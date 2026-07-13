# eLibrary Setup & Import Simplification Plan

Status: draft 2026-07-08. Companion to `pioneer_acquisition_plan.md`.
Audit-only; no setup redesign implemented yet.

## Current inventory

### User-facing screens (reachable from Utilities)

| Screen | File | Role today | Verdict |
| --- | --- | --- | --- |
| Utilities hub | `lib/features/utilities/presentation/utilities_screen.dart` | 12-button flat list mixing setup, sharing, support | Keep, regroup |
| Library Root Setup | `library_root_setup_screen.dart` | Pick/repair library root, create folders, migrate legacy files | Keep → becomes Step 1 |
| eLibrary Setup | `elibrary_setup_screen.dart` (2,719 lines) | Does everything: root status, CaptureClipper package import, OneDrive import, CloudFiles folder, EGW collection checkboxes, EPUB/PDF format, install, remove, index report, legacy migration, debug pickers | Split — this is the confusion epicenter |
| eLibrary Downloads | `elibrary_download_screen.dart` | EGW bulk download progress/report (collections 4, 1227, 1371, 10, 8, 5, 1376 from egwwritings.org) | Merge into wizard Step 4; drop as standalone button |
| Pioneer Library Import | `pioneer_text_import_screen.dart` (1,991 lines) | Pioneer works catalog, clipboard/saved-export/EGW copied-range import, repair/reset, assets/scans import | Keep as the Pioneers pane of Step 3/4; hide repair/reset behind Advanced |
| Captured HTML Import Review | `pioneer_captured_html_import_review_screen.dart` | Review CaptureClipper folder imports needing attention | Keep, linked from status (Step 6) |

### Services (data layer)

- Acquisition: `elibrary_download_service.dart` (EGW), `pioneer_book_package_import_service.dart` (.studybook), `pioneer_captured_html_import_folder_service.dart` + `..._availability_service.dart` + `..._review_store.dart` (CaptureClipper folders), `pioneer_text_import_service.dart` (clipboard/export/copied-range + EPUB parsing), `egw_copied_range_parser.dart`.
- Storage/roots: `library_root_service.dart` (core), `elibrary_storage_policy.dart`, `elibrary_folder_policy.dart`, `utility_folder_setup_service.dart`, `elibrary_root_migration_service.dart`, `elibrary_migration_service.dart`, `elibrary_database_migration_service.dart`.
- Status/maintenance: `pioneer_install_status_service.dart`, `elibrary_file_management_service.dart` (remove downloads), `elibrary_local_install_size_service.dart`, `elibrary_install_estimate_repository.dart`, `elibrary_duplicate_cleanup_service.dart`, `study_bible_storage_index_report_service.dart`.
- **Legacy bad sources (retire from acquisition UI):** `pioneer_ellenwhite_audio_service.dart`, `pioneer_epub_collection_service.dart` (adventaudio/aplib refreshers), aplib/adventaudio/ellenwhiteaudio entries in `pioneer_source_catalog.dart` and `assets/elibrary_sources/pioneer_sources.json`. Keep the detection SQL in `pioneer_install_status_service.dart` so old bad imports stay identifiable (per acquisition plan Phase E).

## Problems observed

1. Three sibling entry points (Library Root Setup, eLibrary Downloads, eLibrary Setup) with overlapping responsibilities and no ordering; users don't know where to start.
2. `elibrary_setup_screen.dart` mixes first-run setup, per-collection acquisition, format choice, removal, debug pickers ("Test Broad Any File Picker"), and migration prompts on one scroll.
3. Bad legacy pioneer sources still surface as plausible acquisition paths.
4. No single "what is installed / indexed / needs attention" view; status is split across the setup screen report, Storage and Index Report, and the pioneer catalog.

## Proposed workflow: one "eLibrary Setup & Import" wizard

A single entry button on Utilities ("eLibrary Setup & Import"), six steps,
each a screen/pane the user can revisit; the wizard remembers completion
state and opens at the first incomplete step.

1. **Storage** — library root picker (reuse `LibraryRootSetupScreen` logic): app-managed default folder (one-tap), optional CloudFiles/OneDrive folder for supported providers, and the iPad `.studybook` package-import location. Legacy migration prompt lives only here.
2. **Collections** — checklist: EGW Books, EGW Devotionals/Commentaries/Misc, EGW Manuscripts, EGW Letters, Pioneers, User Imported. (Backed by existing collection definitions in `elibrary_download_service.dart` + pioneer catalog.)
3. **Acquisition method** — derived automatically per collection, shown not asked where possible: EGW Writings download for EGW collections; CaptureClipper `.studybook` package for Pioneers (primary, per acquisition plan); local EPUB/PDF import as fallback. EGW-EPUB-for-pioneers offered only after a verified HEAD check.
4. **Download / Import** — runs `ELibraryDownloadService` and/or the package/folder import with one combined progress report (reuse `elibrary_download_screen.dart` progress UI inline).
5. **Index / Refresh** — one "Index new files" action wrapping the existing catalog refresh; no separate refresh buttons per screen.
6. **Status** — installed/indexed/needs-attention table per collection (from `pioneer_install_status_service`, `elibrary_local_install_size_service`, index counts), with links to Review Imports and Remove Downloads (remove stays here, out of the setup path).

### Button/label recommendations

- Utilities hub groups: "Library" (eLibrary Setup & Import, Storage & Index Report), "Backup" (Backup, Restore), "Sharing & Community", "Tools" (Church AutoMute, Bible Explorer).
- Rename "Import CaptureClipper Book Package" → "Import Book Package (.studybook)".
- "Refresh Folders" / "Refresh" / estimate-cache refresh → single "Index new files".
- Advanced/hidden: debug pickers, "Reset DAR", Repair/Reimport, duplicate cleanup, legacy migration re-runs.

### Keep / hide / merge / retire

- **Keep:** library root setup, `.studybook` import, CaptureClipper folder import + review, EGW download service, pioneer catalog import, status services.
- **Merge:** eLibrary Downloads screen and the install/remove sections of eLibrary Setup into the wizard.
- **Hide (Advanced):** repair/reset tools, test pickers, migration re-runs, remove-downloads.
- **Retire from UI/catalog:** EllenWhiteAudio, AdventAudio, APLIB acquisition paths (Phase E of acquisition plan; needs explicit approval to delete code — until then simply never render them as sources). Keep bad-import detection heuristics.

## Smallest first implementation step

Add the wizard shell as a new `ELibrarySetupFlowScreen` with the six-step
scaffold where Steps 1, 4, 5 simply embed the existing Library Root Setup,
download progress, and index actions unchanged, and replace the three
Utilities buttons with the single entry point. No service changes, no
deletions — purely navigation regrouping. Each subsequent phase then moves
one section out of `elibrary_setup_screen.dart` into its proper step.
