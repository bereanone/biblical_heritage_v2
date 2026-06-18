#!/usr/bin/env python3
"""
elibrary_import_normalizer.py

Shared normalized data structures for eLibrary acquisition.

Acquisition services parse source files into these records before anything is
written to SQLite. That keeps EPUB, HTML, TXT, and future formats on the same
shape before DB persistence.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
from pathlib import Path

from reference_parser import clean_reference_text, parse_reference


@dataclass(frozen=True)
class NormalizedScriptureReference:
    original_reference: str
    normalized_reference: str
    book: str | None
    chapter: int | None
    verse_start: int | None
    verse_end: int | None


@dataclass
class NormalizedParagraph:
    paragraph_number: int | None
    paragraph_ref: str | None
    page_number: int | None
    section: str | None
    chapter: str | None
    subchapter: str | None
    content_text: str
    embedded_scripture_refs: list[NormalizedScriptureReference] = field(default_factory=list)


@dataclass
class NormalizedWork:
    work_id: str
    author: str | None
    title: str
    abbreviation: str | None
    group: str | None
    subgroup: str | None
    section: str | None
    chapter: str | None
    subchapter: str | None
    source_type: str
    source_url: str | None
    local_source_path: str | None
    archive_source_path: str | None
    import_status: str = "pending"
    source_checksum: str | None = None
    source_version: str | None = None
    notes: str | None = None


@dataclass
class NormalizedWorkBundle:
    work: NormalizedWork
    paragraphs: list[NormalizedParagraph] = field(default_factory=list)


def clean_text(value: object) -> str:
    if value is None:
        return ""

    text = str(value).replace("\r\n", "\n").replace("\r", "\n")
    text = "\n".join(line.strip() for line in text.split("\n"))
    text = " ".join(segment for segment in text.split())
    return text.strip()


def content_checksum(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def file_checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def make_work_id(
    *,
    title: str,
    author: str | None,
    source_type: str,
    local_source_path: str | None,
    source_url: str | None = None,
) -> str:
    basis = "|".join(
        [
            clean_text(title),
            clean_text(author or ""),
            clean_text(source_type),
            clean_text(local_source_path or ""),
            clean_text(source_url or ""),
        ]
    )
    return hashlib.sha256(basis.encode("utf-8")).hexdigest()


def normalize_reference_text(reference_text: str) -> str:
    parsed = parse_reference(clean_reference_text(reference_text))
    return parsed.reference_text

