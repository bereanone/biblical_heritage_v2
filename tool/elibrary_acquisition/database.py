#!/usr/bin/env python3
"""
database.py

SQLite schema and writer for the God's Promises dataset plus the normalized
StudyBible2 eLibrary acquisition tables.

The legacy workbook tables remain in place for backwards compatibility, while
the new `elibrary_*` tables give EPUB, HTML, TXT, and future importers one
shared storage model.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path


class GodsPromisesDatabase:
    def __init__(self, db_path: Path):
        self.db_path = Path(db_path)
        self.conn = sqlite3.connect(self.db_path)
        self.conn.execute("PRAGMA foreign_keys = ON")
        self.elibrary_search_table = "elibrary_paragraph_search"

    @classmethod
    def recreate(cls, db_path: Path) -> "GodsPromisesDatabase":
        path = Path(db_path)
        if path.exists():
            path.unlink()
        return cls(path)

    def close(self) -> None:
        self.conn.close()

    def commit(self) -> None:
        self.conn.commit()

    def create_schema(self) -> None:
        cur = self.conn.cursor()

        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS sections (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE
            )
            """
        )

        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY,
                section_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                problem_text TEXT,
                FOREIGN KEY(section_id) REFERENCES sections(id)
            )
            """
        )

        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS scriptures (
                id INTEGER PRIMARY KEY,
                entry_id INTEGER NOT NULL,
                sequence_no INTEGER NOT NULL,
                reference_text TEXT NOT NULL,
                book TEXT,
                chapter INTEGER,
                verse_start INTEGER,
                verse_end INTEGER,
                FOREIGN KEY(entry_id) REFERENCES entries(id)
            )
            """
        )

        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS prayers (
                id INTEGER PRIMARY KEY,
                entry_id INTEGER NOT NULL,
                prayer_text TEXT,
                FOREIGN KEY(entry_id) REFERENCES entries(id)
            )
            """
        )

        # Helpful indexes for StudyBible2 search and display flows.
        cur.execute("CREATE INDEX IF NOT EXISTS idx_entries_section ON entries(section_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_entries_title ON entries(title)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_entries_problem ON entries(problem_text)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_scriptures_entry ON scriptures(entry_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_scriptures_entry_sequence ON scriptures(entry_id, sequence_no)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_scriptures_book ON scriptures(book)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_scriptures_reference ON scriptures(reference_text)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_sections_name ON sections(name)")

        self._create_elibrary_schema(cur)

        self.conn.commit()

    def _create_elibrary_schema(self, cur: sqlite3.Cursor) -> None:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS elibrary_works (
                id INTEGER PRIMARY KEY,
                work_id TEXT NOT NULL UNIQUE,
                author TEXT,
                title TEXT NOT NULL,
                abbreviation TEXT,
                "group" TEXT,
                subgroup TEXT,
                section TEXT,
                chapter TEXT,
                subchapter TEXT,
                source_type TEXT NOT NULL,
                source_url TEXT,
                local_source_path TEXT,
                archive_source_path TEXT,
                import_status TEXT NOT NULL DEFAULT 'pending',
                source_checksum TEXT,
                source_version TEXT,
                discovered_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                imported_at TEXT,
                notes TEXT
            )
            """
        )

        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS elibrary_paragraphs (
                id INTEGER PRIMARY KEY,
                work_id INTEGER NOT NULL,
                author TEXT,
                title TEXT NOT NULL,
                abbreviation TEXT,
                "group" TEXT,
                subgroup TEXT,
                section TEXT,
                chapter TEXT,
                subchapter TEXT,
                paragraph_number INTEGER,
                paragraph_ref TEXT,
                page_number INTEGER,
                content_text TEXT NOT NULL,
                content_hash TEXT,
                source_type TEXT NOT NULL,
                source_url TEXT,
                local_source_path TEXT,
                import_status TEXT NOT NULL DEFAULT 'imported',
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(work_id) REFERENCES elibrary_works(id) ON DELETE CASCADE
            )
            """
        )

        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS elibrary_scripture_links (
                id INTEGER PRIMARY KEY,
                work_id INTEGER NOT NULL,
                paragraph_id INTEGER NOT NULL,
                sequence_no INTEGER NOT NULL,
                original_reference TEXT NOT NULL,
                normalized_reference TEXT NOT NULL,
                book TEXT,
                chapter INTEGER,
                verse_start INTEGER,
                verse_end INTEGER,
                source_type TEXT NOT NULL,
                source_url TEXT,
                local_source_path TEXT,
                FOREIGN KEY(work_id) REFERENCES elibrary_works(id) ON DELETE CASCADE,
                FOREIGN KEY(paragraph_id) REFERENCES elibrary_paragraphs(id) ON DELETE CASCADE
            )
            """
        )

        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS elibrary_import_runs (
                id INTEGER PRIMARY KEY,
                run_label TEXT,
                started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                finished_at TEXT,
                source_root TEXT,
                report_path TEXT,
                works_discovered INTEGER NOT NULL DEFAULT 0,
                works_with_epub INTEGER NOT NULL DEFAULT 0,
                epubs_imported INTEGER NOT NULL DEFAULT 0,
                epubs_failed INTEGER NOT NULL DEFAULT 0,
                works_lacking_epub INTEGER NOT NULL DEFAULT 0,
                text_html_selected INTEGER NOT NULL DEFAULT 0,
                text_html_imported INTEGER NOT NULL DEFAULT 0,
                duplicate_titles INTEGER NOT NULL DEFAULT 0,
                paragraphs_imported INTEGER NOT NULL DEFAULT 0,
                scripture_references_detected INTEGER NOT NULL DEFAULT 0,
                errors_json TEXT
            )
            """
        )

        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_works_title ON elibrary_works(title)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_works_author ON elibrary_works(author)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_works_type ON elibrary_works(source_type)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_works_status ON elibrary_works(import_status)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_paragraphs_work ON elibrary_paragraphs(work_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_paragraphs_title ON elibrary_paragraphs(title)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_paragraphs_author ON elibrary_paragraphs(author)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_paragraphs_section ON elibrary_paragraphs(section)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_paragraphs_chapter ON elibrary_paragraphs(chapter)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_paragraphs_ref ON elibrary_paragraphs(paragraph_ref)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_scriptures_work ON elibrary_scripture_links(work_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_scriptures_paragraph ON elibrary_scripture_links(paragraph_id)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_scriptures_book ON elibrary_scripture_links(book)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_scriptures_ref ON elibrary_scripture_links(normalized_reference)")

        try:
            cur.execute(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS elibrary_paragraph_fts USING fts5(
                    title,
                    author,
                    abbreviation,
                    "group",
                    subgroup,
                    section,
                    chapter,
                    subchapter,
                    paragraph_ref,
                    content_text,
                    content_hash,
                    tokenize = 'unicode61'
                )
                """
            )
            self.elibrary_search_table = "elibrary_paragraph_fts"
        except sqlite3.OperationalError:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS elibrary_paragraph_search (
                    paragraph_id INTEGER PRIMARY KEY,
                    title TEXT,
                    author TEXT,
                    abbreviation TEXT,
                    "group" TEXT,
                    subgroup TEXT,
                    section TEXT,
                    chapter TEXT,
                    subchapter TEXT,
                    paragraph_ref TEXT,
                    content_text TEXT,
                    content_hash TEXT
                )
                """
            )
            cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_search_title ON elibrary_paragraph_search(title)")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_search_author ON elibrary_paragraph_search(author)")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_search_group ON elibrary_paragraph_search(\"group\")")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_elibrary_search_section ON elibrary_paragraph_search(section)")
            self.elibrary_search_table = "elibrary_paragraph_search"

    def insert_section(self, name: str) -> int:
        cur = self.conn.cursor()
        cur.execute("INSERT OR IGNORE INTO sections(name) VALUES(?)", (name,))
        cur.execute("SELECT id FROM sections WHERE name = ?", (name,))
        row = cur.fetchone()
        if row is None:
            raise RuntimeError(f"Failed to fetch section id for {name!r}")
        return int(row[0])

    def insert_entry(self, section_id: int, title: str, problem_text: str | None) -> int:
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO entries(section_id, title, problem_text)
            VALUES(?, ?, ?)
            """,
            (section_id, title, problem_text),
        )
        return int(cur.lastrowid)

    def insert_scripture(
        self,
        entry_id: int,
        sequence_no: int,
        reference_text: str,
        book: str | None,
        chapter: int | None,
        verse_start: int | None,
        verse_end: int | None,
    ) -> int:
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO scriptures(
                entry_id,
                sequence_no,
                reference_text,
                book,
                chapter,
                verse_start,
                verse_end
            )
            VALUES(?, ?, ?, ?, ?, ?, ?)
            """,
            (entry_id, sequence_no, reference_text, book, chapter, verse_start, verse_end),
        )
        return int(cur.lastrowid)

    def insert_prayer(self, entry_id: int, prayer_text: str | None) -> int:
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO prayers(entry_id, prayer_text)
            VALUES(?, ?)
            """,
            (entry_id, prayer_text),
        )
        return int(cur.lastrowid)

    def fetch_elibrary_work(self, work_id: str) -> dict[str, object] | None:
        cur = self.conn.cursor()
        row = cur.execute(
            """
            SELECT
                id,
                work_id,
                author,
                title,
                abbreviation,
                "group",
                subgroup,
                section,
                chapter,
                subchapter,
                source_type,
                source_url,
                local_source_path,
                archive_source_path,
                import_status,
                source_checksum,
                source_version,
                imported_at,
                notes
              FROM elibrary_works
             WHERE work_id = ?
             LIMIT 1
            """,
            (work_id,),
        ).fetchone()
        if row is None:
            return None
        columns = [
            "id",
            "work_id",
            "author",
            "title",
            "abbreviation",
            "group",
            "subgroup",
            "section",
            "chapter",
            "subchapter",
            "source_type",
            "source_url",
            "local_source_path",
            "archive_source_path",
            "import_status",
            "source_checksum",
            "source_version",
            "imported_at",
            "notes",
        ]
        return dict(zip(columns, row, strict=False))

    def update_elibrary_work_status(
        self,
        *,
        work_id: str,
        import_status: str,
        notes: str | None = None,
    ) -> None:
        cur = self.conn.cursor()
        cur.execute(
            """
            UPDATE elibrary_works
               SET import_status = ?,
                   notes = ?,
                   imported_at = CASE
                       WHEN ? = 'imported' THEN CURRENT_TIMESTAMP
                       ELSE imported_at
                   END
             WHERE work_id = ?
            """,
            (import_status, notes, import_status, work_id),
        )

    def upsert_elibrary_work(
        self,
        *,
        work_id: str,
        author: str | None,
        title: str,
        abbreviation: str | None,
        group_name: str | None,
        subgroup: str | None,
        section: str | None,
        chapter: str | None,
        subchapter: str | None,
        source_type: str,
        source_url: str | None,
        local_source_path: str | None,
        archive_source_path: str | None,
        import_status: str,
        source_checksum: str | None,
        source_version: str | None,
        notes: str | None = None,
    ) -> int:
        cur = self.conn.cursor()
        row = cur.execute("SELECT id FROM elibrary_works WHERE work_id = ?", (work_id,)).fetchone()
        if row is None:
            cur.execute(
                """
                INSERT INTO elibrary_works(
                    work_id,
                    author,
                    title,
                    abbreviation,
                    "group",
                    subgroup,
                    section,
                    chapter,
                    subchapter,
                    source_type,
                    source_url,
                    local_source_path,
                    archive_source_path,
                    import_status,
                    source_checksum,
                    source_version,
                    notes
                )
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    work_id,
                    author,
                    title,
                    abbreviation,
                    group_name,
                    subgroup,
                    section,
                    chapter,
                    subchapter,
                    source_type,
                    source_url,
                    local_source_path,
                    archive_source_path,
                    import_status,
                    source_checksum,
                    source_version,
                    notes,
                ),
            )
            return int(cur.lastrowid)

        work_db_id = int(row[0])
        cur.execute(
            """
            UPDATE elibrary_works
               SET author = ?,
                   title = ?,
                   abbreviation = ?,
                   "group" = ?,
                   subgroup = ?,
                   section = ?,
                   chapter = ?,
                   subchapter = ?,
                   source_type = ?,
                   source_url = ?,
                   local_source_path = ?,
                   archive_source_path = ?,
                   import_status = ?,
                   source_checksum = ?,
                   source_version = ?,
                   imported_at = CASE WHEN ? = 'imported' THEN CURRENT_TIMESTAMP ELSE imported_at END,
                   notes = ?
             WHERE id = ?
            """,
            (
                author,
                title,
                abbreviation,
                group_name,
                subgroup,
                section,
                chapter,
                subchapter,
                source_type,
                source_url,
                local_source_path,
                archive_source_path,
                import_status,
                source_checksum,
                source_version,
                import_status,
                notes,
                work_db_id,
            ),
        )
        return work_db_id

    def delete_elibrary_work(self, work_id: str) -> None:
        cur = self.conn.cursor()
        paragraph_ids = [
            int(row[0])
            for row in cur.execute(
                "SELECT p.id FROM elibrary_paragraphs p JOIN elibrary_works w ON w.id = p.work_id WHERE w.work_id = ?",
                (work_id,),
            ).fetchall()
        ]
        if paragraph_ids:
            placeholders = ",".join("?" for _ in paragraph_ids)
            cur.execute(f"DELETE FROM {self.elibrary_search_table} WHERE rowid IN ({placeholders})", paragraph_ids)
        cur.execute("DELETE FROM elibrary_works WHERE work_id = ?", (work_id,))

    def insert_elibrary_paragraph(
        self,
        *,
        work_id: int,
        author: str | None,
        title: str,
        abbreviation: str | None,
        group_name: str | None,
        subgroup: str | None,
        section: str | None,
        chapter: str | None,
        subchapter: str | None,
        paragraph_number: int | None,
        paragraph_ref: str | None,
        page_number: int | None,
        content_text: str,
        content_hash: str | None,
        source_type: str,
        source_url: str | None,
        local_source_path: str | None,
        import_status: str = "imported",
    ) -> int:
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO elibrary_paragraphs(
                work_id,
                author,
                title,
                abbreviation,
                "group",
                subgroup,
                section,
                chapter,
                subchapter,
                paragraph_number,
                paragraph_ref,
                page_number,
                content_text,
                content_hash,
                source_type,
                source_url,
                local_source_path,
                import_status
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                work_id,
                author,
                title,
                abbreviation,
                group_name,
                subgroup,
                section,
                chapter,
                subchapter,
                paragraph_number,
                paragraph_ref,
                page_number,
                content_text,
                content_hash,
                source_type,
                source_url,
                local_source_path,
                import_status,
            ),
        )
        paragraph_id = int(cur.lastrowid)

        if self.elibrary_search_table == "elibrary_paragraph_fts":
            cur.execute(
                """
                INSERT INTO elibrary_paragraph_fts(
                    rowid,
                    title,
                    author,
                    abbreviation,
                    "group",
                    subgroup,
                    section,
                    chapter,
                    subchapter,
                    paragraph_ref,
                    content_text,
                    content_hash
                )
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    paragraph_id,
                    title,
                    author,
                    abbreviation,
                    group_name,
                    subgroup,
                    section,
                    chapter,
                    subchapter,
                    paragraph_ref,
                    content_text,
                    content_hash,
                ),
            )
        else:
            cur.execute(
                """
                INSERT OR REPLACE INTO elibrary_paragraph_search(
                    paragraph_id,
                    title,
                    author,
                    abbreviation,
                    "group",
                    subgroup,
                    section,
                    chapter,
                    subchapter,
                    paragraph_ref,
                    content_text,
                    content_hash
                )
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    paragraph_id,
                    title,
                    author,
                    abbreviation,
                    group_name,
                    subgroup,
                    section,
                    chapter,
                    subchapter,
                    paragraph_ref,
                    content_text,
                    content_hash,
                ),
            )

        return paragraph_id

    def insert_elibrary_scripture_link(
        self,
        *,
        work_id: int,
        paragraph_id: int,
        sequence_no: int,
        original_reference: str,
        normalized_reference: str,
        book: str | None,
        chapter: int | None,
        verse_start: int | None,
        verse_end: int | None,
        source_type: str,
        source_url: str | None,
        local_source_path: str | None,
    ) -> int:
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO elibrary_scripture_links(
                work_id,
                paragraph_id,
                sequence_no,
                original_reference,
                normalized_reference,
                book,
                chapter,
                verse_start,
                verse_end,
                source_type,
                source_url,
                local_source_path
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                work_id,
                paragraph_id,
                sequence_no,
                original_reference,
                normalized_reference,
                book,
                chapter,
                verse_start,
                verse_end,
                source_type,
                source_url,
                local_source_path,
            ),
        )
        return int(cur.lastrowid)

    def record_elibrary_import_run(
        self,
        *,
        run_label: str | None,
        source_root: str | None,
        report_path: str | None,
        works_discovered: int,
        works_with_epub: int,
        epubs_imported: int,
        epubs_failed: int,
        works_lacking_epub: int,
        text_html_selected: int,
        text_html_imported: int,
        duplicate_titles: int,
        paragraphs_imported: int,
        scripture_references_detected: int,
        errors_json: str | None,
        finished_at: str | None = None,
    ) -> int:
        cur = self.conn.cursor()
        cur.execute(
            """
            INSERT INTO elibrary_import_runs(
                run_label,
                source_root,
                report_path,
                works_discovered,
                works_with_epub,
                epubs_imported,
                epubs_failed,
                works_lacking_epub,
                text_html_selected,
                text_html_imported,
                duplicate_titles,
                paragraphs_imported,
                scripture_references_detected,
                errors_json,
                finished_at
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                run_label,
                source_root,
                report_path,
                works_discovered,
                works_with_epub,
                epubs_imported,
                epubs_failed,
                works_lacking_epub,
                text_html_selected,
                text_html_imported,
                duplicate_titles,
                paragraphs_imported,
                scripture_references_detected,
                errors_json,
                finished_at,
            ),
        )
        return int(cur.lastrowid)
