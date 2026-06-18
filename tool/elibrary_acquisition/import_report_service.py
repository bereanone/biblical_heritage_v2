#!/usr/bin/env python3
"""
import_report_service.py

Track and render the acquisition/import report for the normalized eLibrary
workflow.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class ImportReport:
    import_run_id: int | None = None
    source_root: Path | None = None
    db_path: Path | None = None
    works_discovered: int = 0
    works_with_epub: int = 0
    epub_ready_works: int = 0
    non_epub_discoverable_works: int = 0
    epubs_imported_successfully: int = 0
    epubs_skipped_unchanged: int = 0
    epubs_failed_or_corrupt: list[str] = field(default_factory=list)
    works_lacking_epub: int = 0
    non_epub_skipped_default: int = 0
    text_html_selected: int = 0
    text_html_imported: int = 0
    text_html_skipped_unchanged: int = 0
    text_import_skipped: int = 0
    text_import_failed: int = 0
    verification_required: int = 0
    duplicate_titles: Counter[str] = field(default_factory=Counter)
    paragraphs_imported: int = 0
    scripture_references_detected: int = 0
    imported_works: list[str] = field(default_factory=list)
    already_imported_works: list[str] = field(default_factory=list)
    skipped_works: list[str] = field(default_factory=list)
    selected_documents: list[str] = field(default_factory=list)
    verification_documents: list[str] = field(default_factory=list)
    user_action_required: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def add_error(self, message: str) -> None:
        self.errors.append(message)

    def add_user_action(self, message: str) -> None:
        self.user_action_required.append(message)


def render_import_report(report: ImportReport) -> str:
    lines: list[str] = []
    lines.append("eLibrary Import Report")
    if report.import_run_id is not None:
        lines.append(f"Import run id: {report.import_run_id}")
    if report.source_root is not None:
        lines.append(f"Source root: {report.source_root}")
    if report.db_path is not None:
        lines.append(f"Database: {report.db_path}")
    lines.append("")
    lines.append(f"Works discovered: {report.works_discovered}")
    lines.append(f"Works with EPUB: {report.works_with_epub}")
    lines.append(f"EPUB works ready for import: {report.epub_ready_works}")
    lines.append(f"EPUBs imported successfully: {report.epubs_imported_successfully}")
    lines.append(f"EPUBs skipped unchanged: {report.epubs_skipped_unchanged}")
    lines.append(f"EPUBs failed or corrupt: {len(report.epubs_failed_or_corrupt)}")
    lines.append(f"Works lacking EPUB: {report.works_lacking_epub}")
    lines.append(f"Non-EPUB works discovered: {report.non_epub_discoverable_works}")
    lines.append(f"Non-EPUB works skipped by default: {report.non_epub_skipped_default}")
    lines.append(f"Text/HTML works selected: {report.text_html_selected}")
    lines.append(f"Text/HTML works imported: {report.text_html_imported}")
    lines.append(f"Text/HTML works skipped unchanged: {report.text_html_skipped_unchanged}")
    lines.append(f"Verification-required documents: {report.verification_required}")
    lines.append(f"Text import skipped: {report.text_import_skipped}")
    lines.append(f"Text import failed: {report.text_import_failed}")
    lines.append(f"Duplicate titles: {sum(count - 1 for count in report.duplicate_titles.values() if count > 1)}")
    lines.append(f"Paragraphs imported: {report.paragraphs_imported}")
    lines.append(f"Scripture references detected: {report.scripture_references_detected}")
    lines.append("")

    lines.append("EPUB failures:")
    if report.epubs_failed_or_corrupt:
        lines.extend(f"- {item}" for item in report.epubs_failed_or_corrupt)
    else:
        lines.append("- none")

    lines.append("")
    lines.append("Duplicate titles:")
    if report.duplicate_titles:
        for title, count in sorted(report.duplicate_titles.items(), key=lambda item: (-item[1], item[0].lower())):
            if count > 1:
                lines.append(f"- {title} ({count})")
    else:
        lines.append("- none")

    lines.append("")
    lines.append("Imported works:")
    if report.imported_works:
        lines.extend(f"- {item}" for item in report.imported_works)
    else:
        lines.append("- none")

    lines.append("")
    lines.append("Already imported / unchanged:")
    if report.already_imported_works:
        lines.extend(f"- {item}" for item in report.already_imported_works)
    else:
        lines.append("- none")

    lines.append("")
    lines.append("Skipped works:")
    if report.skipped_works:
        lines.extend(f"- {item}" for item in report.skipped_works)
    else:
        lines.append("- none")

    lines.append("")
    lines.append("Verification-required documents:")
    if report.verification_documents:
        lines.extend(f"- {item}" for item in report.verification_documents)
    else:
        lines.append("- none")

    lines.append("")
    lines.append("User action required:")
    if report.user_action_required:
        lines.extend(f"- {item}" for item in report.user_action_required)
    else:
        lines.append("- none")

    lines.append("")
    lines.append("Errors:")
    if report.errors:
        lines.extend(f"- {item}" for item in report.errors)
    else:
        lines.append("- none")

    return "\n".join(lines) + "\n"
