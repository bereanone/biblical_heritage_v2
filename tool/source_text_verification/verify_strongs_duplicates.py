#!/usr/bin/env python3
"""Scan bible_base.db's Greek/Hebrew tokens for Strong's-number duplication or
mis-split-gloss errors, by comparing per-verse word counts against the
Textus Receptus (Greek NT) and the Masoretic/Leningrad text (Hebrew OT).

Background
----------
Reported case: Revelation 1:1 stores the Greek word "doulois" (servants,
G1401) as TWO separate tokens in the same verse -- one glossed "unto" and
one glossed "servants" -- when the Textus Receptus (Scrivener 1894, per
STEPBible's TAGNT, which is unanimous across NA/TR/Byz/WH/Treg/SBL for this
verse) contains "doulois" exactly ONCE. The same verse independently
duplicates "doulo" (G1401, servant-DAT-SG for John) and "esemanen" (G4591,
signified) the same way. The root cause looks like a token-import bug: when
one Greek word required two English words to translate (e.g. the dative
case rendered as "unto ... servants"), the importer sometimes emitted one
token row per English word instead of per Greek word, and gave both rows
the same ancient_text/Strong's number.

Reference data
--------------
STEPBible-Data "Translators Amalgamated" Greek NT / Hebrew OT
(CC BY 4.0), https://github.com/STEPBible/STEPBible-Data
  - TAGNT (Mat-Jhn, Act-Rev): every word in NA27/28, TR (Scrivener 1894),
    Byz, WH, Treg, SBL, Tyndale House editions, with per-edition tagging.
    We only count a word if "TR" is one of its listed editions, since TR
    is what the KJV (and this database's English glosses) are based on.
  - TAHOT (Gen-Deu, Jos-Est, Job-Sng, Isa-Mal): the Hebrew OT as found in
    the Westminster Leningrad Codex (the standard machine-readable
    Masoretic Text), word-per-line, with the lexical root's Strong's
    number in curly braces (prefixes like "the"/"and"/"in" get their own
    non-bracketed H9xxx function-word codes, which this database does not
    tokenize separately -- confirmed against Gen 1:1, where bible_tokens
    has exactly one row per TAHOT root word).

Downloaded once into source-data/stepbible/ (gitignored) and cached there.

Method
------
For each verse, count how many times each root Strong's number occurs:
  - in bible_tokens (this app's database)
  - in the reference text (TR-tagged rows only for NT; all rows for OT)

If the database has MORE occurrences of a Strong's number in a verse than
the source text does, that is evidence of a duplicated/mis-split token.
Two tokens sharing the *exact same* Greek/Hebrew spelling and Strong's
number in one verse ("exact duplicate pair") is the strongest signal and
is reported as HIGH confidence; a bare over-count without matching
spelling is reported at MEDIUM confidence since it can also result from
legitimate textual variation between manuscript families.

Known limitations
------------------
- This is a count-based comparison. It will NOT catch a wrong-Strong's-
  number tag that doesn't change the per-verse tally (e.g. one word
  swapped for a different, equally-frequent word in the same verse).
- A handful of verses have documented KJV-vs-NRSV versification
  differences (see the TAGNT file header) which can produce benign
  mismatches; these aren't specially suppressed, just reported like any
  other finding, so treat isolated single-verse-off findings with that in
  mind.

Usage
-----
    python3 tool/source_text_verification/verify_strongs_duplicates.py

Writes:
    tool/audits/strongs_duplication_scan_report.csv
    tool/audits/strongs_duplication_scan_report.json
"""

from __future__ import annotations

import csv
import json
import re
import sqlite3
import sys
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = REPO_ROOT / "assets" / "databases" / "bible_base.db"
CACHE_DIR = REPO_ROOT / "source-data" / "stepbible"
REPORT_DIR = REPO_ROOT / "tool" / "audits"

STEPBIBLE_BASE = (
    "https://raw.githubusercontent.com/STEPBible/STEPBible-Data/master/"
    "Translators%20Amalgamated%20OT%2BNT/"
)

NT_FILES = [
    "TAGNT Mat-Jhn - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt",
    "TAGNT Act-Rev - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt",
]
OT_FILES = [
    "TAHOT Gen-Deu - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt",
    "TAHOT Jos-Est - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt",
    "TAHOT Job-Sng - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt",
    "TAHOT Isa-Mal - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt",
]

