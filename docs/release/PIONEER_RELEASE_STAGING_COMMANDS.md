# Pioneer release checkpoint staging

Run from `/Users/deanbowen/Development/StudyBible2` only after reviewing the
final stabilization report.

```sh
git diff --check
git add --pathspec-from-file=docs/release/PIONEER_RELEASE_STAGING_MANIFEST.txt
git diff --cached --check
git status --short
git diff --cached --stat
```

Do not use `git add .` or `git add -A`.

## Intentionally excluded

- `assets/databases/Databases/`, `assets/databases/Graphics/`,
  `assets/databases/download_reports/`, and every `eLibrary.db`, `user.db`,
  WAL, or SHM file
- `CloudFiles/`, Pioneer source EPUBs, local scans, backups, recovery data,
  generated reports, screenshots, build outputs, and temporary logs
- `.claude/`
- `lib/features/library/dev/`
- `test/features/library/dev/`
- `test/features/library/data/real_ssp_canonical_proof_test.dart`
- `test/features/library/data/ssp_heading_classification_test.dart`
- `test/fixtures/`
- `test/tool/epub_canonical_overnight_batch_test.dart`
- `test/tool/pioneer_epub_folder_inventory_report_test.dart`
- `test/tool/pioneer_epub_production_import_test.dart`
- `tool/audits/`
- `tool/canonical_ssp_runtime_proof.dart`
- `tool/elibrary_profile_probe.dart`

The production Pioneer import harness remains classification C: local-only
and untracked. The real-book fixture/proof files remain local-only as required.
