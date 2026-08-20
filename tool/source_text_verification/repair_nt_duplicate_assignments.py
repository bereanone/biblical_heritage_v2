#!/usr/bin/env python3
"""Clear duplicated Greek assignments without deleting English gloss rows.

The reverse interlinear needs one row for each English alignment unit, but a
Greek word must only be attached to as many rows as it occurs in Scrivener's
TR.  This repair preserves every row and ``english_gloss`` value.  On surplus
exact (Greek spelling, Strong's) assignments it clears only the Greek metadata,
turning that row into an English-only alignment row.

The operation is conservative: substitutions, split/crasis spellings, missing
words, and non-identical over-counts are not changed here.  Run the full
verifier afterward to assess those independently.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from collections import defaultdict
from pathlib import Path

import verify_nt_word_order as verification


REPORT_PATH = verification.REPORT_DIR / "nt_duplicate_assignment_repair.json"
GREEK_COLUMNS = (
    "ancient_text",
    "transliteration",
    "strongs_number",
    "strongs_canonical",
    "morphology_tag",
    "pronunciation",
)

# A duplicated source word was commonly stamped on both an English helper word
# ("unto", "he") and the semantic head ("servants", "signified").  Prefer to
# retain the assignment on the semantic head.  This affects display/link
# placement only; the source-content result is identical whichever duplicate is
# retained.
HELPER_GLOSSES = {
    ".", "a", "an", "and", "are", "as", "at", "be", "been", "being",
    "by", "did", "do", "does", "for", "from", "had", "has", "have", "he",
    "her", "him", "his", "i", "in", "is", "it", "its", "of", "on", "she",
    "that", "the", "their", "them", "they", "to", "unto", "was", "were",
    "which", "who", "whom", "with", "you", "your",
}


def gloss_score(token: dict) -> tuple[int, int, int]:
    gloss = (token.get("gloss") or "").strip().lower()
    words = [w.strip(".,;:!?()[]{}\"'") for w in gloss.split()]
    content = [w for w in words if w and w not in HELPER_GLOSSES]
    return (1 if content else 0, sum(map(len, content)), token["verse_index"])


def plan_repairs(conn: sqlite3.Connection) -> list[dict]:
    verification.download_if_missing()
    tr_by_verse, _anomalies, _moved = verification.load_reference()
    lemma_index = verification.load_db_lemma_index(conn)
    verification.attach_expected_db_strongs(tr_by_verse, lemma_index)
    db_by_verse = verification.load_db_tokens(conn)

    repairs: list[dict] = []
    for key, tokens in db_by_verse.items():
        tr_words = tr_by_verse.get(key)
        if not tr_words:
            continue

        groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
        for token in tokens:
            if token["text_norm"] and token["strong"]:
                groups[(token["text_norm"], token["strong"])].append(token)

        for (text_norm, strong), candidates in groups.items():
            if strong == "G3588" and text_norm == "ο":
                # The DB deliberately spells every untranslated inflected
                # article as generic ὁ, so compare this group with the total
                # article count rather than only literal nominative ὁ rows.
                expected_count = sum(
                    1 for word in tr_words if strong in word["expected_db_strongs"]
                )
            else:
                expected_count = sum(
                    1
                    for word in tr_words
                    if verification.texts_equivalent(word, text_norm)
                    and strong in word["expected_db_strongs"]
                )
            surplus = len(candidates) - expected_count
            if expected_count < 1 or surplus < 1:
                continue

            # Retain the most meaningful English alignment(s); clear helpers.
            ranked = sorted(candidates, key=gloss_score, reverse=True)
            for token in ranked[expected_count:]:
                repairs.append({
                    "book": key[0],
                    "chapter": key[1],
                    "verse": key[2],
                    "token_id": token["token_id"],
                    "verse_index": token["verse_index"],
                    "english_gloss": token["gloss"],
                    "ancient_text": token["ancient_text"],
                    "strongs": token["strong"],
                })
    return repairs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="commit repairs to bible_base.db")
    args = parser.parse_args()

    conn = sqlite3.connect(str(verification.DB_PATH))
    try:
        repairs = plan_repairs(conn)
        if args.apply:
            conn.execute("BEGIN IMMEDIATE")
            placeholders = ", ".join(f"{column} = NULL" for column in GREEK_COLUMNS)
            for repair in repairs:
                cursor = conn.execute(
                    f"UPDATE bible_tokens SET {placeholders} WHERE token_id = ?",
                    (repair["token_id"],),
                )
                if cursor.rowcount != 1:
                    raise RuntimeError(f"token_id {repair['token_id']} updated {cursor.rowcount} rows")
            conn.commit()
        cleared_rows = [
            {
                "book": verification.BOOK_ABBR[book_number],
                "chapter": chapter,
                "verse": verse,
                "token_id": token_id,
                "verse_index": verse_index,
                "english_gloss": gloss,
            }
            for book_number, chapter, verse, token_id, verse_index, gloss in conn.execute(
                """
                SELECT b.book_number, b.chapter, b.block_index, t.token_id,
                       t.verse_index, t.english_gloss
                FROM bible_tokens t
                JOIN bible_blocks b ON b.id = t.block_id
                WHERE b.book_number BETWEEN 40 AND 66
                  AND t.ancient_text IS NULL
                  AND t.strongs_canonical IS NULL
                ORDER BY b.book_number, b.chapter, b.block_index, t.verse_index
                """
            )
        ]
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    verification.REPORT_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "apply_requested_this_run": args.apply,
        "planned_repair_count_this_run": len(repairs),
        "cleared_assignment_count_in_database": len(cleared_rows),
        "policy": "preserve row/gloss; clear surplus exact Greek assignment metadata",
        "planned_repairs": repairs,
        "cleared_assignment_rows": cleared_rows,
    }
    REPORT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    mode = "Applied" if args.apply else "Planned"
    print(f"{mode} {len(repairs)} duplicate-assignment repairs")
    print(f"Wrote {REPORT_PATH}")


if __name__ == "__main__":
    main()