BOOK_ABBR = {
    1: "Gen", 2: "Exo", 3: "Lev", 4: "Num", 5: "Deu", 6: "Jos", 7: "Jdg", 8: "Rut",
    9: "1Sa", 10: "2Sa", 11: "1Ki", 12: "2Ki", 13: "1Ch", 14: "2Ch", 15: "Ezr",
    16: "Neh", 17: "Est", 18: "Job", 19: "Psa", 20: "Pro", 21: "Ecc", 22: "Sng",
    23: "Isa", 24: "Jer", 25: "Lam", 26: "Ezk", 27: "Dan", 28: "Hos", 29: "Jol",
    30: "Amo", 31: "Oba", 32: "Jon", 33: "Mic", 34: "Nam", 35: "Hab", 36: "Zep",
    37: "Hag", 38: "Zec", 39: "Mal", 40: "Mat", 41: "Mrk", 42: "Luk", 43: "Jhn",
    44: "Act", 45: "Rom", 46: "1Co", 47: "2Co", 48: "Gal", 49: "Eph", 50: "Php",
    51: "Col", 52: "1Th", 53: "2Th", 54: "1Ti", 55: "2Ti", 56: "Tit", 57: "Phm",
    58: "Heb", 59: "Jas", 60: "1Pe", 61: "2Pe", 62: "1Jn", 63: "2Jn", 64: "3Jn",
    65: "Jud", 66: "Rev",
}

REF_RE = re.compile(r"^([1-3]?[A-Za-z]{2,3})\.(\d+)\.(\d+)#\d+")
STRONG_RE = re.compile(r"^([GH])0*(\d+)")
TAHOT_ROOT_RE = re.compile(r"\{(H0*\d+)[A-Za-z]*\}")


def download_if_missing() -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    for name in NT_FILES + OT_FILES:
        dest = CACHE_DIR / name
        if dest.exists() and dest.stat().st_size > 0:
            continue
        url = STEPBIBLE_BASE + urllib.parse.quote(name)
        print(f"Downloading {name} ...", file=sys.stderr)
        urllib.request.urlretrieve(url, dest)


def normalize_strong(raw: str) -> str | None:
    m = STRONG_RE.match(raw)
    if not m:
        return None
    letter, digits = m.groups()
    return f"{letter}{int(digits):04d}"


def parse_tagnt(path: Path, ref_counts: dict, ref_words: dict) -> None:
    with path.open(encoding="utf-8") as f:
        for line in f:
            if "\t" not in line:
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 6:
                continue
            m = REF_RE.match(cols[0])
            if not m:
                continue
            editions = cols[5]
            if "TR" not in editions.split("+"):
                continue
            book, chapter, verse = m.group(1), int(m.group(2)), int(m.group(3))
            strong_field = cols[3].split("=")[0]
            strong = normalize_strong(strong_field)
            if not strong:
                continue
            key = (book, chapter, verse)
            ref_counts.setdefault(key, Counter())[strong] += 1
            greek = cols[1].split(" (")[0].strip()
            ref_words.setdefault(key, []).append((greek, strong))


def parse_tahot(path: Path, ref_counts: dict, ref_words: dict) -> None:
    with path.open(encoding="utf-8") as f:
        for line in f:
            if "\t" not in line:
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 5:
                continue
            m = REF_RE.match(cols[0])
            if not m:
                continue
            book, chapter, verse = m.group(1), int(m.group(2)), int(m.group(3))
            dstrongs = cols[4]
            roots = TAHOT_ROOT_RE.findall(dstrongs)
            if not roots:
                continue
            key = (book, chapter, verse)
            hebrew = cols[1].strip()
            for r in roots:
                strong = normalize_strong(r)
                if not strong:
                    continue
                ref_counts.setdefault(key, Counter())[strong] += 1
                ref_words.setdefault(key, []).append((hebrew, strong))


def load_reference() -> tuple[dict, dict]:
    ref_counts: dict = {}
    ref_words: dict = {}
    for name in NT_FILES:
        parse_tagnt(CACHE_DIR / name, ref_counts, ref_words)
    for name in OT_FILES:
        parse_tahot(CACHE_DIR / name, ref_counts, ref_words)
    return ref_counts, ref_words


def load_db_tokens(conn: sqlite3.Connection) -> dict:
    query = """
        SELECT b.book_number, b.chapter, b.block_index AS verse,
               t.token_id, t.verse_index, t.english_gloss, t.ancient_text,
               t.strongs_canonical
        FROM bible_tokens t
        JOIN bible_blocks b ON b.id = t.block_id
        ORDER BY b.book_number, b.chapter, b.block_index, t.verse_index
    """
    by_verse: dict = defaultdict(list)
    for book_number, chapter, verse, token_id, verse_index, gloss, ancient_text, strongs in conn.execute(query):
        abbr = BOOK_ABBR.get(book_number)
        if not abbr:
            continue
        strong = normalize_strong(strongs) if strongs else None
        by_verse[(abbr, chapter, verse)].append({
            "token_id": token_id,
            "verse_index": verse_index,
            "gloss": gloss,
            "ancient_text": ancient_text,
            "strong": strong,
        })
    return by_verse


