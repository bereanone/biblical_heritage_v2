#!/usr/bin/env python3
"""
scripture_reference_detector.py

Detect embedded Bible references in free text and normalize the ones we can
parse. The original reference text is always preserved.
"""

from __future__ import annotations

import re

from elibrary_import_normalizer import NormalizedScriptureReference
from reference_parser import clean_reference_text, parse_reference


_VERSE_PATTERN = re.compile(
    r"(?P<verse>\d+[:.]\d+(?:\s*[-–]\s*\d+)?(?:\s*,\s*\d+(?:\s*[-–]\s*\d+)?)*)"
)
_BOOK_PREFIX_PATTERN = re.compile(
    r"(?P<book>(?:[1-3]\s+)?(?:[A-Z][A-Za-z.]*|of|and|the)(?:\s+(?:[A-Z][A-Za-z.]*|of|and|the)){0,4})\s*$"
)


def _candidate_reference(prefix: str, verse_text: str) -> str | None:
    stripped_prefix = prefix.rstrip(" ,;:()[]{}\"'“”")
    if not stripped_prefix:
        return None

    match = _BOOK_PREFIX_PATTERN.search(stripped_prefix)
    if not match:
        return None
    return clean_reference_text(f"{match.group('book')} {verse_text}")


def detect_scripture_references(text: str) -> list[NormalizedScriptureReference]:
    if not text:
        return []

    detected: list[NormalizedScriptureReference] = []
    seen: set[str] = set()

    for verse_match in _VERSE_PATTERN.finditer(text):
        candidate = _candidate_reference(text[: verse_match.start()], verse_match.group("verse"))
        if not candidate or candidate in seen:
            continue

        parsed = parse_reference(candidate)
        if candidate in seen:
            continue
        seen.add(candidate)

        detected.append(
            NormalizedScriptureReference(
                original_reference=candidate,
                normalized_reference=parsed.reference_text,
                book=parsed.book,
                chapter=parsed.chapter,
                verse_start=parsed.verse_start,
                verse_end=parsed.verse_end,
            )
        )

    return detected

