#!/usr/bin/env python3
"""
text_acquisition_service.py

Parse TXT/HTML source files into normalized eLibrary bundles.
"""

from __future__ import annotations

from dataclasses import dataclass
from html import unescape
from html.parser import HTMLParser
import re

from elibrary_import_normalizer import (
    NormalizedParagraph,
    NormalizedWork,
    NormalizedWorkBundle,
    clean_text,
    file_checksum,
    make_work_id,
)
from scripture_reference_detector import detect_scripture_references
from source_inventory_service import SourceInventoryItem


@dataclass
class _Block:
    kind: str
    level: int | None
    text: str


class VerificationRequiredError(RuntimeError):
    def __init__(self, message: str, source_url: str | None = None) -> None:
        super().__init__(message)
        self.source_url = source_url


_VERIFICATION_PATTERNS = [
    r"cloudflare",
    r"checking your browser before accessing",
    r"verify you are human",
    r"please enable javascript and cookies",
    r"attention required",
    r"security check",
    r"one more step",
    r"browser verification",
]


class _HTMLBlockParser(HTMLParser):
    _BLOCK_TAGS = {
        "article",
        "aside",
        "blockquote",
        "div",
        "figcaption",
        "footer",
        "header",
        "li",
        "p",
        "section",
        "td",
        "th",
        "tr",
    }
    _HEADING_TAGS = {"h1", "h2", "h3", "h4", "h5", "h6"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.blocks: list[_Block] = []
        self._buffer: list[str] = []
        self._current_kind: str | None = None
        self._current_level: int | None = None
        self._skip_depth = 0

    def _flush(self) -> None:
        text = clean_text(" ".join(self._buffer))
        self._buffer.clear()
        if text:
            self.blocks.append(_Block(kind=self._current_kind or "paragraph", level=self._current_level, text=text))
        self._current_kind = None
        self._current_level = None

    def handle_starttag(self, tag: str, attrs):
        if tag in {"script", "style"}:
            self._skip_depth += 1
            return
        if self._skip_depth:
            return
        if tag in self._HEADING_TAGS:
            self._flush()
            self._current_kind = "heading"
            self._current_level = int(tag[1])
        elif tag == "br":
            self._buffer.append("\n")
        elif tag in self._BLOCK_TAGS and self._buffer:
            self._flush()
            self._current_kind = "paragraph"

    def handle_endtag(self, tag: str):
        if tag in {"script", "style"} and self._skip_depth:
            self._skip_depth -= 1
            return
        if self._skip_depth:
            return
        if tag in self._BLOCK_TAGS or tag in self._HEADING_TAGS:
            self._flush()

    def handle_data(self, data: str):
        if self._skip_depth:
            return
        text = clean_text(unescape(data))
        if text:
            self._buffer.append(text)

    def close(self):
        super().close()
        if self._buffer:
            self._flush()


def _document_source_fields(item: SourceInventoryItem) -> dict[str, str | None]:
    return {
        "author": item.author,
        "title": item.title,
        "abbreviation": item.abbreviation,
        "group": item.group,
        "subgroup": item.subgroup,
        "section": item.section,
        "chapter": item.chapter,
        "subchapter": item.subchapter,
        "source_type": item.source_type,
        "source_url": item.source_url,
        "local_source_path": str(item.path),
    }


def _looks_like_verification_page(text: str) -> bool:
    lowered = clean_text(text).lower()
    if not lowered:
        return False

    if any(re.search(pattern, lowered, re.IGNORECASE) for pattern in _VERIFICATION_PATTERNS):
        return True

    cloudflare_hint_count = sum(1 for phrase in ["cf-browser-verification", "cf-challenge", "__cf_bm"] if phrase in lowered)
    if cloudflare_hint_count:
        return True

    short_text = len(lowered.split()) < 80
    if short_text and any(phrase in lowered for phrase in ["javascript", "cookies", "verification"]):
        return True

    return False


def _build_paragraph(
    *,
    paragraph_number: int,
    paragraph_ref: str,
    content_text: str,
    section: str | None,
    chapter: str | None,
    subchapter: str | None,
    page_number: int | None,
) -> NormalizedParagraph:
    refs = detect_scripture_references(content_text)
    return NormalizedParagraph(
        paragraph_number=paragraph_number,
        paragraph_ref=paragraph_ref,
        page_number=page_number,
        section=section,
        chapter=chapter,
        subchapter=subchapter,
        content_text=content_text,
        embedded_scripture_refs=refs,
    )


def _split_text_blocks(text: str) -> list[str]:
    blocks: list[str] = []
    current: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            if current:
                blocks.append(clean_text(" ".join(current)))
                current = []
            continue
        current.append(stripped)
    if current:
        blocks.append(clean_text(" ".join(current)))
    return [block for block in blocks if block]


def _is_heading(block: str) -> bool:
    words = block.split()
    if not words:
        return False
    if len(words) <= 10 and block == block.upper():
        return True
    if len(words) <= 8 and not block.endswith((".", "!", "?", ":")):
        return True
    return False


def parse_text_bundle(item: SourceInventoryItem) -> NormalizedWorkBundle:
    text = item.path.read_text(encoding="utf-8", errors="ignore")
    if _looks_like_verification_page(text):
        raise VerificationRequiredError(
            "Source site verification required. Open this URL in a browser, complete the verification manually, then retry import.",
            source_url=item.source_url,
        )
    return _parse_text_bundle(item, text)


def parse_html_bundle(item: SourceInventoryItem) -> NormalizedWorkBundle:
    text = item.path.read_text(encoding="utf-8", errors="ignore")
    if _looks_like_verification_page(text):
        raise VerificationRequiredError(
            "Source site verification required. Open this URL in a browser, complete the verification manually, then retry import.",
            source_url=item.source_url,
        )
    parser = _HTMLBlockParser()
    parser.feed(text)
    parser.close()
    blocks = [block.text for block in parser.blocks]
    return _build_bundle(item, blocks, source_text=text)


def _parse_text_bundle(item: SourceInventoryItem, text: str) -> NormalizedWorkBundle:
    blocks = _split_text_blocks(text)
    return _build_bundle(item, blocks, source_text=text)


def _build_bundle(item: SourceInventoryItem, blocks: list[str], source_text: str) -> NormalizedWorkBundle:
    work = NormalizedWork(
        work_id=make_work_id(
            title=item.title,
            author=item.author,
            source_type=item.source_type,
            local_source_path=str(item.path),
            source_url=item.source_url,
        ),
        author=item.author,
        title=item.title,
        abbreviation=item.abbreviation,
        group=item.group,
        subgroup=item.subgroup,
        section=item.section,
        chapter=item.chapter,
        subchapter=item.subchapter,
        source_type=item.source_type,
        source_url=item.source_url,
        local_source_path=str(item.path),
        archive_source_path=None,
        import_status="pending",
        source_checksum=file_checksum(item.path),
        source_version=None,
        notes=None,
    )

    paragraphs: list[NormalizedParagraph] = []
    current_section = item.section
    current_chapter = item.chapter
    current_subchapter = item.subchapter

    for index, block in enumerate(blocks, start=1):
        is_heading = _is_heading(block)
        if is_heading and current_chapter is None:
            current_chapter = block
        elif is_heading and current_section is None:
            current_section = block
        elif is_heading and current_subchapter is None:
            current_subchapter = block

        paragraph = _build_paragraph(
            paragraph_number=index,
            paragraph_ref=f"{item.source_type}-{index}",
            content_text=block,
            section=current_section,
            chapter=current_chapter,
            subchapter=current_subchapter,
            page_number=None,
        )
        paragraphs.append(paragraph)

    if not paragraphs and source_text.strip():
        paragraphs.append(
            _build_paragraph(
                paragraph_number=1,
                paragraph_ref=f"{item.source_type}-1",
                content_text=clean_text(source_text),
                section=current_section,
                chapter=current_chapter,
                subchapter=current_subchapter,
                page_number=None,
            )
        )

    return NormalizedWorkBundle(work=work, paragraphs=paragraphs)


def acquire_text_or_html_bundle(item: SourceInventoryItem) -> NormalizedWorkBundle:
    if item.source_type == "txt":
        return parse_text_bundle(item)
    if item.source_type == "html":
        return parse_html_bundle(item)
    raise ValueError(f"Unsupported text/html source type: {item.source_type}")
