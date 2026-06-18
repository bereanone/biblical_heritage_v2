#!/usr/bin/env python3
"""
elibrary_import.py

EPUB-first acquisition workflow for StudyBible2 eLibrary sources.

This script discovers source files, auto-imports EPUBs, and only imports
plain text / HTML sources when the user explicitly selects them.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import json
from pathlib import Path
import sqlite3

from elibrary_db_writer import ElibraryDBWriter
from epub_acquisition_service import parse_epub_bundle
from elibrary_import_normalizer import clean_text, make_work_id
from import_report_service import ImportReport, render_import_report
from online_source_search_service import search_inventory_locally
from source_inventory_service import (
    SourceInventoryItem,
    filter_inventory,
    format_inventory_summary,
    group_inventory_items,
    scan_source_root,
    document_display_name,
)
from text_acquisition_service import VerificationRequiredError, acquire_text_or_html_bundle


@dataclass(frozen=True)
class SourceStatusEntry:
    display_name: str
    bucket: str
    source_type: str
    path: Path
    author: str | None
    title: str
    group: str | None
    subgroup: str | None
    source_url: str | None
    reason: str | None = None


@dataclass
class SourceStatusDashboard:
    epub_ready: list[SourceStatusEntry]
    epub_unchanged: list[SourceStatusEntry]
    epub_changed: list[SourceStatusEntry]
    epub_failed: list[SourceStatusEntry]
    text_ready: list[SourceStatusEntry]
    text_unchanged: list[SourceStatusEntry]
    text_changed: list[SourceStatusEntry]
    text_verification_required: list[SourceStatusEntry]
    text_failed: list[SourceStatusEntry]
    unsupported_skipped: list[SourceStatusEntry]


def _parse_csv_values(value: str | None) -> set[str] | None:
    if value is None:
        return None
    values = {part.strip() for part in value.split(",") if part.strip()}
    return values or None


def _load_elibrary_work_records(db_path: Path) -> dict[str, dict[str, object]]:
    if not db_path.exists():
        return {}

    with sqlite3.connect(db_path) as conn:
        table_exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='elibrary_works'"
        ).fetchone()
        if table_exists is None:
            return {}

        rows = conn.execute(
            """
            SELECT
                work_id,
                author,
                title,
                abbreviation,
                "group",
                subgroup,
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
            """
        ).fetchall()

    records: dict[str, dict[str, object]] = {}
    for row in rows:
        records[row[0]] = {
            "work_id": row[0],
            "author": row[1],
            "title": row[2],
            "abbreviation": row[3],
            "group": row[4],
            "subgroup": row[5],
            "source_type": row[6],
            "source_url": row[7],
            "local_source_path": row[8],
            "archive_source_path": row[9],
            "import_status": row[10],
            "source_checksum": row[11],
            "source_version": row[12],
            "imported_at": row[13],
            "notes": row[14],
        }
    return records


def _source_work_id(item: SourceInventoryItem) -> str:
    return make_work_id(
        title=item.title,
        author=item.author,
        source_type=item.source_type,
        local_source_path=str(item.path),
        source_url=item.source_url,
    )


def _is_unchanged_import(writer: ElibraryDBWriter, item: SourceInventoryItem) -> dict[str, object] | None:
    row = writer.db.fetch_elibrary_work(_source_work_id(item))
    if row is None:
        return None
    if row.get("import_status") == "imported" and row.get("source_checksum") == item.checksum:
        return row
    return None


def _status_display_name(item: SourceInventoryItem, source_root: Path) -> str:
    return document_display_name(item, source_root)


def _status_reason_for_record(
    item: SourceInventoryItem,
    record: dict[str, object] | None,
) -> tuple[str, str | None]:
    if record is None:
        if item.source_type == "epub":
            return "ready", "No existing database record."
        return "ready", "No existing database record."

    import_status = clean_text(record.get("import_status") or "").lower()
    stored_checksum = clean_text(record.get("source_checksum") or "")
    current_checksum = clean_text(item.checksum or "")
    notes = clean_text(record.get("notes") or "") or None

    if import_status == "verification_required":
        reason = notes or "Source previously required manual verification."
        if stored_checksum and current_checksum and stored_checksum != current_checksum:
            reason = f"{reason} Checksum changed since last attempt."
        return "verification_required", reason

    if import_status == "failed":
        reason = notes or "Previous import attempt failed."
        if stored_checksum and current_checksum and stored_checksum != current_checksum:
            reason = f"{reason} Checksum changed since last attempt."
        return "failed", reason

    if import_status == "imported":
        if stored_checksum and current_checksum and stored_checksum == current_checksum:
            return "unchanged", "Checksum matches imported record."
        return "changed", "Checksum changed since import."

    return "ready", f"Existing status: {import_status}" if import_status else "No blocking status recorded."


def _make_status_entry(
    item: SourceInventoryItem,
    source_root: Path,
    bucket: str,
    reason: str | None,
) -> SourceStatusEntry:
    return SourceStatusEntry(
        display_name=_status_display_name(item, source_root),
        bucket=bucket,
        source_type=item.source_type,
        path=item.path,
        author=item.author,
        title=item.title,
        group=item.group,
        subgroup=item.subgroup,
        source_url=item.source_url,
        reason=reason,
    )


def _build_source_status_dashboard(
    source_root: Path,
    db_path: Path,
    *,
    report_path: Path,
) -> SourceStatusDashboard:
    discovery = scan_source_root(source_root)
    excluded_paths = {db_path.resolve(), report_path.resolve()}
    excluded_names = {db_path.name, report_path.name, "import_report.txt", "elibrary_import_report.txt"}
    inventory = [
        item
        for item in discovery.supported
        if item.path.resolve() not in excluded_paths and item.path.name not in excluded_names
    ]
    unsupported_paths = [
        path
        for path in discovery.unsupported
        if path.resolve() not in excluded_paths and path.name not in excluded_names
    ]
    records = _load_elibrary_work_records(db_path)

    dashboard = SourceStatusDashboard(
        epub_ready=[],
        epub_unchanged=[],
        epub_changed=[],
        epub_failed=[],
        text_ready=[],
        text_unchanged=[],
        text_changed=[],
        text_verification_required=[],
        text_failed=[],
        unsupported_skipped=[],
    )

    for item in inventory:
        record = records.get(_source_work_id(item))
        status, reason = _status_reason_for_record(item, record)

        if item.source_type == "epub":
            if status == "ready":
                dashboard.epub_ready.append(_make_status_entry(item, source_root, "ready", reason))
            elif status == "unchanged":
                dashboard.epub_unchanged.append(_make_status_entry(item, source_root, "unchanged", reason))
            elif status == "changed":
                dashboard.epub_changed.append(_make_status_entry(item, source_root, "changed", reason))
            elif status == "failed":
                dashboard.epub_failed.append(_make_status_entry(item, source_root, "failed", reason))
            elif status == "verification_required":
                dashboard.epub_failed.append(_make_status_entry(item, source_root, "verification_required", reason))
            else:
                dashboard.epub_ready.append(_make_status_entry(item, source_root, "ready", reason))
            continue

        if status == "ready":
            dashboard.text_ready.append(_make_status_entry(item, source_root, "ready_for_selection", reason))
        elif status == "unchanged":
            dashboard.text_unchanged.append(_make_status_entry(item, source_root, "unchanged", reason))
        elif status == "changed":
            dashboard.text_changed.append(_make_status_entry(item, source_root, "changed", reason))
        elif status == "verification_required":
            dashboard.text_verification_required.append(
                _make_status_entry(item, source_root, "verification_required", reason)
            )
        elif status == "failed":
            dashboard.text_failed.append(_make_status_entry(item, source_root, "failed", reason))
        else:
            dashboard.text_ready.append(_make_status_entry(item, source_root, "ready_for_selection", reason))

    for path in unsupported_paths:
        display_name = clean_text(path.stem.replace("_", " "))
        dashboard.unsupported_skipped.append(
            SourceStatusEntry(
                display_name=display_name or path.name,
                bucket="unsupported",
                source_type=path.suffix.lower().lstrip(".") or "unsupported",
                path=path,
                author=None,
                title=display_name or path.stem,
                group=None,
                subgroup=None,
                source_url=None,
                reason="Unsupported or skipped file type.",
            )
        )

    return dashboard


def _print_inventory(items, source_root: Path | None = None) -> None:
    print(format_inventory_summary(items, source_root))


def _print_skipped_sources(items: list[Path]) -> None:
    if not items:
        return
    print("Skipped unsupported files:")
    for path in items:
        print(f"- {path}")


def _parse_selection_numbers(raw: str, limit: int) -> list[int]:
    values: list[int] = []
    for token in raw.split(","):
        token = token.strip()
        if not token or not token.isdigit():
            continue
        index = int(token)
        if 1 <= index <= limit:
            values.append(index)
    return values


def _select_items_from_matches(items: list[SourceInventoryItem], source_root: Path, prompt: str) -> list[SourceInventoryItem]:
    if not items:
        return []
    print(prompt)
    for index, item in enumerate(items, start=1):
        print(f"{index}. {document_display_name(item, source_root)} | {item.source_type} | {item.path}")
    raw = input("Enter numbers to import, 'a' for all matches, or blank to cancel: ").strip().lower()
    if not raw:
        return []
    if raw in {"a", "all"}:
        return list(items)
    selected: list[SourceInventoryItem] = []
    for index in _parse_selection_numbers(raw, len(items)):
        selected.append(items[index - 1])
    return selected


def _interactive_import_menu(
    *,
    writer: ElibraryDBWriter,
    report: ImportReport,
    source_root: Path,
    non_epub_items: list[SourceInventoryItem],
) -> None:
    remaining = list(non_epub_items)
    while True:
        print("")
        print("Non-EPUB sources:")
        _print_inventory(remaining, source_root)
        print("")
        print("Menu:")
        print("  a) import all remaining non-EPUB documents")
        print("  l) list grouped authors / groups")
        print("  g) import all documents for one author/group/folder")
        print("  s) search/filter document list by title or path")
        print("  n) import selected document numbers")
        print("  q) quit")

        choice = input("Choose an action: ").strip().lower()
        if not choice or choice in {"q", "quit"}:
            break

        if choice in {"a", "all"}:
            selected = list(remaining)
            if not selected:
                print("No non-EPUB documents remain.")
                continue
            _import_text_sources(writer, report, selected)
            remaining = [item for item in remaining if item not in selected]
            continue

        if choice in {"l", "list"}:
            grouped = group_inventory_items(remaining, source_root)
            for label, docs in grouped.items():
                print(f"{label} [{len(docs)} docs]")
                for index, item in enumerate(docs, start=1):
                    print(f"  {index}. {item.title} | {item.source_type} | {item.path.name}")
            continue

        if choice in {"g", "group", "author"}:
            grouped = group_inventory_items(remaining, source_root)
            labels = list(grouped.keys())
            if not labels:
                print("No grouped documents available.")
                continue
            for index, label in enumerate(labels, start=1):
                print(f"{index}. {label} [{len(grouped[label])} docs]")
            raw = input("Enter a group number to import, or blank to cancel: ").strip()
            if not raw.isdigit():
                continue
            selected_index = int(raw)
            if not 1 <= selected_index <= len(labels):
                continue
            selected = list(grouped[labels[selected_index - 1]])
            _import_text_sources(writer, report, selected)
            remaining = [item for item in remaining if item not in selected]
            continue

        if choice in {"s", "search", "filter"}:
            query = input("Enter a title or path search term: ").strip()
            if not query:
                continue
            matches = search_inventory_locally(remaining, query)
            selected = _select_items_from_matches([match.item for match in matches], source_root, "Search matches:")
            if not selected:
                continue
            _import_text_sources(writer, report, selected)
            remaining = [item for item in remaining if item not in selected]
            continue

        if choice in {"n", "numbers", "select"}:
            selected = _select_items_from_matches(remaining, source_root, "Available non-EPUB documents:")
            if not selected:
                continue
            _import_text_sources(writer, report, selected)
            remaining = [item for item in remaining if item not in selected]
            continue

        print("Unrecognized option. Please choose a listed action.")


def _import_text_sources(
    writer: ElibraryDBWriter,
    report: ImportReport,
    selected_text_items: list[SourceInventoryItem],
) -> None:
    report.text_html_selected += len(selected_text_items)
    for item in selected_text_items:
        report.selected_documents.append(f"{item.path} [{item.source_type}]")
        existing = _is_unchanged_import(writer, item)
        if existing is not None:
            report.text_html_skipped_unchanged += 1
            report.already_imported_works.append(f"{item.title} [{item.source_type}]")
            continue
        try:
            bundle = acquire_text_or_html_bundle(item)
            stats = writer.import_bundle(bundle)
            report.text_html_imported += 1
            report.paragraphs_imported += stats["paragraphs_imported"]
            report.scripture_references_detected += stats["scripture_links_imported"]
            report.imported_works.append(f"{bundle.work.title} [{item.source_type}]")
        except VerificationRequiredError as exc:
            report.verification_required += 1
            report.text_import_skipped += 1
            source_hint = exc.source_url or item.source_url or str(item.path)
            message = (
                f"Source site verification required for {item.path}. "
                f"Open this URL in a browser, complete the verification manually, then retry import."
            )
            if source_hint:
                message = f"{message} URL: {source_hint}"
            report.verification_documents.append(message)
            report.user_action_required.append(message)
            writer.record_source_item(item, "verification_required", notes=message)
        except Exception as exc:  # noqa: BLE001
            report.text_import_failed += 1
            report.add_error(f"{item.path}: {exc}")
            writer.record_source_item(item, "failed", notes=str(exc))


def _print_non_epub_summary(items: list[SourceInventoryItem], source_root: Path) -> None:
    grouped = group_inventory_items(items, source_root)
    print("Non-EPUB document groups:")
    for label, docs in grouped.items():
        print(f"{label} [{len(docs)} docs]")
        for index, item in enumerate(docs, start=1):
            print(f"  {index}. {item.title} | {item.source_type} | {item.path}")


def _print_summary(db_path: Path) -> None:
    with sqlite3.connect(db_path) as conn:
        def _count_table(name: str) -> int:
            row = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
                (name,),
            ).fetchone()
            if row is None:
                return 0
            return int(conn.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0])

        counts = {
            "elibrary_works": _count_table("elibrary_works"),
            "elibrary_paragraphs": _count_table("elibrary_paragraphs"),
            "elibrary_scripture_links": _count_table("elibrary_scripture_links"),
            "elibrary_import_runs": _count_table("elibrary_import_runs"),
        }
        search_tables = [
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('elibrary_paragraph_fts', 'elibrary_paragraph_search')"
            )
        ]

    print(f"Database: {db_path}")
    for table_name, count in counts.items():
        print(f"{table_name}: {count}")
    if "elibrary_paragraph_fts" in search_tables:
        print("FTS status: enabled (elibrary_paragraph_fts)")
    elif "elibrary_paragraph_search" in search_tables:
        print("FTS status: fallback table (elibrary_paragraph_search)")
    else:
        print("FTS status: unavailable")


def _print_status_bucket(title: str, count: int) -> None:
    print(f"  {title}: {count}")


def _print_status_entries(entries: list[SourceStatusEntry], *, verbose: bool) -> None:
    if not verbose:
        return
    for entry in entries:
        parts = [entry.display_name, f"status={entry.bucket}", f"path={entry.path}"]
        if entry.source_url:
            parts.append(f"url={entry.source_url}")
        if entry.reason:
            parts.append(f"reason={entry.reason}")
        print(f"    - {' | '.join(parts)}")


def _print_source_status_dashboard(dashboard: SourceStatusDashboard, source_root: Path, db_path: Path, *, verbose: bool) -> None:
    print("eLibrary Source Status")
    print(f"Source root: {source_root}")
    print(f"Database: {db_path}")
    print("")
    print("EPUB:")
    _print_status_bucket("ready", len(dashboard.epub_ready))
    _print_status_bucket("unchanged", len(dashboard.epub_unchanged))
    _print_status_bucket("changed", len(dashboard.epub_changed))
    _print_status_bucket("failed", len(dashboard.epub_failed))
    if verbose:
        _print_status_entries(dashboard.epub_ready, verbose=verbose)
        _print_status_entries(dashboard.epub_unchanged, verbose=verbose)
        _print_status_entries(dashboard.epub_changed, verbose=verbose)
        _print_status_entries(dashboard.epub_failed, verbose=verbose)

    print("")
    print("Text/HTML:")
    _print_status_bucket("ready for selection", len(dashboard.text_ready))
    _print_status_bucket("unchanged", len(dashboard.text_unchanged))
    _print_status_bucket("changed", len(dashboard.text_changed))
    _print_status_bucket("verification required", len(dashboard.text_verification_required))
    _print_status_bucket("failed", len(dashboard.text_failed))
    if verbose:
        _print_status_entries(dashboard.text_ready, verbose=verbose)
        _print_status_entries(dashboard.text_unchanged, verbose=verbose)
        _print_status_entries(dashboard.text_changed, verbose=verbose)
        _print_status_entries(dashboard.text_verification_required, verbose=verbose)
        _print_status_entries(dashboard.text_failed, verbose=verbose)

    print("")
    print("Unsupported:")
    _print_status_bucket("skipped", len(dashboard.unsupported_skipped))
    if verbose:
        _print_status_entries(dashboard.unsupported_skipped, verbose=verbose)


def run_acquisition(
    source_root: Path,
    db_path: Path,
    report_path: Path,
    *,
    authors: set[str] | None = None,
    titles: set[str] | None = None,
    groups: set[str] | None = None,
    search_query: str | None = None,
    include_text: bool = False,
    interactive: bool = False,
) -> ImportReport:
    discovery = scan_source_root(source_root)
    excluded_paths = {db_path.resolve(), report_path.resolve()}
    excluded_names = {db_path.name, report_path.name, "import_report.txt", "elibrary_import_report.txt"}
    inventory = [
        item
        for item in discovery.supported
        if item.path.resolve() not in excluded_paths and item.path.name not in excluded_names
    ]
    unsupported_paths = [
        path
        for path in discovery.unsupported
        if path.resolve() not in excluded_paths and path.name not in excluded_names
    ]
    report = ImportReport(source_root=source_root, db_path=db_path)
    report.works_discovered = len(inventory)
    report.works_with_epub = sum(1 for item in inventory if item.is_epub)
    report.epub_ready_works = report.works_with_epub
    report.non_epub_discoverable_works = sum(1 for item in inventory if not item.is_epub)
    report.works_lacking_epub = report.works_discovered - report.works_with_epub
    report.duplicate_titles = Counter(
        {title: count for title, count in Counter(item.title for item in inventory).items() if count > 1}
    )
    report.skipped_works = [str(path) for path in unsupported_paths]

    epub_items = [item for item in inventory if item.is_epub]
    non_epub_items = [item for item in inventory if not item.is_epub]
    report.non_epub_skipped_default = len(non_epub_items)

    writer = ElibraryDBWriter(db_path)
    try:
        for item in epub_items:
            existing = _is_unchanged_import(writer, item)
            if existing is not None:
                report.epubs_skipped_unchanged += 1
                report.already_imported_works.append(f"{item.title} [{item.source_type}]")
                continue
            try:
                bundle = parse_epub_bundle(item)
                stats = writer.import_bundle(bundle)
                report.epubs_imported_successfully += 1
                report.paragraphs_imported += stats["paragraphs_imported"]
                report.scripture_references_detected += stats["scripture_links_imported"]
                report.imported_works.append(f"{bundle.work.title} [{item.source_type}]")
            except Exception as exc:  # noqa: BLE001 - surface as a user-facing import failure
                report.epubs_failed_or_corrupt.append(f"{item.path}: {exc}")
                writer.record_source_item(item, "failed", notes=str(exc))

        has_text_filters = any([authors, titles, groups, search_query, include_text])
        selected_text_items: list[SourceInventoryItem] = []

        if interactive:
            _print_non_epub_summary(non_epub_items, source_root)
            _print_skipped_sources(unsupported_paths)
            _interactive_import_menu(
                writer=writer,
                report=report,
                source_root=source_root,
                non_epub_items=filter_inventory(non_epub_items, authors=authors, titles=titles, groups=groups)
                if any([authors, titles, groups])
                else list(non_epub_items),
            )
        else:
            if include_text:
                selected_text_items = filter_inventory(non_epub_items, authors=authors, titles=titles, groups=groups)
                if search_query:
                    selected_text_items = search_inventory_locally(selected_text_items, search_query)
                    selected_text_items = [result.item for result in selected_text_items]
                elif not any([authors, titles, groups]):
                    selected_text_items = list(non_epub_items)
            elif has_text_filters:
                selected_text_items = filter_inventory(non_epub_items, authors=authors, titles=titles, groups=groups)
                if search_query:
                    matches = search_inventory_locally(selected_text_items, search_query)
                    selected_text_items = [result.item for result in matches]
            elif search_query:
                matches = search_inventory_locally(non_epub_items, search_query)
                selected_text_items = [result.item for result in matches]

            if selected_text_items:
                _import_text_sources(writer, report, selected_text_items)

        report.text_import_skipped = max(
            0,
            report.non_epub_discoverable_works
            - report.text_html_imported
            - report.verification_required
            - report.text_import_failed
            - report.text_html_skipped_unchanged,
        )
        if report.text_import_skipped and not report.user_action_required:
            report.add_user_action("Non-EPUB sources were discovered but not selected for import.")

        import_run_id = writer.db.record_elibrary_import_run(
            run_label=source_root.name or None,
            source_root=str(source_root),
            report_path=str(report_path),
            works_discovered=report.works_discovered,
            works_with_epub=report.works_with_epub,
            epubs_imported=report.epubs_imported_successfully,
            epubs_failed=len(report.epubs_failed_or_corrupt),
            works_lacking_epub=report.works_lacking_epub,
            text_html_selected=report.text_html_selected,
            text_html_imported=report.text_html_imported,
            duplicate_titles=sum(count - 1 for count in report.duplicate_titles.values() if count > 1),
            paragraphs_imported=report.paragraphs_imported,
            scripture_references_detected=report.scripture_references_detected,
            errors_json=json.dumps({"errors": report.errors, "user_action_required": report.user_action_required}),
        )
        report.import_run_id = import_run_id
        writer.commit()
    finally:
        writer.close()

    report_text = render_import_report(report)
    report_path.write_text(report_text, encoding="utf-8")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="EPUB-first StudyBible2 eLibrary acquisition workflow.")
    parser.add_argument("source_root", type=Path, nargs="?", default=Path("."), help="Source directory or file to inventory")
    parser.add_argument("--db", type=Path, default=Path("elibrary.db"), help="Output SQLite database")
    parser.add_argument(
        "--report",
        type=Path,
        default=Path("elibrary_import_report.txt"),
        help="Write the import report here",
    )
    parser.add_argument("--author", help="Restrict plain-text/HTML import to authors (comma-separated)")
    parser.add_argument("--title", help="Restrict plain-text/HTML import to titles (comma-separated)")
    parser.add_argument("--group", help="Restrict plain-text/HTML import to groups (comma-separated)")
    parser.add_argument("--filter", dest="search", help="Search unimported text/HTML sources before import")
    parser.add_argument("--search", dest="search", help=argparse.SUPPRESS)
    parser.add_argument("--include-text", action="store_true", help="Import selected non-EPUB text/HTML sources")
    parser.add_argument("--interactive", action="store_true", help="Prompt for selective text/HTML import")
    parser.add_argument("--status", action="store_true", help="Show source status dashboard without importing")
    parser.add_argument("--verbose", action="store_true", help="Show detailed lines for status/dashboard output")
    parser.add_argument("--summary", action="store_true", help="Print database counts and exit")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if args.status:
        dashboard = _build_source_status_dashboard(args.source_root, args.db, report_path=args.report)
        _print_source_status_dashboard(dashboard, args.source_root, args.db, verbose=args.verbose)
        return

    if args.summary:
        _print_summary(args.db)
        return

    if not args.source_root.exists():
        raise FileNotFoundError(f"Source not found: {args.source_root}")

    report = run_acquisition(
        args.source_root,
        args.db,
        args.report,
        authors=_parse_csv_values(args.author),
        titles=_parse_csv_values(args.title),
        groups=_parse_csv_values(args.group),
        search_query=args.search,
        include_text=args.include_text,
        interactive=args.interactive,
    )

    print(render_import_report(report))


if __name__ == "__main__":
    main()
