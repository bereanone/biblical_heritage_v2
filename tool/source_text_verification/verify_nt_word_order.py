#!/usr/bin/env python3
"""Strict verse-by-verse, word-by-word verification of the New Testament
Greek in bible_tokens against the Textus Receptus (Scrivener 1894), as
encoded in STEPBible-Data's TAGNT (Translators Amalgamated Greek NT).

This is a follow-up to verify_strongs_duplicates.py. That script only
compared per-verse Strong's-number *counts*. This script compares the
actual word content and, separately, the actual word sequence.

Reference source and edition
-----------------------------
STEPBible-Data "Translators Amalgamated Greek New Testament" (TAGNT),
CC BY 4.0, https://github.com/STEPBible/STEPBible-Data
  Translators%20Amalgamated%20OT%2BNT/TAGNT Mat-Jhn ... .txt
  Translators%20Amalgamated%20OT%2BNT/TAGNT Act-Rev ... .txt

TAGNT is an amalgamated/interlinear-critical-apparatus file: for every verse
it lists EVERY word found in ANY of NA27/28, TR, Byz, WH, Treg, SBL, Tyndale
House, tagged with a "Word & Type" code (e.g. "Mat.1.1#06=NKO") whose
letters indicate which manuscript-tradition group(s) contain that word:
    N = Nestle-Aland (Ancient / modern critical text)
    K = "Traditional" -- the KJV translators' Greek text, i.e. the Textus
        Receptus of Scrivener's 1894 (TAGNT's own definition of "K")
    O = Other editions
This script extracts the Scrivener/TR-specific reading for every word that
carries a "K" in its type code:
  1. If "TR" is one of the joined names in the row's "editions" column, the
     row's own Greek text/dStrongs IS the TR reading -- used as-is.
  2. Otherwise TR must be named in the "Meaning variants" column's
     "in: ..." list (a genuinely different word/Strong's from the row's
     displayed text) -- that alternate word/Strong's is used instead.
  3. Separately, if the "Spelling variants" column also names TR (e.g.
     "+TR: \u0394\u03b1\u03b2\u1f76\u03b4 ;"), that is recorded as a *documented
     print-edition spelling variant* -- exactly the "known TR/Scrivener
     1894 print-edition variant" this audit must NOT flag as an error
     (confirmed against Matthew 1:1, where this DB stores "\u03b4\u03b1\u03b2\u03b9\u03b4",
     the Scrivener-specific spelling, not the NA-preferred "\u03b4\u03b1\u03c5\u03b9\u03b4"
     shown as TAGNT's primary display text for that row).

A critical discovery during development, which shapes the method below:
--------------------------------------------------------------------------
**bible_tokens does NOT store Greek words in Greek syntactic order.** It
stores them in the order the KJV English translation reads (a "reverse
interlinear" layout, standard in interlinear study-Bible software). E.g.
John 11:35 "Jesus wept" is TR "\u1f10\u03b4\u03ac\u03ba\u03c1\u03c5\u03c3\u03b5\u03bd \u1f41 \u1f38\u03b7\u03c3\u03bf\u1fe6\u03c2" (wept / the / Jesus)
but this DB stores it as "\u1f41 \u1f38\u03b7\u03c3\u03bf\u1fe6\u03c2 \u1f10\u03b4\u03ac\u03ba\u03c1\u03c5\u03c3\u03b5\u03bd" (the / Jesus / wept) --
matching English word order exactly, not Greek. This is confirmed as
systematic (1 Corinthians 1:2 similarly reorders "in every place" to where
it falls in the English clause, not the Greek clause) and is a deliberate
design characteristic of this database, not textual corruption. A strict
Greek-order-vs-DB-order positional diff therefore flags the overwhelming
majority of NT verses (measured: 7,878 / 7,948 = 99%) almost entirely
because of this reordering cascade, which would bury genuine content
errors under reordering noise.

To separate the two, this script reports TWO layers per verse:
  1. CONTENT (primary, order-independent): are the same words, with the
     same Strong's numbers, present -- regardless of position? This is
     the layer that answers "is the Greek text itself correct." Matching
     is done via greedy multiset reconciliation (see match_verse_content
     below), not difflib, specifically because position carries no
     textual-correctness signal in this DB.
  2. ORDER (informational only, not counted as an error): does the DB's
     token order match TR's Greek syntactic order? This is expected to
     differ in the large majority of verses by design (see above) and is
     reported purely as a per-verse yes/no note plus an aggregate stat,
     not folded into the content error counts.

bible_tokens.ancient_text has no accents, no breathing marks, no
punctuation, and is lower-case. Both sides of every comparison are
normalized the same way (Unicode NFD decomposition, combining marks
stripped, trailing punctuation stripped, lower-cased, NFC recomposed)
before comparing.

Method (content layer)
-----------------------
For each verse, greedily reconcile the TR word list against the DB token
list as multisets, in three passes, from most to least specific match:
  A. exact match: same normalized text (or a documented TR spelling
     variant / movable-nu / elision equivalent) AND same Strong's number
     -> consumed, no issue.
  B. text match only: same normalized text, different Strong's number
     -> "strongs_mismatch" (the word is right, the Strong's tag is wrong).
  C. Strong's match only: same Strong's number, different normalized text
     -> "word_substitution" (same lexeme tagged, but a different
     inflected form/spelling than TR has in this verse).
  D. Left over on the TR side -> "missing_word" (no candidate anywhere in
     the verse, by either text or Strong's).
  E. Left over on the DB side -> "extra_word" (no TR counterpart anywhere
     in the verse).
Each pass consumes candidates greedily; ties among interchangeable
duplicate words (e.g. multiple plain "\u03ba\u03b1\u03af"/"and") are broken arbitrarily
since such words are not distinguishable from each other by text or
Strong's alone.

Known limitations
------------------
- Greedy multiset matching, not optimal bipartite matching -- for the rare
  verse with several words of the same Strong's number in different
  inflected forms, the specific pairing reported in a "word_substitution"
  finding may not be the pairing a human collator would choose, though the
  aggregate issue counts are still correct.
- Versification differences (TAGNT follows NRSV, this DB follows KJV
  versification) mean a handful of verses have no reference match; these
  are excluded from the scan, not counted as clean.
- This is a Strong's-tagged textual collation against STEPBible's TAGNT
  encoding of Scrivener 1894, not a manuscript collation against a scanned
  facsimile of the print edition.
- This is a **verification/reporting pass only** -- bible_tokens and all
  other tables were not modified.

Usage
-----
    python3 tool/source_text_verification/verify_nt_word_order.py
    python3 tool/source_text_verification/verify_nt_word_order.py --debug-verse Mat.1.1

Writes:
    tool/audits/nt_word_order_verification_report.csv
    tool/audits/nt_word_order_verification_report.json
    tool/audits/nt_word_order_verification_summary.md
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sqlite3
import sys
import unicodedata
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

BOOK_ABBR = {
    40: "Mat", 41: "Mrk", 42: "Luk", 43: "Jhn",
    44: "Act", 45: "Rom", 46: "1Co", 47: "2Co", 48: "Gal", 49: "Eph", 50: "Php",
    51: "Col", 52: "1Th", 53: "2Th", 54: "1Ti", 55: "2Ti", 56: "Tit", 57: "Phm",
    58: "Heb", 59: "Jas", 60: "1Pe", 61: "2Pe", 62: "1Jn", 63: "2Jn", 64: "3Jn",
    65: "Jud", 66: "Rev",
}

ROW_RE = re.compile(r"^([1-3]?[A-Za-z]{2,3})\.(\d+)\.(\d+)#(\d+)=(\S+)$")
STRONG_RE = re.compile(r"^([GH])0*(\d+)")
DSTRONG_RE = re.compile(r"^([A-Za-z]?\d+[A-Za-z]*)")
STRONG_CODE_RE = re.compile(r"^[GH]\d+[A-Za-z]*$")
MEANING_VARIANT_RE = re.compile(
    r"^(?P<greek>.+?)\s*\([a-zA-Z]=[^)]*\)\s*(?P<gloss>.*?)\s*-\s*"
    r"(?P<strong>[GH]\d+[A-Za-z]*)=(?P<parse>\S+)\s+in:\s*(?P<editions>.+)$"
)
SPELLING_VARIANT_TR_RE = re.compile(r"([+A-Za-z]*\bTR\b[+A-Za-z]*)\s*:\s*([^;]+);?")
DISPLACEMENT_SUFFIX_RE = re.compile(r"[»«]\d+$")

GREEK_LETTER_CATEGORIES = {"Lu", "Ll"}


def strip_trailing_non_letters(text: str) -> str:
    """Strip a run of trailing non-letter characters -- punctuation
    (.,;·;:'"()[]) as well as odd marks TAGNT sometimes appends, e.g. the
    pilcrow "¶" used as a paragraph-break marker (confirmed via 1
    Corinthians 1:3's "Χριστοῦ.¶") or the koronis/elision mark "᾽" (e.g.
    "δι᾽", "καθ᾽"). Uses Unicode category (Lu/Ll) rather than a codepoint
    range, since the Greek Extended block also contains non-letter spacing
    diacritics (e.g. U+1FBD KORONIS) that a naive range check would wrongly
    keep."""
    end = len(text)
    while end > 0 and unicodedata.category(text[end - 1]) not in GREEK_LETTER_CATEGORIES:
        end -= 1
    return text[:end]


def normalize_strong(raw: str) -> str | None:
    if not raw:
        return None
    m = STRONG_RE.match(raw.strip())
    if not m:
        return None
    letter, digits = m.groups()
    return f"{letter}{int(digits):04d}"


def normalize_greek(raw: str) -> str:
    """Strip accents/breathing/iota-subscript, punctuation, and case --
    matching the format bible_tokens.ancient_text is stored in."""
    if not raw:
        return ""
    text = raw.split(" (")[0].strip()  # drop "(transliteration)"
    text = strip_trailing_non_letters(text)
    text = unicodedata.normalize("NFD", text)
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    text = unicodedata.normalize("NFC", text)
    return text.lower().strip()


def strip_movable_nu(s: str) -> str:
    return s[:-1] if s.endswith("\u03bd") and len(s) > 1 else s


# Bounded, well-attested set of Greek preposition citation-form / elided
# (or phonetically-assimilated) form pairs -- e.g. \u03ba\u03b1\u03c4\u03ac before a rough
# breathing regularly elides and aspirates to \u03ba\u03b1\u03b8', and \u1f10\u03ba regularly
# becomes \u1f10\u03be before a vowel. These are standard Greek orthographic/
# phonological environment rules, not textual variants, so a TR/DB pair
# differing only by one of these is treated the same as movable-nu.
PREPOSITION_ELISION_PAIRS = {
    frozenset({"\u03b1\u03c0\u03bf", "\u03b1\u03c6"}), frozenset({"\u03b1\u03c0\u03bf", "\u03b1\u03c0"}),
    frozenset({"\u03b5\u03c0\u03b9", "\u03b5\u03c6"}), frozenset({"\u03b5\u03c0\u03b9", "\u03b5\u03c0"}),
    frozenset({"\u03c5\u03c0\u03bf", "\u03c5\u03c6"}), frozenset({"\u03c5\u03c0\u03bf", "\u03c5\u03c0"}),
    frozenset({"\u03ba\u03b1\u03c4\u03b1", "\u03ba\u03b1\u03b8"}), frozenset({"\u03ba\u03b1\u03c4\u03b1", "\u03ba\u03b1\u03c4"}),
    frozenset({"\u03bc\u03b5\u03c4\u03b1", "\u03bc\u03b5\u03b8"}), frozenset({"\u03bc\u03b5\u03c4\u03b1", "\u03bc\u03b5\u03c4"}),
    frozenset({"\u03b4\u03b9\u03b1", "\u03b4\u03b9"}),
    frozenset({"\u03c0\u03b1\u03c1\u03b1", "\u03c0\u03b1\u03c1"}),
    frozenset({"\u03b1\u03bd\u03c4\u03b9", "\u03b1\u03bd\u03c4"}),
    frozenset({"\u03b5\u03ba", "\u03b5\u03be"}),
}


def is_orthographic_variant(tr_norm: str, db_norm: str) -> bool:
    """Movable-nu, elision, or preposition-assimilation difference on an
    otherwise identical word -- a phonetic/typesetting-environment
    convention, not a textual difference."""
    if not tr_norm or not db_norm or tr_norm == db_norm:
        return False
    if strip_movable_nu(tr_norm) == strip_movable_nu(db_norm):
        return True
    if frozenset({tr_norm, db_norm}) in PREPOSITION_ELISION_PAIRS:
        return True
    shorter, longer = sorted([tr_norm, db_norm], key=len)
    if len(longer) - len(shorter) == 1 and longer.startswith(shorter):
        return True
    return False


def is_untranslated_article_placeholder(tw: dict, dt: dict) -> bool:
    """This DB represents EVERY untranslated Greek definite article
    (regardless of its actual case/gender/number -- τῷ, τοῦ, τὴν, τὸ,
    ἡ, etc.) with a single generic placeholder token: the literal letter
    ὁ ("ο" once accents are stripped), glossed "." -- rather than the
    real inflected spelling. Confirmed systematic (12,348 of 12,626 raw
    word_substitution matches in an initial run were exactly this pattern,
    2,467 of them the verse's ONLY discrepancy) and consistent with the
    Revelation 1:1 walkthrough already documented in
    strongs_duplication_scan_summary.md (six ".''-glossed ὁ placeholders
    standing in for ὁ/τοῖς/τοῦ/τῷ). This is a known DB-wide
    representation convention for an untranslated function word, not a
    scattered spelling error, so it is tracked separately rather than
    counted as a content discrepancy."""
    return (
        tw["strong"] == "G3588"
        and dt["strong"] == "G3588"
        and dt["text_norm"] == "ο"
        and dt["gloss"] == "."
    )


# Ancient Greek's most common verbs are suppletive -- built from several
# historically-unrelated roots across different tenses (e.g. "say" =
# present λέγω / aorist εἶπον(ἔπω) / future ἐρῶ / perfect-passive ῥηθέν
# (ῥέω); "know/see" = present ὁράω / perfect-with-present-sense
# οἶδα(εἴδω), whose own aorist-imperative forms ἰδού/ἴδε became fixed
# "behold!" interjections). Classical Strong's numbering gives each
# principal part its own entry; TAGNT (STEPBible) preserves that
# distinction. This DB instead consistently cites the whole paradigm
# under one lexeme number -- confirmed by data (not speculative): each
# pair below is a directional (TR-classical-number -> DB-number) mismatch
# that recurred dozens to hundreds of times with matching surface Greek
# text, i.e. the same word, tagged under a different (but linguistically
# related, suppletive-paradigm) headword every single time it occurs.
SUPPLETIVE_LEMMA_CONVENTION_PAIRS = {
    ("G2036", "G3004"),  # ἔπω (aorist "say") -> λέγω, 940 occurrences
    ("G4483", "G2046"),  # ῥέω/ἐρρέθη (perf/pass "say") -> ἐρέω (future "say"), 44
    ("G1492", "G3708"),  # εἴδω/οἶδα ("to know", from "to see") -> ὁράω, 339
    ("G2400", "G3708"),  # ἰδού ("behold!", from "to see") -> ὁράω, 212
    ("G2396", "G3708"),  # ἴδε ("behold!", from "to see") -> ὁράω, 27
}


def is_suppletive_lemma_convention(tw: dict, dt: dict) -> bool:
    """True if this TR-strong/DB-strong pair is one of the DB's known,
    systematic suppletive-verb-paradigm citation choices (see
    SUPPLETIVE_LEMMA_CONVENTION_PAIRS) -- tracked separately, not counted
    as a content discrepancy, for the same reason as the article
    placeholder (is_untranslated_article_placeholder)."""
    return (tw["strong"], dt["strong"]) in SUPPLETIVE_LEMMA_CONVENTION_PAIRS


def matches_documented_spelling_variant(tr_word: dict, db_norm: str) -> bool:
    """True if the DB spelling matches TAGNT's own documented TR/Scrivener
    print-edition spelling-variant note for this word."""
    note = tr_word.get("spelling_note")
    if not note:
        return False
    return normalize_greek(note) == db_norm


def texts_equivalent(tr_word: dict, db_norm: str) -> bool:
    return (
        tr_word["greek_norm"] == db_norm
        or matches_documented_spelling_variant(tr_word, db_norm)
        or is_orthographic_variant(tr_word["greek_norm"], db_norm)
    )


def download_if_missing() -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    for name in NT_FILES:
        dest = CACHE_DIR / name
        if dest.exists() and dest.stat().st_size > 0:
            continue
        url = STEPBIBLE_BASE + urllib.parse.quote(name)
        print(f"Downloading {name} ...", file=sys.stderr)
        urllib.request.urlretrieve(url, dest)


def parse_meaning_variant(field: str) -> tuple[str, str] | None:
    m = MEANING_VARIANT_RE.match(field.strip())
    if not m:
        return None
    editions = [e.strip() for e in m.group("editions").split("+")]
    if "TR" not in editions:
        return None
    return m.group("greek").strip(), m.group("strong").strip()


def parse_spelling_variant_tr_note(field: str) -> str | None:
    if not field or "TR" not in field:
        return None
    for label, text in SPELLING_VARIANT_TR_RE.findall(field):
        if "TR" in label:
            return text.strip()
    return None


def parse_tagnt(path: Path, tr_by_verse: dict, anomalies: list, moved_tr: list) -> None:
    with path.open(encoding="utf-8") as f:
        for line in f:
            if "\t" not in line:
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 8:
                continue
            m = ROW_RE.match(cols[0].strip())
            if not m:
                continue
            book, chapter, verse, instance, type_code = m.groups()
            if "k" not in type_code.lower():
                continue  # not part of the Traditional/TR text at all

            greek_field = cols[1]
            dstrong_field = cols[3]
            dict_form_field = cols[4] if len(cols) > 4 else ""
            editions_field = cols[5]
            meaning_variants_field = cols[6] if len(cols) > 6 else ""
            spelling_variants_field = cols[7] if len(cols) > 7 else ""
            # sStrong is col 11; further columns can hold one or more "Alt
            # Strongs" values -- both are candidate classical Strong's
            # numbers this DB might reasonably use for the same word.
            alt_strong_candidates = set()
            for extra_col in cols[11:]:
                extra_col = extra_col.strip()
                if STRONG_CODE_RE.match(extra_col.split("_")[0]):
                    s = normalize_strong(extra_col)
                    if s:
                        alt_strong_candidates.add(s)

            # An edition name can carry a displacement suffix, e.g. "TR»1"
            # (moved forward 1 word in TR) or "TR«4" (moved back 4 words)
            # -- the word is still IN that edition, just repositioned, so
            # the suffix must be stripped before membership/name matching
            # (confirmed via the many false "K but TR not in editions"
            # parser anomalies seen before this fix -- editions_field
            # values like "...+TR»1+Byz»1" were being read as the edition
            # literally named "TR»1", which never equals "TR").
            editions_raw = [e.split()[0].strip() for e in editions_field.split("+")]
            editions_raw = [e for e in editions_raw if e]
            editions = [DISPLACEMENT_SUFFIX_RE.sub("", e) for e in editions_raw]

            greek_raw = None
            strong_raw = None
            source = None

            if "TR" in editions:
                greek_raw = greek_field.split(" (")[0].strip()
                dm = DSTRONG_RE.match(dstrong_field.split("=")[0].strip())
                strong_raw = dm.group(1) if dm else dstrong_field.split("=")[0].strip()
                source = "primary"
            else:
                alt = parse_meaning_variant(meaning_variants_field)
                if alt:
                    greek_raw, strong_raw = alt
                    source = "meaning_variant"
                else:
                    anomalies.append(
                        f"{book}.{chapter}.{verse}#{instance}: has 'K' in type "
                        f"'{type_code}' but TR not in editions ('{editions_field}') "
                        f"and no TR meaning-variant found"
                    )
                    continue

            spelling_note = parse_spelling_variant_tr_note(spelling_variants_field)

            lemma_field = dict_form_field.split("=")[0].strip()
            lemma_candidates = {
                normalize_greek(l) for l in lemma_field.split(",") if l.strip()
            }
            lemma_candidates.discard("")

            for e_raw in editions_raw:
                if e_raw.startswith("TR") and DISPLACEMENT_SUFFIX_RE.search(e_raw):
                    moved_tr.append(f"{book}.{chapter}.{verse}#{instance}: {e_raw} (full editions field: {editions_field.strip()})")
                    break

            key = (book, int(chapter), int(verse))
            tr_by_verse.setdefault(key, []).append({
                "instance": instance,
                "greek_raw": greek_raw,
                "greek_norm": normalize_greek(greek_raw),
                "strong": normalize_strong(strong_raw),
                "spelling_note": spelling_note,
                "source": source,
                "alt_strong_candidates": alt_strong_candidates,
                "lemma_candidates": lemma_candidates,
            })


def load_reference() -> tuple[dict, list, list]:
    tr_by_verse: dict = {}
    anomalies: list = []
    moved_tr: list = []
    for name in NT_FILES:
        parse_tagnt(CACHE_DIR / name, tr_by_verse, anomalies, moved_tr)
    return tr_by_verse, anomalies, moved_tr


def load_db_tokens(conn: sqlite3.Connection) -> dict:
    query = """
        SELECT b.book_number, b.chapter, b.block_index AS verse,
               t.token_id, t.verse_index, t.english_gloss, t.ancient_text,
               t.strongs_canonical
        FROM bible_tokens t
        JOIN bible_blocks b ON b.id = t.block_id
        WHERE b.book_number BETWEEN 40 AND 66
        ORDER BY b.book_number, b.chapter, b.block_index, t.verse_index
    """
    by_verse: dict = defaultdict(list)
    for book_number, chapter, verse, token_id, verse_index, gloss, ancient_text, strongs in conn.execute(query):
        abbr = BOOK_ABBR.get(book_number)
        if not abbr:
            continue
        strong = normalize_strong(strongs) if strongs else None
        text = (ancient_text or "").strip()
        # English-only alignment rows are intentional.  The repair tool clears
        # the source-language metadata from surplus rows while retaining their
        # KJV gloss, so they must not be counted as Greek words.
        if not text and not strong:
            continue
        by_verse[(abbr, chapter, verse)].append({
            "token_id": token_id,
            "verse_index": verse_index,
            "gloss": gloss,
            "ancient_text": text,
            "text_norm": normalize_greek(text) if text else "",
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


def load_db_lemma_index(conn: sqlite3.Connection) -> dict:
    """normalized Greek lemma -> set of this DB's own classical Strong's
    numbers that use that lemma. Used to cross-walk TAGNT's disambiguated
    dStrong/sStrong numbering (which invents extended codes like G6063 for
    forms classical/simple Strong's numbering does not distinguish, e.g.
    per-case personal-pronoun forms or suppletive-verb principal parts)
    back to whatever classical number THIS database actually uses for the
    same headword -- since bible_tokens was confirmed (see module
    docstring) to use classical/lexeme-root numbering, not STEPBible's
    disambiguation scheme."""
    idx = defaultdict(set)
    for strongs_canonical, lemma in conn.execute(
        "SELECT strongs_canonical, lemma FROM strongs_dictionary WHERE strongs_canonical LIKE 'G%'"
    ):
        strong = normalize_strong(strongs_canonical)
        norm_lemma = normalize_greek(lemma) if lemma else ""
        if strong and norm_lemma:
            idx[norm_lemma].add(strong)
    return idx


def attach_expected_db_strongs(tr_by_verse: dict, db_lemma_index: dict) -> None:
    """For every TR word, compute the set of Strong's numbers this DB could
    reasonably be expected to use for it: TAGNT's own number, any Alt
    Strongs TAGNT lists, and -- most importantly -- whatever classical
    number(s) this DB's own dictionary assigns to the same lemma. This is
    what makes the Strong's comparison robust to STEPBible's disambiguated
    numbering scheme differing from this DB's classical/lexeme-root
    convention (see load_db_lemma_index docstring)."""
    for words in tr_by_verse.values():
        for w in words:
            expected = set()
            if w["strong"]:
                expected.add(w["strong"])
            expected |= w["alt_strong_candidates"]
            for lemma in w["lemma_candidates"]:
                expected |= db_lemma_index.get(lemma, set())
            w["expected_db_strongs"] = expected


def match_verse_content(tr_words: list, db_tokens: list) -> tuple[list, dict]:
    """Order-independent greedy multiset reconciliation. Returns
    (issue dicts, known_convention_notes) -- issues is empty if the
    verse's Greek content is fully accounted for, regardless of word
    order; known_convention_notes counts informational-only patterns (see
    is_untranslated_article_placeholder, is_suppletive_lemma_convention), never
    counted as issues."""
    tr_left = list(enumerate(tr_words))
    db_left = list(enumerate(db_tokens))
    issues = []
    notes = {"article_placeholder": 0, "suppletive_lemma_convention": 0}

    # Pass A: exact match (text-equivalent AND a compatible Strong's) -> consumed, no issue
    still_tr = []
    for ti, tw in tr_left:
        found = None
        for k, (di, dt) in enumerate(db_left):
            if texts_equivalent(tw, dt["text_norm"]) and dt["strong"] in tw["expected_db_strongs"]:
                found = k
                break
        if found is not None:
            db_left.pop(found)
        else:
            still_tr.append((ti, tw))
    tr_left = still_tr

    # Pass B: text matches, Strong's differs -> strongs_mismatch
    still_tr = []
    for ti, tw in tr_left:
        found = None
        for k, (di, dt) in enumerate(db_left):
            if texts_equivalent(tw, dt["text_norm"]):
                found = k
                break
        if found is not None:
            di, dt = db_left.pop(found)
            if is_suppletive_lemma_convention(tw, dt):
                notes["suppletive_lemma_convention"] += 1
            else:
                issues.append({
                    "type": "strongs_mismatch",
                    "tr_word": tw["greek_raw"], "tr_strong": tw["strong"],
                    "tr_expected_strongs": sorted(tw["expected_db_strongs"]),
                    "db_word": dt["ancient_text"], "db_strong": dt["strong"],
                })
        else:
            still_tr.append((ti, tw))
    tr_left = still_tr

    # Pass C: Strong's matches, text differs -> word_substitution (different form),
    # except the known untranslated-article placeholder pattern (not an issue)
    still_tr = []
    for ti, tw in tr_left:
        found = None
        if tw["expected_db_strongs"]:
            for k, (di, dt) in enumerate(db_left):
                if dt["strong"] and dt["strong"] in tw["expected_db_strongs"]:
                    found = k
                    break
        if found is not None:
            di, dt = db_left.pop(found)
            if is_untranslated_article_placeholder(tw, dt):
                notes["article_placeholder"] += 1
            else:
                issues.append({
                    "type": "word_substitution",
                    "tr_word": tw["greek_raw"], "tr_strong": tw["strong"],
                    "db_word": dt["ancient_text"], "db_strong": dt["strong"],
                })
        else:
            still_tr.append((ti, tw))
    tr_left = still_tr

    # Pass D: unmatched TR words -> missing from DB
    for ti, tw in tr_left:
        issues.append({
            "type": "missing_word",
            "tr_word": tw["greek_raw"], "tr_strong": tw["strong"],
            "db_word": None, "db_strong": None,
        })

    # Pass E: unmatched DB tokens -> extra, not in TR
    for di, dt in db_left:
        issues.append({
            "type": "extra_word",
            "tr_word": None, "tr_strong": None,
            "db_word": dt["ancient_text"], "db_strong": dt["strong"],
        })

    return issues, notes


def classify_content_summary(issues: list) -> str:
    types_present = {i["type"] for i in issues}
    if types_present == {"missing_word"}:
        return "missing_word"
    if types_present == {"extra_word"}:
        return "extra_word"
    if types_present == {"strongs_mismatch"}:
        return "strongs_mismatch"
    if types_present == {"word_substitution"}:
        return "word_substitution"
    return "mixed_content"


def order_differs(tr_words: list, db_tokens: list) -> bool:
    """Informational only: does strict positional Greek order differ from
    DB order? Expected to be True for the large majority of verses by
    design (see module docstring) -- NOT counted as a content error."""
    if len(tr_words) != len(db_tokens):
        return True
    for tw, dt in zip(tr_words, db_tokens):
        if not texts_equivalent(tw, dt["text_norm"]):
            return True
    return False


def diff_verse(key: tuple, tr_words: list, db_tokens: list) -> dict | None:
    issues, notes = match_verse_content(tr_words, db_tokens)
    order_diff = order_differs(tr_words, db_tokens)
    any_notes = notes["article_placeholder"] or notes["suppletive_lemma_convention"]
    if not issues:
        return None if not (order_diff or any_notes) else {
            "book": key[0], "chapter": key[1], "verse": key[2],
            "issues": [], "content_summary": "clean_content_reordered",
            "order_differs": order_diff,
            "notes": notes,
            "tr_sequence": [w["greek_raw"] for w in tr_words],
            "db_sequence": [t["ancient_text"] for t in db_tokens],
        }
    return {
        "book": key[0], "chapter": key[1], "verse": key[2],
        "issues": issues,
        "content_summary": classify_content_summary(issues),
        "order_differs": order_diff,
        "notes": notes,
        "tr_sequence": [w["greek_raw"] for w in tr_words],
        "db_sequence": [t["ancient_text"] for t in db_tokens],
    }


def write_reports(findings: list, verses_checked: int, verses_no_reference: list,
                   anomalies: list, moved_tr: list, clean_reordered_count: int,
                   fully_clean_count: int, order_differs_total: int,
                   article_placeholder_verses: int, article_placeholder_total: int,
                   suppletive_lemma_verses: int, suppletive_lemma_total: int) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    content_findings = [f for f in findings if f["issues"]]
    content_findings.sort(key=lambda f: (f["book"], f["chapter"], f["verse"]))

    csv_path = REPORT_DIR / "nt_word_order_verification_report.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "book", "chapter", "verse", "content_mismatch_summary", "issue_count",
            "order_differs_from_greek_syntax_informational_only",
            "tr_scrivener_sequence", "db_sequence", "content_mismatch_detail",
        ])
        for item in content_findings:
            detail_parts = []
            for i in item["issues"]:
                if i["type"] == "missing_word":
                    detail_parts.append(f"MISSING: TR has '{i['tr_word']}' ({i['tr_strong']}), no match anywhere in DB verse")
                elif i["type"] == "extra_word":
                    detail_parts.append(f"EXTRA: DB has '{i['db_word']}' ({i['db_strong']}), no TR counterpart anywhere in verse")
                elif i["type"] == "strongs_mismatch":
                    detail_parts.append(
                        f"STRONGS MISMATCH: word text matches ('{i['tr_word']}'); expected Strong's "
                        f"(TR/TAGNT {i['tr_strong']}, cross-walked to this DB's lexeme numbering: "
                        f"{'/'.join(i['tr_expected_strongs']) or 'none found'}) "
                        f"vs DB actual '{i['db_word']}'={i['db_strong']}"
                    )
                elif i["type"] == "word_substitution":
                    detail_parts.append(
                        f"DIFFERENT FORM: same Strong's {i['tr_strong']}, TR '{i['tr_word']}' "
                        f"vs DB '{i['db_word']}'"
                    )
            w.writerow([
                item["book"], item["chapter"], item["verse"], item["content_summary"],
                len(item["issues"]), "yes" if item["order_differs"] else "no",
                " ".join(item["tr_sequence"]),
                " ".join(item["db_sequence"]),
                " | ".join(detail_parts),
            ])

    json_path = REPORT_DIR / "nt_word_order_verification_report.json"
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(content_findings, f, ensure_ascii=False, indent=2)

    print(f"Wrote {csv_path}")
    print(f"Wrote {json_path}")

    by_type = Counter()
    for item in content_findings:
        for i in item["issues"]:
            by_type[i["type"]] += 1
    by_summary = Counter(item["content_summary"] for item in content_findings)

    md_path = REPORT_DIR / "nt_word_order_verification_summary.md"
    with md_path.open("w", encoding="utf-8") as f:
        f.write(f"""# New Testament Greek Word-Content Verification vs. Textus Receptus (Scrivener 1894)

Generated by `tool/source_text_verification/verify_nt_word_order.py`.
Re-run that script to regenerate this summary and the accompanying
`nt_word_order_verification_report.csv` / `.json`.

## Methodology

**Reference source and edition:** STEPBible-Data "Translators Amalgamated
Greek New Testament" (TAGNT), CC BY 4.0,
https://github.com/STEPBible/STEPBible-Data. Per TAGNT's own field
definitions, **"K" = the Traditional text, i.e. the Textus Receptus of
Scrivener's 1894, the Greek text underlying the KJV translators' work** --
the specific edition requested. Only rows whose Word & Type code contains
"K" were extracted as belonging to the Scrivener/TR text, with the
Scrivener-specific reading resolved from TAGNT's "editions" and "Meaning
variants" columns (see script docstring for the exact resolution rules).

**A critical discovery that shapes this report's structure:**
`bible_tokens` does **not** store Greek words in Greek syntactic order --
it stores them in the order the KJV English translation reads (a "reverse
interlinear" layout). For example, John 11:35 "Jesus wept": TR order is
\u1f10\u03b4\u03ac\u03ba\u03c1\u03c5\u03c3\u03b5\u03bd \u1f41 \u1f38\u03b7\u03c3\u03bf\u1fe6\u03c2 (*wept / the / Jesus*), but this DB stores
\u1f41 \u1f38\u03b7\u03c3\u03bf\u1fe6\u03c2 \u1f10\u03b4\u03ac\u03ba\u03c1\u03c5\u03c3\u03b5\u03bd (*the / Jesus / wept*) -- matching English word order,
not Greek. This is systematic (verified across many verses, e.g. 1
Corinthians 1:2 similarly relocates "in every place" to its position in
the English clause), and is a deliberate interlinear-display design
choice, not textual corruption. A strict Greek-order-vs-DB-order
positional diff was tested first and flagged 7,878 of 7,948 verses (99%)
almost entirely because of this reordering cascade -- a number that would
be true but deeply misleading if reported as "99% of verses have textual
errors." **The user was informed of this finding and chose to have the
report separate genuine content accuracy from word order.**

**A second discovery, equally important to the Strong's-mismatch counts
below:** TAGNT's own Strong's numbers (`dStrong`/`sStrong`) are a
*disambiguated, extended* numbering scheme -- e.g. it tags personal-
pronoun case-forms (ἡμῶν, μοι, μου...) and certain suppletive-verb
principal parts under invented codes beyond the classical 1-5624 range
(e.g. `G6063` for a form of "to know"), which classical/simple Strong's
tagging (confirmed to be what this DB uses) does not distinguish, instead
tagging all such forms under one lexeme-root number (e.g. `G1473` for
every case of ἐγώ). Comparing TAGNT's numbers to this DB's numbers
directly therefore produced large false-positive `strongs_mismatch`
counts driven purely by tagging-convention differences, not DB errors --
the same phenomenon already flagged as a known limitation in
`strongs_duplication_scan_summary.md` ("Greek personal-pronoun forms...
occasionally tagged under a different disambiguated Strong's number").
This script fixes that by cross-walking every TR word's TAGNT number (and
TAGNT's own "Alt Strongs" column) through **this DB's own
`strongs_dictionary` table**, matched by normalized lemma text (TAGNT's
"Dictionary form" column) rather than by number -- so a word is only
flagged as a genuine `strongs_mismatch` if the DB's tag doesn't match *any*
classical Strong's number this database's own dictionary associates with
that lemma.

Accordingly, every verse is evaluated on two independent layers:

1. **CONTENT (primary, order-independent).** Are the same words, with a
   compatible Strong's number (see cross-walk above), present in the
   verse, regardless of position? Matched by greedy multiset
   reconciliation, in priority order:
   - exact match (same normalized text, or a documented TR/Scrivener
     print-edition spelling variant, or a movable-nu/elision variant --
     AND a compatible Strong's number) -> no issue
   - text matches, Strong's incompatible -> `strongs_mismatch`
   - Strong's compatible, text differs -> `word_substitution` (a different
     inflected form/spelling than TR has for that lexeme in this verse) --
     **except** the untranslated-article placeholder pattern below, which
     is tracked separately, not as an issue
   - left over on the TR side, no candidate anywhere in the verse ->
     `missing_word`
   - left over on the DB side, no TR counterpart anywhere in the verse ->
     `extra_word`
   This is the layer that answers "is the Greek text itself correct,"
   and is what the CSV/JSON reports below are built from.

   **Untranslated-article placeholder (excluded from `word_substitution`,
   tracked separately):** this DB represents *every* untranslated Greek
   definite article -- regardless of its real case/gender/number (τῷ,
   τοῦ, τὴν, τὸ, ἡ, etc.) -- with one generic placeholder token, the
   literal letter ὁ (nominative singular, "ο" once accents are stripped),
   glossed ".". This matches the Revelation 1:1 walkthrough already in
   `strongs_duplication_scan_summary.md` and was confirmed systematic
   here: in an initial run, 12,348 of 12,626 raw `word_substitution`
   matches (97.8%) were exactly this pattern, and 2,467 verses had it as
   their *only* discrepancy. Since it is one well-understood, DB-wide
   representation convention for an untranslated function word -- not a
   scattered spelling error -- it is excluded from the content-issue
   counts and reported only as an aggregate, informational stat below.

   **Suppletive-verb lemma convention (excluded from `strongs_mismatch`,
   tracked separately):** Ancient Greek's commonest verbs are suppletive
   (built from different roots per tense/mood -- "say" = λέγω(present) /
   ἔπω(aorist) / ἐρέω(future) / ῥέω(perfect-passive); "know" = οἶδα
   (historically the perfect of "to see", εἴδω, whose own aorist-
   imperative forms ἰδού/ἴδε became fixed "behold!" interjections).
   Classical Strong's numbering gives each principal part its own entry,
   which TAGNT preserves; this DB instead cites the whole paradigm under
   one lexeme every time. Confirmed by data, not speculation -- see
   `SUPPLETIVE_LEMMA_CONVENTION_PAIRS` in the script for the exact
   (TR-number -> DB-number) pairs and their observed counts (940 + 44 +
   339 + 212 + 27 = 1,562 occurrences in an initial run). Excluded from
   the content-issue counts for the same reason as the article
   placeholder, and reported only as an aggregate, informational stat
   below.
2. **ORDER (informational only, not counted as a content error).** Does
   the DB's token order match TR's Greek syntactic order position-by-
   position? Reported per verse as a single yes/no column
   (`order_differs_from_greek_syntax_informational_only`) plus an
   aggregate stat below. Expected to be "yes" for most verses by design
   (see discovery above); a verse being reordered is not, by itself,
   evidence of a data error in this DB.

**Known TR/Scrivener 1894 print-edition variants (excluded from error
flags):** TAGNT's own "Spelling variants" column, when it names TR, was
used to recognize documented print-edition spellings (e.g. Matthew 1:1
"David": NA-preferred display \u0394\u03b1\u03c5\u1f76\u03b4 vs. Scrivener's \u0394\u03b1\u03b2\u1f76\u03b4 -- this
DB stores the latter, correctly). Movable-nu (\u03bd \u03b5\u03c6\u03b5\u03bb\u03ba\u03c5\u03c3\u03c4\u03b9\u03ba\u03cc\u03bd) and
vowel-elision differences on an otherwise-identical, same-Strong's word
were also treated as non-errors, since these are a typesetting/phonetic-
environment convention, not a textual difference. `bible_tokens.ancient_text`
has no accents, breathing marks, or punctuation and is lower-case; both
sides of every comparison were normalized identically (Unicode NFD
decomposition with combining marks stripped, trailing punctuation
stripped, lower-cased, NFC recomposed) before comparing.

## Results

| | Count |
|---|---|
| NT verses checked (had TAGNT + DB coverage) | {verses_checked} |
| NT verses with no reference match (versification gap, excluded) | {len(verses_no_reference)} |
| **Verses with \u22651 genuine content discrepancy (missing/extra/wrong word or Strong's)** | **{len(content_findings)}** |
| Verses fully clean in content, but with word order that differs from Greek syntax (expected/by-design, not an error) | {clean_reordered_count} |
| Verses fully clean in content AND matching strict Greek word order | {fully_clean_count} |
| Verses where DB order differs from Greek syntax (informational; includes both clean- and issue-content verses) | {order_differs_total} / {verses_checked} |
| Verses containing ≥1 untranslated-article placeholder (informational, not an error; includes both clean- and issue-content verses) | {article_placeholder_verses} ({article_placeholder_total} instances) |
| Verses containing ≥1 suppletive-verb lemma tagging-convention instance ("say"/"see-know-behold" families; informational, not an error; includes both clean- and issue-content verses) | {suppletive_lemma_verses} ({suppletive_lemma_total} instances) |
| Total content-discrepancy issues (all types, across all flagged verses) | {sum(by_type.values())} |

### Breakdown by content issue type

| Type | Count |
|---|---|
""")
        for t, n in by_type.most_common():
            f.write(f"| {t} | {n} |\n")
        f.write("\n### Breakdown by verse-level content classification\n\n| Summary | Verses |\n|---|---|\n")
        for t, n in by_summary.most_common():
            f.write(f"| {t} | {n} |\n")

        f.write(f"""
## Known limitations

- **Greedy, not optimal, multiset matching.** For a verse with several
  words sharing one Strong's number in different inflected forms, the
  specific TR-word-to-DB-word pairing shown in a `word_substitution`
  finding may not be the pairing a human collator would choose, though
  the aggregate issue counts for that verse are still correct.
- **Residual personal-pronoun `strongs_mismatch` findings** (e.g. TR
  ἡμᾶς/G2248, ἡμῶν/G2257, ἡμῖν/G2254 vs DB G1473; ὑμῶν/G5216, ὑμῖν/G5213
  vs DB G4771) likely reflect the same lemma-consolidation pattern as the
  suppletive-verb convention above, just for the singular/plural pronoun
  paradigm (ἐγώ/ἡμεῖς, σύ/ὑμεῖς), which the lemma cross-walk did not
  catch because TAGNT cites the plural forms under a separate dictionary
  headword this DB's own dictionary does not carry. This is a smaller,
  long-tail pattern (~40 occurrences total, none more than 11) left
  flagged individually rather than special-cased, consistent with how
  `strongs_duplication_scan_summary.md` already treats this class of
  pronoun tagging-convention difference.
- **Word order is reported for information only, never as an error**, per
  the discovery above -- do not read the
  `order_differs_from_greek_syntax_informational_only` column as a defect
  indicator.
- **Versification differences.** TAGNT follows NRSV versification; this
  database follows KJV versification. Verses with no TAGNT match at the
  same (book, chapter, verse) key are excluded from the scan, not counted
  as clean.
- **Parser anomalies.** {len(anomalies)} TAGNT rows were tagged as
  containing "K" in their Word & Type code but could not be resolved to a
  concrete TR reading (neither "TR" in the editions column nor in a
  meaning-variant's "in:" list) -- these rows were skipped.
- **{len(moved_tr)} TR-specific word-order notes** (TAGNT's own "TR\u00bbN"/"TR\u00abN" displacement suffix) were
  found in the TAGNT reference data itself, meaning TR's own word order
  is occasionally attested by STEPBible as different from TAGNT's base
  display order. This does not affect the content layer (order-
  independent), but is noted for completeness.
- This is a Strong's-tagged textual collation against STEPBible's TAGNT
  encoding of Scrivener 1894, not a manuscript collation against a
  scanned facsimile of the print edition.
- This is a **verification/reporting pass only** -- `bible_tokens` and all
  other tables were not modified.

## Files

- `tool/source_text_verification/verify_nt_word_order.py` -- the scan script (re-runnable; reuses cached reference data in `source-data/stepbible/`, gitignored)
- `tool/audits/nt_word_order_verification_report.csv` -- every verse with \u22651 genuine content discrepancy, with the full TR and DB word sequences, the order-differs note, and a plain-text mismatch description
- `tool/audits/nt_word_order_verification_report.json` -- same data, full structured detail (per-issue word/Strong's, both TR and DB)
""")

    print(f"Wrote {md_path}")


def debug_verse(ref: str) -> None:
    book, chapter, verse = ref.split(".")
    key = (book, int(chapter), int(verse))
    download_if_missing()
    tr_by_verse, anomalies, moved_tr = load_reference()
    conn = sqlite3.connect(str(DB_PATH))
    db_by_verse = load_db_tokens(conn)
    db_lemma_index = load_db_lemma_index(conn)
    conn.close()
    attach_expected_db_strongs(tr_by_verse, db_lemma_index)

    tr_words = tr_by_verse.get(key, [])
    db_tokens = db_by_verse.get(key, [])
    print(f"TR/Scrivener ({len(tr_words)} words):")
    for w in tr_words:
        print(f"  {w['greek_raw']!r:20} norm={w['greek_norm']!r:15} strong={w['strong']} expected={sorted(w['expected_db_strongs'])} src={w['source']} note={w['spelling_note']}")
    print(f"\nDB ({len(db_tokens)} tokens):")
    for t in db_tokens:
        print(f"  {t['ancient_text']!r:20} norm={t['text_norm']!r:15} strong={t['strong']} gloss={t['gloss']!r}")
    result = diff_verse(key, tr_words, db_tokens)
    print(f"\nDiff result: {json.dumps(result, ensure_ascii=False, indent=2) if result else 'FULLY CLEAN (content matches, order matches)'}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug-verse", help="e.g. Mat.1.1 -- dump extraction/diff for one verse and exit")
    args = parser.parse_args()

    if args.debug_verse:
        debug_verse(args.debug_verse)
        return

    download_if_missing()
    print("Parsing TAGNT reference data (K-tagged Traditional/TR rows only)...", file=sys.stderr)
    tr_by_verse, anomalies, moved_tr = load_reference()

    conn = sqlite3.connect(str(DB_PATH))
    try:
        db_by_verse = load_db_tokens(conn)
        db_lemma_index = load_db_lemma_index(conn)
    finally:
        conn.close()
    attach_expected_db_strongs(tr_by_verse, db_lemma_index)

    findings = []
    verses_checked = 0
    verses_no_reference = []
    clean_reordered_count = 0
    fully_clean_count = 0
    order_differs_total = 0
    article_placeholder_verses = 0
    article_placeholder_total = 0
    suppletive_lemma_verses = 0
    suppletive_lemma_total = 0

    for key, db_tokens in db_by_verse.items():
        tr_words = tr_by_verse.get(key)
        if tr_words is None:
            verses_no_reference.append(key)
            continue
        verses_checked += 1
        result = diff_verse(key, tr_words, db_tokens)
        if result is None:
            fully_clean_count += 1
            continue
        if result["order_differs"]:
            order_differs_total += 1
        if result["notes"]["article_placeholder"]:
            article_placeholder_verses += 1
            article_placeholder_total += result["notes"]["article_placeholder"]
        if result["notes"]["suppletive_lemma_convention"]:
            suppletive_lemma_verses += 1
            suppletive_lemma_total += result["notes"]["suppletive_lemma_convention"]
        if not result["issues"]:
            clean_reordered_count += 1
            continue
        findings.append(result)

    write_reports(findings, verses_checked, verses_no_reference, anomalies, moved_tr,
                   clean_reordered_count, fully_clean_count, order_differs_total,
                   article_placeholder_verses, article_placeholder_total,
                   suppletive_lemma_verses, suppletive_lemma_total)

    print()
    print(f"NT verses checked:              {verses_checked}")
    print(f"NT verses no reference:         {len(verses_no_reference)}")
    print(f"Verses w/ content discrepancy:  {len(findings)}")
    print(f"Content-clean, reordered only:  {clean_reordered_count}")
    print(f"Fully clean (content + order):  {fully_clean_count}")
    print(f"Order differs (informational):  {order_differs_total} / {verses_checked}")
    print(f"Article-placeholder verses:     {article_placeholder_verses} ({article_placeholder_total} instances, informational)")
    print(f"Suppletive-lemma conv. verses:  {suppletive_lemma_verses} ({suppletive_lemma_total} instances, informational)")
    print(f"Parser anomalies:               {len(anomalies)}")
    print(f"TR 'moved' notes found:         {len(moved_tr)}")


if __name__ == "__main__":
    main()
