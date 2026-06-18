#!/usr/bin/env python3
"""
epub_acquisition_service.py

Parse EPUB files into normalized eLibrary bundles.
"""

from __future__ import annotations

from dataclasses import dataclass
from html import unescape
from html.parser import HTMLParser
import posixpath
from pathlib import Path
import zipfile
import xml.etree.ElementTree as ET

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


_CONTAINER_NS = "urn:oasis:names:tc:opendocument:xmlns:container"
_OPF_NS = {
    "opf": "http://www.idpf.org/2007/opf",
    "dc": "http://purl.org/dc/elements/1.1/",
}


@dataclass
class _Block:
    kind: str
    level: int | None
    text: str


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


def _read_rootfile_path(zf: zipfile.ZipFile) -> str:
    container = ET.fromstring(zf.read("META-INF/container.xml"))
    rootfile = container.find(f".//{{{_CONTAINER_NS}}}rootfile")
    if rootfile is None:
        raise ValueError("EPUB container does not declare a rootfile.")
    full_path = rootfile.attrib.get("full-path")
    if not full_path:
        raise ValueError("EPUB rootfile is missing a full-path attribute.")
    return full_path


def _find_text(root: ET.Element, xpath: str) -> list[str]:
    values: list[str] = []
    for node in root.findall(xpath, _OPF_NS):
        text = clean_text("".join(node.itertext()))
        if text:
            values.append(text)
    return values


def _resolve_spine_path(opf_path: str, href: str) -> str:
    base_dir = posixpath.dirname(opf_path)
    return posixpath.normpath(posixpath.join(base_dir, href))


def _extract_blocks_from_markup(markup: str) -> list[_Block]:
    parser = _HTMLBlockParser()
    parser.feed(markup)
    parser.close()
    return [block for block in parser.blocks if block.text]


def _work_id_from_metadata(_identifier: str | None, item: SourceInventoryItem, source_url: str | None) -> str:
    return make_work_id(
        title=item.title,
        author=item.author,
        source_type="epub",
        local_source_path=str(item.path),
        source_url=source_url,
    )


def _paragraph_from_block(
    *,
    paragraph_number: int,
    paragraph_ref: str,
    text: str,
    section: str | None,
    chapter: str | None,
    subchapter: str | None,
    page_number: int | None,
) -> NormalizedParagraph:
    refs = detect_scripture_references(text)
    return NormalizedParagraph(
        paragraph_number=paragraph_number,
        paragraph_ref=paragraph_ref,
        page_number=page_number,
        section=section,
        chapter=chapter,
        subchapter=subchapter,
        content_text=text,
        embedded_scripture_refs=refs,
    )


def parse_epub_bundle(item: SourceInventoryItem) -> NormalizedWorkBundle:
    with zipfile.ZipFile(item.path) as zf:
        opf_path = _read_rootfile_path(zf)
        opf_root = ET.fromstring(zf.read(opf_path))
        manifest = opf_root.find("opf:manifest", _OPF_NS)
        spine = opf_root.find("opf:spine", _OPF_NS)
        if manifest is None or spine is None:
            raise ValueError("EPUB package is missing manifest or spine.")

        title_candidates = _find_text(opf_root, "opf:metadata/dc:title") or [item.title]
        author_candidates = _find_text(opf_root, "opf:metadata/dc:creator")
        identifier_candidates = _find_text(opf_root, "opf:metadata/dc:identifier")
        language_candidates = _find_text(opf_root, "opf:metadata/dc:language")

        title = title_candidates[0]
        author = author_candidates[0] if author_candidates else item.author
        identifier = identifier_candidates[0] if identifier_candidates else None
        source_version = language_candidates[0] if language_candidates else None

        manifest_map: dict[str, tuple[str, str | None]] = {}
        for node in manifest.findall("opf:item", _OPF_NS):
            item_id = node.attrib.get("id")
            href = node.attrib.get("href")
            media_type = node.attrib.get("media-type")
            if item_id and href:
                manifest_map[item_id] = (_resolve_spine_path(opf_path, href), media_type)

        spine_item_ids = [node.attrib.get("idref") for node in spine.findall("opf:itemref", _OPF_NS)]
        work = NormalizedWork(
            work_id=_work_id_from_metadata(identifier, item, source_url=None),
            author=author,
            title=title,
            abbreviation=item.abbreviation,
            group=item.group,
            subgroup=item.subgroup,
            section=item.section,
            chapter=item.chapter,
            subchapter=item.subchapter,
            source_type="epub",
            source_url=None,
            local_source_path=str(item.path),
            archive_source_path=str(item.path),
            import_status="pending",
            source_checksum=file_checksum(item.path),
            source_version=identifier or source_version,
            notes=f"EPUB language: {source_version}" if source_version else None,
        )

        paragraphs: list[NormalizedParagraph] = []
        paragraph_number = 0
        current_section = item.section
        current_chapter = item.chapter or title
        current_subchapter = item.subchapter

        for spine_index, item_id in enumerate(spine_item_ids, start=1):
            if not item_id:
                continue
            manifest_entry = manifest_map.get(item_id)
            if manifest_entry is None:
                continue
            doc_path, media_type = manifest_entry
            if media_type not in {"application/xhtml+xml", "text/html", "application/xml"}:
                continue

            try:
                markup = zf.read(doc_path).decode("utf-8", errors="ignore")
            except KeyError:
                continue

            blocks = _extract_blocks_from_markup(markup)
            doc_chapter = current_chapter
            for block_index, block in enumerate(blocks, start=1):
                block_text = block.text
                if block.kind == "heading" and block.level is not None:
                    if block.level <= 1:
                        doc_chapter = block_text
                        current_chapter = block_text
                    elif block.level == 2:
                        current_section = block_text
                    elif block.level == 3:
                        current_subchapter = block_text
                elif block_index == 1 and len(block_text.split()) <= 12:
                    doc_chapter = block_text
                    current_chapter = block_text

                paragraph_number += 1
                paragraph_ref = f"{spine_index}:{block_index}"
                paragraphs.append(
                    _paragraph_from_block(
                        paragraph_number=paragraph_number,
                        paragraph_ref=paragraph_ref,
                        text=block_text,
                        section=current_section,
                        chapter=doc_chapter,
                        subchapter=current_subchapter,
                        page_number=None,
                    )
                )

        if not paragraphs:
            raise ValueError(f"EPUB {item.path} did not yield any importable paragraphs.")

        return NormalizedWorkBundle(work=work, paragraphs=paragraphs)
