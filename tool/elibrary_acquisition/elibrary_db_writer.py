#!/usr/bin/env python3
"""
elibrary_db_writer.py

Write normalized eLibrary bundles into SQLite.
"""

from __future__ import annotations

from pathlib import Path

from database import GodsPromisesDatabase
from elibrary_import_normalizer import NormalizedParagraph, NormalizedWork, NormalizedWorkBundle, content_checksum
from elibrary_import_normalizer import make_work_id
from source_inventory_service import SourceInventoryItem


class ElibraryDBWriter:
    def __init__(self, db_path: Path):
        self.db = GodsPromisesDatabase(db_path)
        self.db.create_schema()

    def close(self) -> None:
        self.db.close()

    def commit(self) -> None:
        self.db.commit()

    def record_source_item(self, item: SourceInventoryItem, import_status: str, notes: str | None = None) -> int:
        work_id = make_work_id(
            title=item.title,
            author=item.author,
            source_type=item.source_type,
            local_source_path=str(item.path),
            source_url=item.source_url,
        )
        return self.db.upsert_elibrary_work(
            work_id=work_id,
            author=item.author,
            title=item.title,
            abbreviation=item.abbreviation,
            group_name=item.group,
            subgroup=item.subgroup,
            section=item.section,
            chapter=item.chapter,
            subchapter=item.subchapter,
            source_type=item.source_type,
            source_url=item.source_url,
            local_source_path=str(item.path),
            archive_source_path=str(item.path) if item.source_type == "epub" else None,
            import_status=import_status,
            source_checksum=item.checksum,
            source_version=None,
            notes=notes,
        )

    def import_bundle(self, bundle: NormalizedWorkBundle) -> dict[str, int]:
        work = bundle.work
        self.db.delete_elibrary_work(work.work_id)
        work_db_id = self.db.upsert_elibrary_work(
            work_id=work.work_id,
            author=work.author,
            title=work.title,
            abbreviation=work.abbreviation,
            group_name=work.group,
            subgroup=work.subgroup,
            section=work.section,
            chapter=work.chapter,
            subchapter=work.subchapter,
            source_type=work.source_type,
            source_url=work.source_url,
            local_source_path=work.local_source_path,
            archive_source_path=work.archive_source_path,
            import_status="imported",
            source_checksum=work.source_checksum,
            source_version=work.source_version,
            notes=work.notes,
        )

        paragraphs_imported = 0
        scripture_links_imported = 0
        for paragraph in bundle.paragraphs:
            paragraph_id = self.db.insert_elibrary_paragraph(
                work_id=work_db_id,
                author=work.author,
                title=work.title,
                abbreviation=work.abbreviation,
                group_name=work.group,
                subgroup=work.subgroup,
                section=paragraph.section or work.section,
                chapter=paragraph.chapter or work.chapter,
                subchapter=paragraph.subchapter or work.subchapter,
                paragraph_number=paragraph.paragraph_number,
                paragraph_ref=paragraph.paragraph_ref,
                page_number=paragraph.page_number,
                content_text=paragraph.content_text,
                content_hash=content_checksum(paragraph.content_text),
                source_type=work.source_type,
                source_url=work.source_url,
                local_source_path=work.local_source_path,
                import_status="imported",
            )
            paragraphs_imported += 1

            for sequence_no, ref in enumerate(paragraph.embedded_scripture_refs, start=1):
                self.db.insert_elibrary_scripture_link(
                    work_id=work_db_id,
                    paragraph_id=paragraph_id,
                    sequence_no=sequence_no,
                    original_reference=ref.original_reference,
                    normalized_reference=ref.normalized_reference,
                    book=ref.book,
                    chapter=ref.chapter,
                    verse_start=ref.verse_start,
                    verse_end=ref.verse_end,
                    source_type=work.source_type,
                    source_url=work.source_url,
                    local_source_path=work.local_source_path,
                )
                scripture_links_imported += 1

        self.commit()
        return {
            "work_id": work_db_id,
            "paragraphs_imported": paragraphs_imported,
            "scripture_links_imported": scripture_links_imported,
        }

    def search_paragraphs(self, query: str, limit: int = 20) -> list[dict[str, object]]:
        cur = self.db.conn.cursor()
        table = self.db.elibrary_search_table
        if table == "elibrary_paragraph_fts":
            rows = cur.execute(
                f"""
                SELECT rowid, title, author, paragraph_ref, content_text
                  FROM {table}
                 WHERE {table} MATCH ?
                 LIMIT ?
                """,
                (query, limit),
            ).fetchall()
            return [
                {
                    "paragraph_id": int(row[0]),
                    "title": row[1],
                    "author": row[2],
                    "paragraph_ref": row[3],
                    "content_text": row[4],
                }
                for row in rows
            ]

        pattern = f"%{query}%"
        rows = cur.execute(
            """
            SELECT paragraph_id, title, author, paragraph_ref, content_text
              FROM elibrary_paragraph_search
             WHERE content_text LIKE ?
                OR title LIKE ?
                OR author LIKE ?
             LIMIT ?
            """,
            (pattern, pattern, pattern, limit),
        ).fetchall()
        return [
            {
                "paragraph_id": int(row[0]),
                "title": row[1],
                "author": row[2],
                "paragraph_ref": row[3],
                "content_text": row[4],
            }
            for row in rows
        ]
