#!/usr/bin/env python3
"""
reference_parser.py

Parse Bible references from the workbook into structured fields while keeping
the original reference text intact for display and search.
"""

from __future__ import annotations

from dataclasses import dataclass
import re


@dataclass(frozen=True)
class ParsedReference:
    reference_text: str
    book: str | None
    chapter: int | None
    verse_start: int | None
    verse_end: int | None
    parsed: bool
    failure_reason: str | None = None


_BOOK_ALIASES: dict[str, str] = {
    "gen": "Genesis",
    "genesis": "Genesis",
    "ex": "Exodus",
    "exod": "Exodus",
    "exo": "Exodus",
    "exodus": "Exodus",
    "lev": "Leviticus",
    "leviticus": "Leviticus",
    "num": "Numbers",
    "numbers": "Numbers",
    "deut": "Deuteronomy",
    "deuteronomy": "Deuteronomy",
    "josh": "Joshua",
    "joshua": "Joshua",
    "judg": "Judges",
    "judges": "Judges",
    "ruth": "Ruth",
    "samuel": "1 Samuel",
    "sam": "1 Samuel",
    "1 sam": "1 Samuel",
    "2 sam": "2 Samuel",
    "1 samuel": "1 Samuel",
    "2 samuel": "2 Samuel",
    "1 kings": "1 Kings",
    "2 kings": "2 Kings",
    "1 chron": "1 Chronicles",
    "1 chronicles": "1 Chronicles",
    "2 chron": "2 Chronicles",
    "2 chronicles": "2 Chronicles",
    "ezra": "Ezra",
    "neh": "Nehemiah",
    "nehemiah": "Nehemiah",
    "esth": "Esther",
    "esther": "Esther",
    "job": "Job",
    "ps": "Psalms",
    "psalm": "Psalms",
    "psalms": "Psalms",
    "prov": "Proverbs",
    "proverbs": "Proverbs",
    "eccl": "Ecclesiastes",
    "ecclesiastes": "Ecclesiastes",
    "song of solomon": "Song of Solomon",
    "song of songs": "Song of Solomon",
    "isa": "Isaiah",
    "isaiah": "Isaiah",
    "jer": "Jeremiah",
    "jeremiah": "Jeremiah",
    "lam": "Lamentations",
    "lamentations": "Lamentations",
    "eze": "Ezekiel",
    "ezekiel": "Ezekiel",
    "dan": "Daniel",
    "daniel": "Daniel",
    "hos": "Hosea",
    "hosea": "Hosea",
    "joel": "Joel",
    "amos": "Amos",
    "obad": "Obadiah",
    "obadiah": "Obadiah",
    "jonah": "Jonah",
    "mic": "Micah",
    "micah": "Micah",
    "nah": "Nahum",
    "nahum": "Nahum",
    "hab": "Habakkuk",
    "habakkuk": "Habakkuk",
    "zeph": "Zephaniah",
    "zephaniah": "Zephaniah",
    "hag": "Haggai",
    "haggai": "Haggai",
    "zech": "Zechariah",
    "zechariah": "Zechariah",
    "mal": "Malachi",
    "malachi": "Malachi",
    "matt": "Matthew",
    "matthew": "Matthew",
    "mark": "Mark",
    "luke": "Luke",
    "john": "John",
    "acts": "Acts",
    "rom": "Romans",
    "romans": "Romans",
    "1 cor": "1 Corinthians",
    "1 corinthians": "1 Corinthians",
    "2 cor": "2 Corinthians",
    "2 corinthians": "2 Corinthians",
    "gal": "Galatians",
    "galatians": "Galatians",
    "eph": "Ephesians",
    "ephesians": "Ephesians",
    "phil": "Philippians",
    "philippians": "Philippians",
    "col": "Colossians",
    "colossians": "Colossians",
    "1 thess": "1 Thessalonians",
    "1 thessalonians": "1 Thessalonians",
    "2 thess": "2 Thessalonians",
    "2 thessalonians": "2 Thessalonians",
    "1 tim": "1 Timothy",
    "1 timothy": "1 Timothy",
    "2 tim": "2 Timothy",
    "2 timothy": "2 Timothy",
    "titus": "Titus",
    "philem": "Philemon",
    "philemon": "Philemon",
    "heb": "Hebrews",
    "hebrews": "Hebrews",
    "james": "James",
    "1 pet": "1 Peter",
    "1 peter": "1 Peter",
    "2 pet": "2 Peter",
    "2 peter": "2 Peter",
    "1 john": "1 John",
    "2 john": "2 John",
    "3 john": "3 John",
    "jude": "Jude",
    "rev": "Revelation",
    "revelation": "Revelation",
}

_REFERENCE_PATTERN = re.compile(r"^(?P<book>.+?)\s+(?P<chapter>\d+)(?P<sep>[:.])(?P<verses>[\d,\-\s]+)$")
_ROMAN_PREFIXES = {"i": "1", "ii": "2", "iii": "3"}


def clean_reference_text(value: str) -> str:
    text = value.replace("\r\n", "\n").replace("\r", "\n").strip()
    text = text.strip("“”\"'")
    text = text.strip()
    text = re.sub(r"^[\(\[]+|[\)\]]+$", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def split_reference_chunks(value: str) -> list[str]:
    text = clean_reference_text(value)
    if not text:
        return []
    chunks = [clean_reference_text(part) for part in text.split(";")]
    return [chunk for chunk in chunks if chunk]


def _normalize_book_key(book: str) -> str:
    text = clean_reference_text(book)
    text = text.replace(".", "")
    text = re.sub(r"\s+", " ", text).strip().lower()

    prefix_match = re.match(r"^(i{1,3}|1|2|3)\s+(.*)$", text)
    if prefix_match:
        prefix = prefix_match.group(1)
        rest = prefix_match.group(2).strip()
        if prefix in _ROMAN_PREFIXES:
            prefix = _ROMAN_PREFIXES[prefix]
        text = f"{prefix} {rest}"

    if text == "i sam":
        text = "1 sam"

    return text


def canonicalize_book(book: str) -> str | None:
    key = _normalize_book_key(book)
    if key in _BOOK_ALIASES:
        return _BOOK_ALIASES[key]
    return None


def _strip_trailing_punctuation(text: str) -> str:
    stripped = text.strip()
    while stripped and stripped[-1] in ".,;:)":
        stripped = stripped[:-1].rstrip()
    return stripped


def parse_reference(reference_text: str) -> ParsedReference:
    original = clean_reference_text(reference_text)
    if not original:
        return ParsedReference("", None, None, None, None, False, "empty reference")

    candidate = _strip_trailing_punctuation(original)
    match = _REFERENCE_PATTERN.match(candidate)
    if not match:
        return ParsedReference(original, None, None, None, None, False, "pattern not recognized")

    book = canonicalize_book(match.group("book"))
    if not book:
        return ParsedReference(original, None, None, None, None, False, f"unknown book: {match.group('book').strip()}")

    chapter = int(match.group("chapter"))
    verse_numbers = [int(value) for value in re.findall(r"\d+", match.group("verses"))]
    if not verse_numbers:
        return ParsedReference(original, None, None, None, None, False, "no verse numbers found")

    verse_start = verse_numbers[0]
    verse_end = verse_numbers[-1]
    return ParsedReference(original, book, chapter, verse_start, verse_end, True, None)
