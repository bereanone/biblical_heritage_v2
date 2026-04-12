#!/usr/bin/env python3
from __future__ import annotations

import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parent
TARGET_DB = ROOT / "assets" / "databases" / "bible_base.db"
SOURCE_DB = Path(
    "/Users/deanbowen/Development/bible_app_mac/assets/databases/bible_base.db"
)


def table_exists(conn: sqlite3.Connection, table: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table,),
    ).fetchone()
    return row is not None


def create_bible_sections_if_missing(conn: sqlite3.Connection) -> None:
    if table_exists(conn, "bible_sections"):
        return
    conn.execute(
        """
        CREATE TABLE bible_sections (
          section_id     INTEGER PRIMARY KEY,
          section_name   TEXT NOT NULL,
          color_hex      TEXT NOT NULL,
          min_block_id   INTEGER NOT NULL,
          max_block_id   INTEGER NOT NULL
        )
        """
    )


def create_section_headings_if_missing(conn: sqlite3.Connection) -> None:
    if table_exists(conn, "section_headings"):
        return
    conn.execute(
        """
        CREATE TABLE section_headings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_number INTEGER NOT NULL,
          chapter INTEGER NOT NULL,
          verse INTEGER NOT NULL,
          heading TEXT NOT NULL,
          source TEXT,
          block_id INTEGER
        )
        """
    )
    conn.execute(
        """
        CREATE TRIGGER prevent_section_headings_update
        BEFORE UPDATE ON section_headings
        BEGIN
          SELECT RAISE(ABORT, 'section_headings are immutable');
        END
        """
    )
    conn.execute(
        """
        CREATE TRIGGER prevent_section_headings_delete
        BEFORE DELETE ON section_headings
        BEGIN
          SELECT RAISE(ABORT, 'section_headings are immutable');
        END
        """
    )


def main() -> None:
    if not TARGET_DB.exists():
        raise SystemExit(f"Target DB not found: {TARGET_DB}")
    if not SOURCE_DB.exists():
        raise SystemExit(f"Source DB not found: {SOURCE_DB}")

    conn = sqlite3.connect(TARGET_DB)
    conn.execute("PRAGMA foreign_keys = OFF")
    conn.execute("ATTACH DATABASE ? AS Version1", (str(SOURCE_DB),))

    try:
        create_bible_sections_if_missing(conn)
        create_section_headings_if_missing(conn)

        conn.execute("DELETE FROM bible_sections")
        conn.execute(
            """
            INSERT INTO bible_sections(
              section_id,
              section_name,
              color_hex,
              min_block_id,
              max_block_id
            )
            SELECT
              section_id,
              section_name,
              color_hex,
              min_block_id,
              max_block_id
            FROM Version1.bible_sections
            """
        )
        bible_sections_imported = conn.execute("SELECT changes()").fetchone()[0]

        conn.execute("DROP TRIGGER IF EXISTS prevent_section_headings_update")
        conn.execute("DROP TRIGGER IF EXISTS prevent_section_headings_delete")
        conn.execute("DELETE FROM section_headings")
        conn.execute(
            """
            INSERT INTO section_headings(
              id,
              book_number,
              chapter,
              verse,
              heading,
              source,
              block_id
            )
            SELECT
              id,
              book_number,
              chapter,
              verse,
              heading,
              source,
              block_id
            FROM Version1.section_headings
            """
        )
        section_headings_imported = conn.execute("SELECT changes()").fetchone()[0]
        conn.execute(
            """
            CREATE TRIGGER IF NOT EXISTS prevent_section_headings_update
            BEFORE UPDATE ON section_headings
            BEGIN
              SELECT RAISE(ABORT, 'section_headings are immutable');
            END
            """
        )
        conn.execute(
            """
            CREATE TRIGGER IF NOT EXISTS prevent_section_headings_delete
            BEFORE DELETE ON section_headings
            BEGIN
              SELECT RAISE(ABORT, 'section_headings are immutable');
            END
            """
        )

        conn.commit()
        print(f"Imported bible_sections rows: {bible_sections_imported}")
        print(f"Imported section_headings rows: {section_headings_imported}")
        print("Topic tables copied successfully.")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.execute("DETACH DATABASE Version1")
        conn.close()


if __name__ == "__main__":
    main()
