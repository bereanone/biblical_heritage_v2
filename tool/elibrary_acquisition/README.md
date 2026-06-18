# eLibrary Acquisition Prototype

This folder holds the recovered Python acquisition prototype for StudyBible2.
It is tooling/prototype code for personal-use acquisition workflows, not the
Flutter UI.

What it does:
- EPUB-first import for discovered source files
- TXT/HTML fallback for selectively chosen non-EPUB sources
- stable work identity and checksum-based unchanged detection
- shared SQLite storage in `eLibrary.db` for imported works and paragraphs
- source status / inventory reporting for acquisition workflows
- source verification and site-specific rules are respected; Cloudflare or
  other verification steps are not bypassed

What it is not:
- it is not wired into the Flutter app UI
- it is not the legacy God's Promises workbook importer
- it is a tooling/prototype area for acquisition and normalization
- it is not a public distribution workflow

Key scripts:
- `elibrary_import.py` - main acquisition CLI
- `database.py` - local SQLite schema/helper used by the prototype
- `elibrary_db_writer.py` - writes normalized bundles into SQLite

Typical usage:

```bash
python3 tool/elibrary_acquisition/elibrary_import.py . --db /private/tmp/elibrary_test.db --report /private/tmp/elibrary_report.txt
python3 tool/elibrary_acquisition/elibrary_import.py . --db /private/tmp/elibrary_test.db --summary
python3 tool/elibrary_acquisition/elibrary_import.py . --db /private/tmp/elibrary_test.db --status
python3 tool/elibrary_acquisition/elibrary_import.py . --db /private/tmp/elibrary_test.db --status --verbose
```

Use only where you are allowed to access the source site and import the
material. Follow source-site terms, rate limits, and verification requirements.