def load_dictionary(conn: sqlite3.Connection) -> dict:
    out = {}
    for strongs_canonical, lemma, short_definition in conn.execute(
        "SELECT strongs_canonical, lemma, short_definition FROM strongs_dictionary"
    ):
        strong = normalize_strong(strongs_canonical) if strongs_canonical else None
        if strong:
            out[strong] = (lemma, short_definition)
    return out


def compare(db_by_verse: dict, ref_counts: dict, ref_words: dict) -> tuple[list, int, list]:
    findings = []
    verses_scanned = 0
    verses_no_reference = []
    for key, tokens in db_by_verse.items():
        ref = ref_counts.get(key)
        if ref is None:
            verses_no_reference.append(key)
            continue
        verses_scanned += 1
        db_counter = Counter(t["strong"] for t in tokens if t["strong"])
        for strong, db_n in db_counter.items():
            ref_n = ref.get(strong, 0)
            if db_n <= ref_n:
                continue
            matches = [t for t in tokens if t["strong"] == strong]
            texts = Counter(m["ancient_text"].strip().lower() for m in matches if m["ancient_text"])
            exact_dupe = any(c >= 2 for c in texts.values())
            findings.append({
                "book": key[0], "chapter": key[1], "verse": key[2],
                "strong": strong,
                "db_count": db_n, "source_count": ref_n,
                "confidence": "HIGH" if exact_dupe else "MEDIUM",
                "db_tokens": matches,
                "source_words": [w for w, s in ref_words.get(key, []) if s == strong],
            })
    return findings, verses_scanned, verses_no_reference


def write_reports(findings: list, dictionary: dict) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    findings.sort(key=lambda f: (0 if f["confidence"] == "HIGH" else 1, f["book"], f["chapter"], f["verse"]))

    csv_path = REPORT_DIR / "strongs_duplication_scan_report.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "confidence", "book", "chapter", "verse", "strongs", "lemma", "gloss_meaning",
            "db_count", "source_count", "db_ancient_texts", "db_english_glosses",
            "source_words", "db_token_ids",
        ])
        for item in findings:
            lemma, definition = dictionary.get(item["strong"], ("", ""))
            w.writerow([
                item["confidence"], item["book"], item["chapter"], item["verse"], item["strong"],
                lemma, definition, item["db_count"], item["source_count"],
                " | ".join(t["ancient_text"] or "" for t in item["db_tokens"]),
                " | ".join(t["gloss"] or "" for t in item["db_tokens"]),
                " | ".join(item["source_words"]),
                " | ".join(str(t["token_id"]) for t in item["db_tokens"]),
            ])

    json_path = REPORT_DIR / "strongs_duplication_scan_report.json"
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(findings, f, ensure_ascii=False, indent=2)

    print(f"Wrote {csv_path}")
    print(f"Wrote {json_path}")


def main() -> None:
    download_if_missing()
    print("Parsing reference texts (TR-tagged Greek NT + Masoretic Hebrew OT)...", file=sys.stderr)
    ref_counts, ref_words = load_reference()

    conn = sqlite3.connect(str(DB_PATH))
    try:
        db_by_verse = load_db_tokens(conn)
        dictionary = load_dictionary(conn)
    finally:
        conn.close()

    findings, verses_scanned, verses_no_reference = compare(db_by_verse, ref_counts, ref_words)
    write_reports(findings, dictionary)

    high = [x for x in findings if x["confidence"] == "HIGH"]
    medium = [x for x in findings if x["confidence"] == "MEDIUM"]

    print()
    print(f"Verses scanned:            {verses_scanned}")
    print(f"Verses with no reference:  {len(verses_no_reference)}")
    print(f"HIGH-confidence findings:  {len(high)}  (exact duplicate word+Strong's pair in one verse)")
    print(f"MEDIUM-confidence findings:{len(medium)}  (Strong's over-count, spelling differs)")

    rev11 = [x for x in findings if x["book"] == "Rev" and x["chapter"] == 1 and x["verse"] == 1]
    print()
    print(f"Rev.1.1 findings: {len(rev11)}")
    for item in rev11:
        print(f"  {item['confidence']}  {item['strong']}  db={item['db_count']} source={item['source_count']}  "
              f"glosses={[t['gloss'] for t in item['db_tokens']]}")


if __name__ == "__main__":
    main()
