"""Build a small, read-only Abbott-Smith lookup from its public-domain TEI.

The TEI input remains unchanged. References link only when their exact OSIS
book/chapter/verse exists in the bundled Bible; all other citations stay text.
"""

import argparse
import hashlib
import json
import re
import sqlite3
import xml.etree.ElementTree as ET
from pathlib import Path


SOURCE_URL = "https://github.com/translatable-exegetical-tools/Abbott-Smith"
SOURCE_COMMIT = "8c00cb244761aa23659421a8cbbbf7a3b27b7d59"
OSIS_BOOKS = (
    "Gen Exod Lev Num Deut Josh Judg Ruth 1Sam 2Sam 1Kgs 2Kgs 1Chr 2Chr "
    "Ezra Neh Esth Job Ps Prov Eccl Song Isa Jer Lam Ezek Dan Hos Joel Amos "
    "Obad Jonah Mic Nah Hab Zeph Hag Zech Mal Matt Mark Luke John Acts Rom "
    "1Cor 2Cor Gal Eph Phil Col 1Thess 2Thess 1Tim 2Tim Titus Phlm Heb Jas "
    "1Pet 2Pet 1John 2John 3John Jude Rev"
).split()
BOOK_NUMBER = {book: index + 1 for index, book in enumerate(OSIS_BOOKS)}
EXACT_REF = re.compile(r"^([1-3]?[A-Za-z]+)\.(\d+)\.(\d+)$")
STRONGS = re.compile(r"^G0*(\d+)$")


def tag_name(node):
    return node.tag.rsplit("}", 1)[-1]


def block_for_ref(osis_ref, blocks):
    match = EXACT_REF.fullmatch(osis_ref or "")
    if not match:
        return None
    book = BOOK_NUMBER.get(match.group(1))
    if book is None:
        return None
    return blocks.get((book, int(match.group(2)), int(match.group(3))))


def segments(node, blocks, *, skip_nested_senses=False):
    pieces = []

    def inner_text(current):
        value = current.text or ""
        for child in current:
            value += inner_text(child) + (child.tail or "")
        return value

    def append_text(value):
        if not value:
            return
        value = re.sub(r"\s+", " ", value)
        if pieces and "block_id" not in pieces[-1]:
            pieces[-1]["text"] += value
        else:
            pieces.append({"text": value})

    def walk(current):
        append_text(current.text)
        for child in current:
            if skip_nested_senses and tag_name(child) == "sense":
                append_text(child.tail)
                continue
            if tag_name(child) == "ref":
                label = inner_text(child).strip()
                block_id = block_for_ref(child.get("osisRef"), blocks)
                if label and block_id is not None:
                    pieces.append({"text": label, "block_id": block_id})
                else:
                    append_text(label)
            else:
                walk(child)
            append_text(child.tail)

    walk(node)
    return pieces


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tei", type=Path, required=True)
    parser.add_argument("--bible", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    tei_bytes = args.tei.read_bytes()
    source_hash = hashlib.sha256(tei_bytes).hexdigest()
    root = ET.fromstring(tei_bytes)
    with sqlite3.connect(f"file:{args.bible}?mode=ro", uri=True) as bible:
        blocks = {
            (book, chapter, verse): block_id
            for block_id, book, chapter, verse in bible.execute(
                "SELECT id, book_number, chapter, block_index FROM bible_blocks"
            )
        }

    entries = {}
    for entry in root.iter():
        if tag_name(entry) != "entry":
            continue
        strongs_ids = [
            f"G{int(match.group(1)):04d}"
            for raw in entry.get("n", "").split("|")
            if (match := STRONGS.fullmatch(raw))
        ]
        if not strongs_ids:
            continue
        senses = []

        def collect_senses(sense, parent_number=""):
            own_number = sense.get("n", "").strip()
            number = " ".join(part for part in (parent_number, own_number) if part)
            parts = segments(sense, blocks, skip_nested_senses=True)
            if not "".join(part["text"] for part in parts).strip():
                parts = []
            if parts:
                senses.append({"number": number, "parts": parts})
            for child in sense:
                if tag_name(child) == "sense":
                    collect_senses(child, number)

        for sense in entry:
            if tag_name(sense) == "sense":
                collect_senses(sense)
        related = [segments(node, blocks) for node in entry if tag_name(node) == "re"]
        if not senses:
            # Some Abbott-Smith articles give only a spelling or see-under
            # note. Preserve that note, but never borrow another headword's
            # senses as though they belonged to this Strong's number.
            related = [
                segments(node, blocks) for node in entry if tag_name(node) == "form"
            ]
            if not any("".join(part["text"] for part in note).strip() for note in related):
                continue
        for strongs in strongs_ids:
            if strongs not in entries or (senses and not entries[strongs]["senses"]):
                entries[strongs] = {"senses": senses, "related": related}

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        args.output.unlink()
    with sqlite3.connect(args.output) as output:
        output.execute("CREATE TABLE entries (strongs TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        output.execute("CREATE TABLE provenance (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        output.executemany(
            "INSERT INTO entries VALUES (?, ?)",
            ((key, json.dumps(value, ensure_ascii=False, separators=(",", ":")))
             for key, value in sorted(entries.items())),
        )
        output.executemany(
            "INSERT INTO provenance VALUES (?, ?)",
            [
                ("title", "George Abbott-Smith, A Manual Greek Lexicon of the New Testament (1922)"),
                ("source_url", SOURCE_URL),
                ("source_commit", SOURCE_COMMIT),
                ("source_sha256", source_hash),
                ("license", "Public Domain, per TEI project README"),
            ],
        )
        print(
            f"{len(entries)} Greek entries; "
            f"{sum(len(value['senses']) for value in entries.values())} senses; "
            f"{sum('block_id' in part for value in entries.values() for sense in value['senses'] for part in sense['parts'])} linked references"
        )
        print(f"source sha256 {source_hash}")


if __name__ == "__main__":
    main()
