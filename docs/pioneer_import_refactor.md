# Pioneer Import Refactor Ledger

Status: active architecture cleanup, started 2026-09-01.

This is the durable handoff record for Codex, Claude Code, and human review.
Update it at the end of every refactor step. It is linked from root
`CLAUDE.md`.

## Objective

Replace overlapping Pioneer ingestion and repair paths with a small,
provenance-first pipeline. Prevent invalid or legacy sources from becoming
active records rather than hiding their symptoms in the reader.

## Established facts

- A configured v2 root and old legacy Documents root coexisted. The app
  silently resolved missing v2 files from the legacy root.
- The raw-Pioneer folder importer previously recursed below the selected
  folder, admitting backup/staging descendants as input candidates.
- The canonical external source is `CloudFiles/ePubs/Pioneers` with 423
  direct EPUBs. A duplicate temporary ZIP extraction was retired to Trash.
- The v2 root has 51 Pioneer EPUBs; the legacy root has 473. There are 469
  active Pioneer records that exist only in the legacy root.
- The approved cleanup direction is reversible archival of legacy-only
  records, followed only by deliberate, hash-recorded re-import of verified
  editions.

## Current safeguards

| Boundary | Current state | Evidence |
| --- | --- | --- |
| Selected root | Strict provenance boundary; no legacy-file fallback | `LibraryRootService.resolveExistingAssetFile` |
| Raw EPUB discovery | Direct files only; descendant folders excluded | `PioneerEpubFolderInventoryService.survey` |
| Source fidelity | No `ARGUMET → ARGUMENT` rewrite | `LibraryDocumentCanonicalizer` tests |
| Existing data | Nothing deleted | Legacy-only records await explicit archival |

## Entanglement inventory

| File | Lines | Responsibilities currently mixed | Priority |
| --- | ---: | --- | --- |
| `lib/features/utilities/data/pioneer_text_import_service.dart` | 6,502 | EPUB/text/HTML/clipboard import; download; parsing; DB writes; canonicalization; repairs; duplicate cleanup; reset/delete | P0 |
| `lib/features/utilities/data/pioneer_captured_html_import_folder_service.dart` | 2,816 | scan/copy/import/repair/catalog matching/archive | P1 |
| `lib/features/library/data/library_catalog_service.dart` | 3,278 | catalog reads plus metadata/path/ID repair writes | P1 |
| `lib/features/utilities/presentation/elibrary_setup_screen.dart` | 3,762 | UI plus root/setup/import/migration orchestration | P2 |
| `lib/core/bootstrap/library_root_service.dart` | 724 | selection/authorization/legacy detection/paths/backups | P1 |

The newer `pioneer_epub_bulk_import_service.dart` is only 217 lines and is
comparatively focused. Do not fold it back into the older service.

## Target ownership model

| Component | Sole responsibility | Must not do |
| --- | --- | --- |
| LibraryRootPolicy | Select/authorize one root and resolve within it | Search/fall back to another root |
| PioneerSourceInventory | Enumerate direct eligible files; record hash/path | Copy, write DB rows, repair metadata |
| PioneerImportValidator | Validate archive/container/content | Guess editions or change text |
| ManagedEpubStore | Atomically copy validated bytes | Scan external folders |
| LibraryRegistration | Write full provenance record | Canonicalize or dedupe by title |
| CanonicalActivation | Produce reader content from managed copy | Modify author text/source metadata |
| LegacyArchiveMigration | Reversibly archive selected old records | Run during normal import/read |
| UI | Collect explicit choice and show outcomes | Define source policy/mutate records |

## Refactor phases

### Phase 0 — freeze and map (current)

- [x] Identify strict root and non-recursive discovery as causes.
- [x] Record file-size/ownership audit.
- [x] Establish this durable handoff ledger.
- [x] Map every write to `library_items`, text blocks, navigation, and
  canonical document rows.
- [x] Record every reader/catalog path that mutates data during a read.

### Phase 1 — isolate pure parsing (no behavior change)

- [ ] Move EPUB package inspection/parsing helpers out of
  `PioneerTextImportService` into a parser-only library.
- [ ] Add golden tests for byte-for-byte text/heading preservation and
  deterministic navigation output.

### Phase 2 — centralize normal import

- [ ] Route local/raw EPUB entry points through Inventory → Validator →
  Managed Store → Registration → Canonical Activation.
- [ ] Make source provenance required for every new registration.

### Phase 3 — separate maintenance

- [ ] Move duplicate detection, repair heuristics, resets, and deletion into
  explicit maintenance services/screens.
- [ ] Make catalog/reader reads side-effect free.
- [ ] Implement reviewed, reversible archival for the 469 legacy-only records.

### Phase 4 — retire obsolete paths

- [ ] Remove legacy fallbacks only after migration/report verification.
- [ ] Delete code only after tests and a live-data report show no active use.

## Safety rules

1. One refactor slice per change; never mix source cleanup, reader behavior,
   UI redesign, and migration.
2. Do not overwrite/delete user or library data during refactoring.
3. Do not use title-only matching as identity.
4. Preserve uncommitted changes unless directly part of the reviewed slice.
5. Add a regression test with each defect.
6. Record decisions, files, tests, and remaining risks here.

## Progress log

### 2026-09-01 — read-only write-path and read-side-effect audit

- **What changed:** completed the requested read-only map; no production,
  library-data, source-file, or Drive mutation was performed.  Verified the
  shared Drive folder named `Pioneers` (folder
  `1tqpn_w4UaootNgtTIJ22PekcknzAN8Yp`) by listing its *direct* children only.
  It contains direct `.epub` files plus `manifest.json` and a ZIP; therefore
  the source policy must explicitly select direct eligible EPUBs rather than
  treat every child (or any descendant) as an import candidate.
- **Why:** the currently selected v2 root and direct-source boundary are only
  useful if all later paths preserve provenance and if reading a catalog does
  not silently repair/migrate it.

#### Write-path map (current code)

| Target | Entry point / writer | Operation and reference | Risk |
| --- | --- | --- | --- |
| `library_items` | `PioneerTextImportService.importSelectedWorks` → `_writeImportedWork` | upsert at `pioneer_text_import_service.dart:3216-3427`, helper `:4188-4219`; normal download/text flow also writes flattened text/nav | Normal import is coupled to legacy flattened storage and identity reconciliation. |
| `library_items` | local EPUB import | `importLocalEpubFile` (`:1451-1510`) delegates to `_writeImportedWork`; best-effort `_persistEpubSourceAndCanonicalize` updates source path/type at `:1387-1441` | A successful flattened import can precede managed-copy/canonical activation. |
| `library_items` | captured text/clipboard/saved export/copied range | `importFromCapturedText` `:1531-1699`, clipboard `:1702-1743`, saved export `:1883-1925`, copied range `:1927-1979`; `_writeCopiedRangeImportedWork` `:2633-3164` | These “import” routes may replace rows and trigger sibling cleanup. |
| `library_items`, nav, text | captured HTML folder import and in-place repair | `importHtmlCaptureFolders` `:1981-2352`; `_repairBrokenCapturedHtmlItemInPlace` `:2500-2588` updates metadata; text/nav replacement in `_writeCopiedRangeImportedWork` `:3059-3108` | `allowRepair` is reachable within import, not an explicit maintenance boundary. |
| `library_items`, nav, text | duplicate/legacy retirement | `_deleteCanonicalCapturedImportRows` `:3597-3614`, `_retireLegacySameTitleEpubRows` `:3617-3636`, `_softDeleteMatchingCapturedHtmlDuplicateItems` `:3854-3908` | Title-based retirement of `pioneer_epub_import` rows can run as a side effect of a captured-HTML import. |
| `library_items`, nav, text | deletion/reset | `hardResetWork` `:4019-4035`; `removeImportedLibraryItem` `:4040-4088`; destructive helper `_deleteImportedWorkRows` `:3650-3684`, markup-preserving variant `:3686-3715` | Hard deletes and reset logic reside beside normal import APIs. |
| canonical sections/blocks/source-map/conversion | `LibraryDocumentCanonicalizer.canonicalize` | stage `library_document_sections_staging`/`blocks_staging` at `library_document_canonicalizer.dart:137-252`; atomically delete/replace active sections/blocks at `:305-348`; structural-rejection cleanup at `:413-466` | Canonical activation is an intentional replacement writer; source validation failure can delete a previously untrustworthy generation and mark the item `needs_attention`. |
| `library_items`, canonical tables | `CanonicalActivation.activate` callers | `PioneerTextImportService._persistEpubSourceAndCanonicalize` `:1387-1441`; `LibraryAcquisitionOrchestrator.prepareExistingEpub` `library_acquisition_orchestrator.dart:196-205`; archive installer `pioneer_archive_org_install_service.dart:401-423` | Multiple acquisition routes activate canonical content, but text/nav ownership is split elsewhere. |
| `library_items` | direct EPUB registration | `pioneer_epub_bulk_import_service.dart:127-214`; `pioneer_archive_org_install_service.dart:332-431`; legacy folder indexer `_indexFile` in `commentary_research_library_service_epub_indexing.dart:80-295` | Three registration implementations preserve different identities/provenance fields. |
| navigation rows and text blocks | legacy EPUB indexer | `_storeNavigationMetadata` `commentary_research_library_service_epub_indexing.dart:660-870` deletes/rebuilds nav; `_storeLibraryTextBlocks` `:599-655` deletes/rebuilds text. `ensureNavigationIndexed` at `commentary_research_library_service.dart:565-620` invokes both post-acquisition. | A second parser builds reader-adjacent tables independently from canonical blocks. |
| `library_items` and related tables | catalog duplicate repair / migration | `elibrary_catalog_duplicate_repair_service.dart:157-278` (including listed canonical/nav/text tables `:307-316`); `elibrary_migration_service.dart:673-725` | Correctly maintenance-shaped, but must remain explicitly invoked—not called by import/catalog reads. |

Other in-scope maintenance writers found: storage removal updates
`library_items` in `epub_storage_policy_service.dart:156-181`; root/database
migration moves/deletes files and remaps item IDs in
`elibrary_root_migration_service.dart:207-309` and
`elibrary_migration_service.dart:611-725`.  These are not normal Pioneer
import and must remain user-confirmed maintenance operations.

#### Read/catalog/reader paths with write side effects

`LibraryCatalogService.loadItems` calls `_hydrateCatalogRows`
(`library_catalog_service.dart:43-226`).  That read can:

- write author/title metadata: `_ensureEpubAuthor` `:1436-1508` and
  `_ensureEpubTitle` `:1511-1567`;
- cache/repair cover paths: `_warmMissingCoverPaths` `:1104-1155`,
  `_warmMissingCaptureCoverPaths` `:1157-1218`, and `_ensureEpubCoverPath`
  `:1856-1939`;
- repair managed path, source metadata, and even identity: `_repairMissingManagedPaths`
  `:1671-1794`, `_repairManagedItemIds` `:1796-1851` (which calls
  `migrateManagedLibraryItemId`).

`CommentaryResearchLibraryService.ensureNavigationIndexed`
(`commentary_research_library_service.dart:565-620`) is explicitly a writer
despite its reader-service home; it rebuilds nav/text tables on acquisition.
`loadNavigationItems` itself is read-only (`:622-650`).
`LibraryDocumentRepository` reader queries are read-only except the explicit
`updateCatalogMetadata` command (`library_document_repository.dart:57-79`).

#### Smallest safe extraction proposal — do not implement yet

Extract only the already top-level, DB-free EPUB inspection/parse seam from
`pioneer_text_import_service.dart`: `PioneerEpubInspectionReport`,
`inspectPioneerEpubBytes` (`:126-365`), the `PioneerEpubParserProfile`
classification/filtering helpers (`:571-783`), and the byte-to-document
parser used by the injected `PioneerImportDocumentParser`.  Place it in a
new `pioneer_epub_inspection_parser.dart` with no `sqflite`, root-service,
filesystem write, network, catalog, canonicalizer, or import-service
dependency.  Leave existing public symbols as forwarding exports/wrappers in
this first slice if call sites require it.

Focused tests should lock: invalid ZIP/container reporting; spine-order
selection; directly authored heading and paragraph strings are preserved
verbatim (including misspellings/case/whitespace after the existing parser's
defined extraction); deterministic section/nav order; and no parser API can
write to a database.  Existing `pioneer_text_import_service_test.dart` and
`pioneer_epub_folder_inventory_service_test.dart` are the nearest homes; add
a new parser-only test file rather than moving broad integration coverage.

- **Tests run/result:** static source audit with `rg`/line inspection only;
  no test suite run because no production behavior changed.
- **Remaining risks:** normal imports still call duplicate retirement and
  repair paths; catalog reads still persist metadata/path/identity repairs;
  canonical, flattened text, and navigation retain separate parse/write
  ownership; the direct Drive inventory should be counted/validated by the
  app's explicit inventory service, not inferred from a Drive listing.
- **Exact next safe step:** obtain approval for the parser-only file/test
  extraction.  Do not migrate, archive, delete, dedupe, or alter any existing
  import route before that approval.

### 2026-09-01 — pure EPUB archive inspection extraction

- **What changed:** added
  `lib/features/utilities/data/pioneer_epub_inspection_parser.dart` and
  `test/features/utilities/data/pioneer_epub_inspection_parser_test.dart`.
  `inspectPioneerEpubBytes` in `pioneer_text_import_service.dart:167-302`
  now delegates only ZIP/container/OPF manifest/spine discovery to the new
  helper; profile-based HTML parsing, quality validation, managed copy,
  registration, canonical activation, and all database writes remain where
  they were. No import route or maintenance route was redesigned.
- **Why:** it creates a testable provenance-preserving seam for archive
  inspection without moving DB behavior or altering authored headings/text.
  The helper has no `sqflite`, filesystem, network, root-service, catalog, or
  import-service dependency; it reports entry bytes and authored spine order
  without normalizing content. It also rejects arbitrary non-ZIP bytes that
  `ZipDecoder` otherwise describes as an empty archive.
- **Tests run/result:**
  `flutter test test/features/utilities/data/pioneer_epub_inspection_parser_test.dart test/features/utilities/data/pioneer_text_import_service_test.dart`
  — passed (33 tests). The new tests cover malformed bytes, authored spine
  order, and byte-for-byte preservation of an authored misspelling
  (`ARGUMET`). `flutter analyze` on the three changed Dart files — passed
  after formatting/lint cleanup.
- **Remaining risks:** this is inspection-only; parsed HTML/heading extraction
  still resides in the large service. Normal imports still contain repair and
  retirement behavior, and catalog loads still mutate data as recorded above.
- **Exact next safe step:** review this narrow extraction. Before extracting
  HTML-to-document parsing, first define a parser input/output contract that
  preserves source text and keeps validation, registration, activation, and
  every maintenance operation outside the parser.

### 2026-09-01 — pure NCX navigation-target extraction

- **What changed:** extended
  `lib/features/utilities/data/pioneer_epub_inspection_parser.dart` with
  `PioneerEpubNavigationParser`. The parser converts an already-loaded EPUB
  archive's authored NCX into ordered `(title, path, anchor, depth)` targets.
  `pioneer_text_import_service.dart` now consumes those targets in its
  existing `_parseNcxAnchoredEpubSections` flow; section/paragraph extraction,
  quality checks, source-profile selection, registration, activation, and all
  writes remain in the service. The parser module has no database,
  filesystem, network, catalog, or import-route dependency.
- **Preservation:** NCX labels are read in authored order, nested depth is
  retained, and entity decoding is limited to the existing display-text
  extraction behavior. No spelling correction, source normalization, repair,
  duplicate cleanup, reset, deletion, migration, or route behavior changed.
- **Tests run/result:**
  `flutter test test/features/utilities/data/pioneer_epub_inspection_parser_test.dart test/features/utilities/data/pioneer_text_import_service_test.dart`
  — passed (34 tests). The parser-only tests cover malformed bytes, authored
  spine order/raw bytes, and nested NCX navigation containing the authored
  unusual heading `CHAPTER I: ARGUMET`. `flutter analyze` on the parser,
  service, and parser test — passed with no issues.
- **Remaining risks:** paragraph and heading block extraction remains in the
  service, and its existing filtering behavior is still entangled with source
  profiles. The wider working tree includes unrelated import/maintenance edits
  that were not changed or exercised beyond the focused service test.
- **Exact next safe step:** extract a parser-owned, explicit input/output
  model for one already-loaded XHTML fragment to deterministic heading and
  paragraph blocks, while continuing to pass source-profile decisions from
  the service and leaving all filtering/validation policy under review.

### 2026-09-01 — pure XHTML body/text helper extraction and map completion

- **What changed:** added `PioneerEpubHtmlBodyParser` to
  `lib/features/utilities/data/pioneer_epub_inspection_parser.dart` and made
  the service's existing `_extractHtmlBody` and `_stripHtml` delegates. It
  extracts only an already-loaded `<body>` and the service's established
  plain-text representation. It has no database, filesystem, network,
  catalog, import-route, profile-selection, repair, cleanup, or write
  dependency.
- **Preservation/tests:** the parser test now asserts verbatim retention of
  `ARGUMET: “Odd”—punctuation!` and its source punctuation/entity text, in
  addition to the existing spine-order and nested NCX/anchor coverage.
  `flutter test test/features/utilities/data/pioneer_epub_inspection_parser_test.dart test/features/utilities/data/pioneer_text_import_service_test.dart`
  passed (35 tests); `flutter analyze` for the parser, service, and parser
  test passed with no issues.
- **Read-only mutation map completion:** the full source sweep confirms the
  only direct writers of the requested tables are: Pioneer service (`library_items`,
  `library_navigation_items`, `library_text_blocks`); bulk and archive.org
  Pioneer registrars (`library_items`); legacy EPUB indexing
  (`library_items`, navigation, text blocks); user EPUB import
  (`library_items`); canonicalizer staging/promote (`library_document_sections_*`
  and `library_document_blocks_*`); and explicit migration/repair services.
  `LibraryCatalogService.loadItems` and
  `CommentaryResearchLibraryService.ensureNavigationIndexed` remain the
  documented read/reader-adjacent write paths. No writer behavior was changed.
- **Checkpoint / next safe seam:** do not extract `_parseHtmlSections` as-is.
  It selects and applies `PioneerPublicDomainExtractionProfile` and
  `_shouldSkipBoilerplateSection`, which are filtering/repair policy rather
  than pure parsing. Review must first approve a parser contract that returns
  unfiltered authored XHTML blocks/sections and keeps that policy in the
  service; otherwise the move risks changing which sections are imported.

### 2026-09-01 — architecture baseline

- Audited the Pioneer import surface read-only.
- Confirmed `PioneerTextImportService` is the dominant entanglement point:
  local EPUB, download, captured HTML, clipboard, saved export, copied-range,
  repair, and removal logic coexist there.
- Confirmed the raw EPUB bulk importer is a small separate path and should be
  retained as a focused model rather than merged into the legacy service.
- Created this ledger. No production import code was changed in this refactor
  phase; active Codex edits remain unmodified.

### 2026-09-01 — `_parseHtmlSections` characterization checkpoint

- **What changed:** expanded the existing captured-XHTML regression in
  `test/features/utilities/data/pioneer_text_import_service_test.dart`; no
  production parser, writer, or route changed.
- **Ordering:** assertions use `library_text_blocks.spine_index ASC,
  paragraph_index ASC`, not `id`. The Pioneer writer sets `spine_index` from
  the parsed section and `paragraph_index` from the paragraph's position in
  that section, so these are the explicit source-sequence fields for this
  import path; `id` is incidental SQLite insertion state.
- **Observed fixture behavior:** the Story of the Seer of Patmos XHTML keeps
  the title-page paragraphs, `FOREWORD`, and `CHAPTER I` in authored order;
  its unusual authored punctuation `"best gift."` remains in retained body
  text. The existing generic path marks early title/foreword sections as
  front matter but does not skip them. The policy paths that do skip sections
  are: generic exact labels (`Contents`, `TOC`, `Cover`, `Copyright`, etc.),
  `nav.xhtml`/`toc.xhtml`, Project Gutenberg markers; and the Pioneer public
  domain profile's title/text-based publisher/contact/ISBN/address rules.
- **Classification:** XHTML body/block/section ordering is structural
  parsing. Every label-, href-, and text-content-based skip is policy. The
  public-domain checks are source-specific and title/content based, so they
  can hide genuine historical front matter or body content and must remain
  characterized rather than silently carried into a pure parser.
- **Verification:** focused characterization test passed; static analysis of
  the test and service passed with no issues.
- **Next safe checkpoint:** retain current behavior and wire nothing. The
  smallest reviewed change is `unfiltered parser output → explicit filtering
  policy → existing writer`, with separate fixtures for every current skip
  rule before replacing `_parseHtmlSections`.

### 2026-09-01 — unfiltered-section parser wiring

- **What changed:** `_parseHtmlSections` now maps its existing classified
  XHTML blocks into `PioneerEpubSectionParser` unfiltered sections, then
  applies the unchanged existing public-domain/generic skip predicates before
  constructing `PioneerImportSection` rows. Retained href and spine numbering
  are recomputed after filtering exactly as before, so skipped sections do
  not consume a retained source anchor or spine position.
- **Equivalence evidence:** parser and full service tests passed (35 total),
  including the characterization fixture that asserts retained titles,
  paragraphs, punctuation, and `spine_index`/`paragraph_index` ordering.
  Static analysis passed for parser, service, and both test files.
- **Risk/next seam:** block classification (`_extractHtmlBlocks`) remains in
  the service and is profile-sensitive. Extract it only behind an explicit
  caller-supplied classification configuration; do not move or alter skip
  predicates, source-profile selection, or writer behavior.

### 2026-09-01 — filtering normalization extraction

- **What changed:** added dependency-free `PioneerEpubFilteringNormalization`
  beside the parser components. The service delegates its existing whitespace
  collapse and comparison-key normalization exactly; stored authored text and
  fallback paragraph handling remain unchanged.
- **Contract/evidence:** collapse maps all whitespace runs to one space and
  trims; comparison keys lowercase and replace non-ASCII-alphanumeric runs
  with spaces. Parser tests lock line breaks, empty text, punctuation/entities,
  and `ARGUMET`; focused parser/service tests passed (36 total) and analysis
  passed.
- **Risk/next seam:** this comparison normalization is also used outside the
  public-domain policy, so only delegation—not broader ownership movement—was
  performed. The next safe extraction is the policy component itself, using
  these helpers without changing fallback or renumbering behavior.

## Next safe action

Await approval for the narrowly scoped parser/inspection helper and its
focused tests. Do not change behavior in existing import routes and do not
migrate, archive, dedupe, reset, delete, or alter library data.

### 2026-09-01 — SL27 provenance diagnostic (read-only)

- **What changed:** no production source, test, or library data was changed.
  Queried the active v2 eLibrary database directly and found two distinct
  SL27 records, which must not be conflated by title: the canonical Pioneer
  EPUB row `library_item_pioneer_epub_import_id_718cdf8d_8560_4c64_93e9_81d198a6eb36`
  and the captured/research row `library_item_research_pioneer_at_jones_sl27`.
- **Findings:** the canonical Pioneer EPUB row completed
  `library_document_conversion` version 6 at `2026-08-20T22:44:21.247003Z`
  and has 7 canonical sections / 1,146 canonical blocks, but zero
  `library_navigation_items` and zero `library_text_blocks`. The research
  row has 13 navigation rows and 925 text blocks, each created at
  `2026-08-31T20:58:59Z`, alongside that row's creation/index timestamp, and
  has no canonical conversion or canonical sections/blocks. Therefore its
  navigation/text were produced by the legacy indexing path
  (`_storeNavigationMetadata` / `_storeLibraryTextBlocks`), not by
  `LibraryDocumentCanonicalizer`; canonicalization does not write those two
  legacy tables. These are different rows and different import/index runs,
  separated by 11 days.
- **Tests run/result:** baseline `flutter test` completed with four existing
  failures and one skip (no new failure introduced by this diagnostic);
  `flutter analyze` completed with 43 pre-existing info/warning diagnostics.
- **Remaining risks:** title-based inspection alone would incorrectly merge
  these two SL27 records. No repair, migration, deduplication, archival, or
  data mutation was performed.
- **Exact next safe step:** await user review before any Option B or C work.

### 2026-09-01 — exact stopping point before cohesive policy extraction

- **Completed immediately before stop:** the service now delegates the pure
  whitespace/comparison normalization operations to
  `PioneerEpubFilteringNormalization`; `PioneerEpubSectionParser` is wired
  before the unchanged filtering calls. Focused parser/service tests passed
  (36 total) and static analysis was clean at that point.
- **Current caller map:** the shared front-matter predicate is used by
  `_parseHtmlSections` for retention/fallback handling and by
  `_validatePioneerEpubImportQuality` for meaningful-body and
  front-matter-first validation. Normalization is shared infrastructure.
- **Approved cohesive next task:** extract and wire, together,
  `PioneerEpubFrontMatterClassifier` (the single shared
  `isSectionFrontMatter(title, rawText)` implementation),
  `PioneerEpubRetentionPolicy` (leading-paragraph/fallback and retention
  decisions), and `PioneerEpubQualityValidationPolicy` (meaningful-body and
  first-body predicates). They must be dependency-free, preserve post-filter
  numbering and every observable import result, and replace all current
  callers without duplicating predicates.
- **Do not cross:** no changes to profile selection, parser output, import
  routes, database/schema/writers, canonical activation, reader/catalog,
  migration, archival, deletion, source folders, Drive, or library data.
- **Required verification before completion:** isolated service fixtures plus
  direct policy tests must prove retained/skipped sections and paragraphs,
  fallback behavior, anchors/order, validation accept/reject outcomes, and
  authored punctuation/text equivalence; then run focused parser/service
  tests and static analysis. Stop only for a real behavior mismatch or a
  source/data-provenance risk.

### 2026-09-01 — cohesive policy extraction completed

- **What changed:** moved `PioneerEpubFrontMatterClassifier`,
  `PioneerEpubRetentionPolicy`, and `PioneerEpubQualityValidationPolicy`
  verbatim out of `pioneer_text_import_service.dart` (previously lines
  534-730) into `pioneer_epub_inspection_parser.dart`, right after
  `PioneerEpubFilteringNormalization`. Their two internal calls to the
  service-local `_normalizeText`/`normalizeWhitespace` wrappers were rewritten
  to call `PioneerEpubFilteringNormalization.comparisonKey`/
  `.collapseWhitespace` directly, which is exactly what those wrappers already
  delegated to — no logic changed. All existing call sites
  (`_validatePioneerEpubImportQuality` and `_parseHtmlSections` in the
  service) needed no edits: the classes kept their names and the service
  already imported `pioneer_epub_inspection_parser.dart`.
- **Why:** this was the ledger's approved next task. The three classes had
  no database, filesystem, network, catalog, or import-route dependency even
  while still living in the service file; moving them completes the
  dependency-free parser/policy module without touching profile selection,
  parser output, import routes, writers, canonical activation,
  reader/catalog, migration, archival, deletion, or library data.
- **Verification:** confirmed via `grep` that no other file in `lib/` or
  `test/` referenced these three classes directly (only the two call sites
  above, both inside the service, which were left as-is).
  `flutter test test/features/utilities/data/pioneer_epub_inspection_parser_test.dart test/features/utilities/data/pioneer_text_import_service_test.dart`
  passed (37 tests, unchanged count from before this move).
  `flutter analyze` on both changed files plus the parser test file — no
  issues. `dart format` on both changed files — no changes needed.
- **Remaining risks:** `PioneerEpubFrontMatterClassifier.isBodyStartTitle` and
  its `_bodyStartTitles` set moved along with the rest of the class but have
  no caller anywhere in `lib/` or `test/` (confirmed by grep) — this was true
  before the move as well and is not a regression introduced here; it is left
  untouched pending explicit review rather than removed as "unused" during a
  refactor slice. Block classification (`_extractHtmlBlocks`) and profile
  selection remain in the service.
- **Exact next safe step:** review this extraction. The parser/policy module
  is now fully separated from the service for front-matter, retention, and
  quality-validation policy. The next candidate seam per the ledger is
  `_extractHtmlBlocks` classification, but per the "Do not cross" rule above
  it must be extracted behind an explicit caller-supplied classification
  configuration, not moved verbatim, since it is profile-sensitive.

### 2026-09-03 — SL27 content-accuracy verification (read-only)

- **What changed:** no production source, test, or library data was changed.
  This follows up on the 2026-09-01 SL27 provenance diagnostic above by
  checking whether the two SL27 records' actual stored content is accurate,
  using the real source book as ground truth — pulled directly from
  archive.org (`adventist-pioneer-authors-alonzo-trevier-jones`, file
  `NSLS27 - The National Sunday Law [SL27]_djvu.txt`, 8,736 lines, confirmed
  to carry the same `SL27 <page>.<para>` reference-code convention already
  used in this app's data, which made line-level comparison possible) against
  the live `eLibrary.db`
  (`~/Library/Containers/com.deanbowen.bibleAppMac/Data/Documents/BiblicalHeritage/v2/eLibrary.db`,
  confirmed live by matching the research row's exact `created_at` timestamp
  from the 09-01 diagnostic).
- **Correction to the 2026-09-01 diagnostic: the canonical row is already
  soft-deleted, and was before that diagnostic ran.**
  `library_item_pioneer_epub_import_id_718cdf8d_8560_4c64_93e9_81d198a6eb36`
  has `deleted_at = 2026-08-30T15:55:16Z` — one day before the SL27
  diagnostic queried it, and the diagnostic entry above does not mention
  this. Per the app's own established pattern (see the "Daniel and The
  Revelation mystery, resolved" note in `BUGS.md`), a `deleted_at`-set row is
  excluded from every list/open query. **The two-record conflict described
  on 2026-09-01 is not currently reachable by a user** — only
  `library_item_research_pioneer_at_jones_sl27` is live, and it alone is
  "the record currently backing what the reader displays." A broader title
  search (`title LIKE '%National Sunday Law%'`) also surfaced two *other*,
  unrelated `pioneer_epub_import` rows for different archive.org editions of
  the same book (`[RLL]`, still live; `[SL18]`, also soft-deleted, at
  `2026-08-31T20:59:56Z`) — noted only to record they exist and are not part
  of this SL27 investigation; each is its own separate scan/edition with its
  own id.
- **Likely cause of the SL27 canonical row's deletion, found while checking
  bug (b) below:** `_retireLegacySameTitleEpubRows`
  (`pioneer_text_import_service.dart:3390-3409`) soft-deletes any
  `library_items` row with `source_type = 'pioneer_epub_import'` whose title
  matches (case-insensitive, exact string) the work being captured-HTML
  imported. The retired row's title, `The National Sunday Law [SL27]`,
  matches this exactly, and the retirement runs as an automatic side effect
  of `_deleteCanonicalCapturedImportRows`, called during captured-HTML
  import/repair. This is circumstantial (no separate audit log exists to
  confirm the triggering run) but consistent on every available fact: the
  helper exists, targets exactly this title, and the row was retired without
  any corresponding entry in `BUGS.md` or this ledger describing a deliberate
  migration. See the new `BUGS.md` entry below.
- **Nav accuracy (research row, 13 entries):** compared against the source's
  own table of contents (djvu lines 11-24) and body structure. All 13 labels
  match the real chapter/section divisions verbatim: INTRODUCTION, the
  argument's title page, ARGUMENT, "ARTICLE" (a reprinted newspaper piece),
  three REMARKS/REPLY exchange pairs correctly nested one level under
  "ARTICLE" (verified against the body text — these are literally responses
  to the reprinted article, not independent chapters), APPENDIX A, OPEN
  LETTER correctly nested one level under APPENDIX A (it is addressed content
  within that appendix), and APPENDIX B. No spurious or missing entries.
  This is accurate.
- **Text-block spot checks, three locations, both rows compared against the
  source djvu text:**
  1. **Introduction, paragraph 1** (djvu lines 30-38): word-for-word
     identical across the source, the research row, and the (retired)
     canonical row. No defect in either row here.
  2. **Mid-book, the "ARGUMENT" section opening** (djvu line ~294): the
     research row is clean — heading `ARGUMENT` (spelled correctly) directly
     followed by "Senator Blair.—You have a full hour, Professor...",
     matching the source exactly. **The canonical row has two real defects
     here**, both absent from the research row: (a) the section heading
     reads `ARGUMET` (missing the second "N") — this is the exact known OCR
     defect `library_document_canonicalizer_generation_test.dart` already has
     a named regression test for ("corrects the known SL27-style OCR heading
     defect..."), and running that test now shows it **currently fails**
     (`Expected: 'ARGUMENT', Actual: 'ARGUMET'`) — the correction is not
     presently working, at least not for whatever generated this row's
     content; (b) two paragraphs earlier, the sentence "...are now laying
     plans to have another national Sunday bill introduced..." is split
     across three separate paragraph blocks by stray page-number tokens
     (`iv`, then later `v`) that were parsed as their own paragraphs instead
     of being stripped — the source and research row have no such artifacts
     at this point.
  3. **A footnote on source page 122** (djvu line 5503, referencing repeal of
     an exemption clause): the canonical row keeps this footnote's text but
     **displaces it to the very end of the entire book** — it is the
     canonical row's absolute last block (`display_order` 1145 of 1145),
     completely detached from its real location. The research row does not
     have this displacement, but on searching all 925 of its blocks for this
     footnote's text, **it isn't present at all** — the research row appears
     to have dropped this footnote rather than misplacing it. This was
     checked for one footnote only; it is not a confirmed general pattern,
     but it means the research row is not proven complete either.
- **Verdict on "canonical-preferred-after-validation":** not supported by
  this sample. The canonical parse is not simply "the research row's content
  minus working navigation" — it has its own independent content defects
  (an uncorrected, currently-test-failing OCR heading typo; page-number
  artifacts splitting sentences; a footnote relocated to the wrong place)
  that the research row does not share at the same spots. The research row
  is cleaner everywhere checked except it appears to be missing at least one
  footnote the canonical row (imperfectly) retained. Neither row is a strict
  superset of the other on this sample.
- **Tests run/result:** `flutter test
  test/features/library/presentation/canonical_library_reader_epub_pilot_test.dart`
  in isolation: 3 pass, 2 fail (the two eligibility tests named in the new
  `BUGS.md` entry below). `flutter test
  test/features/library/data/library_document_canonicalizer_generation_test.dart`
  in isolation: 1 pass, 15 fail, including the named "ARGUMET" test above —
  this file's failure count is much larger than previously reported and was
  not otherwise investigated in this pass (out of scope; flagged for
  awareness only). `flutter test
  test/features/library/data/user_epub_import_service_test.dart` in
  isolation: the "SL27 preserves every Capture Clipper TOC destination..."
  test fails (`Expected: true, Actual: false`) against the hardcoded fixture
  path `/Users/deanbowen/Library/CloudStorage/OneDrive-Personal/CloudFiles/Books/SL27.epub`.
  **Important suite-health note:** a full, unfiltered `flutter test` run
  (1,008 pass / 1 skip / 5 fail) does **not** surface any of these
  per-file failures — it fails five different, unrelated tests instead
  (`entry_screen_set_up_my_library_test.dart`,
  `library_catalog_service_pioneer_test.dart`,
  `library_screen_capture_import_test.dart` ×2,
  `utilities_screen_set_up_my_library_test.dart`). Running each file above in
  isolation reproduces the failures named in the prior session's report
  exactly; running the full suite together does not. The suite's full-run
  result is not a reliable failure baseline right now — it appears to be
  order/parallelism-dependent — and neither the "four failures" figure in the
  2026-09-01 entry above nor a flat "five failures" from a full run should be
  treated as ground truth without saying which run mode produced it.
- **No repair, migration, deduplication, archival, or data mutation was
  performed.**
- **Exact next safe step:** the SL27 reconciliation proposal below, informed
  by these findings. Await your review before any Option B or C work, code
  fix, or data change.

### 2026-09-03 — SL27 reconciliation proposal (design only, not implemented)

- **Premise, corrected from 2026-09-01:** there is currently only one live,
  reachable SL27 record — `library_item_research_pioneer_at_jones_sl27`. The
  canonical `pioneer_epub_import` row is already soft-deleted and has been
  since 2026-08-30, most likely retired by the same title-matching helper
  flagged in the new `BUGS.md` entry below, not by any reviewed decision.
  This is not "two records competing for display today"; it is "one live
  record whose companion was silently retired by an unrelated bug, and whose
  content turns out to have real value the live record may be missing."
- **Do not simply restore or prefer the canonical row.** The content-accuracy
  pass above found it has its own defects at the exact spots checked
  (uncorrected `ARGUMET` heading — the fix for this exists in the
  canonicalizer's test suite but is not currently passing; page-number
  artifacts splitting paragraphs; a footnote relocated to the end of the
  book). Restoring it as the primary record today would trade the research
  row's known gap (a possibly-dropped footnote) for these three different,
  independently-verified defects, without evidence that navigation is the
  canonical row's only problem.
- **Do not blind-copy or merge the two rows' content.** They come from
  different source files entirely (research: a local EPUB at
  `.../OneDrive-Personal/CloudFiles/Books/SL27.epub`; canonical: the bulk
  `aplib`-sourced `ImportedPioneerEpubs/aplib_..._sl27_epub_....epub`) parsed
  by two independent pipelines. A naive merge could interleave two different
  paragraph segmentations of the same prose or duplicate content that only
  differs in incidental formatting.
- **Proposed order of operations (all still pending your review, none
  implemented):**
  1. **Land the `_retireLegacySameTitleEpubRows` safety fix first** (see
     `BUGS.md`) — a title-only match with no file/edition/fingerprint check
     already destructively retired live data once, unreviewed, and any
     reconciliation work here would be at risk of the same helper firing
     again mid-decision.
  2. **Audit the research row for completeness**, not just the canonical
     row for navigation — at minimum, check whether other footnotes besides
     the one found here are missing, since that changes whether the research
     row is actually a safe long-term sole source.
  3. **Only then** decide, explicitly and per-title (not by an automated
     title match), which single id becomes the durable one, and whether any
     specific missing content from the other row should be folded in
     manually — reviewed paragraph by paragraph for this title, not scripted
     across the whole Pioneer catalog.
  4. A **stable work-level alias** (something like a `source_work_id`
     linking both a title's `pioneer_epub_import` and `research`/captured-HTML
     rows without either one owning or overwriting the other) may still be
     the right long-term shape so future imports of the same title stop
     minting ambiguous duplicates in the first place — this is a design
     direction, not a proposed implementation; it needs review before any
     schema or migration work starts.
- **Exact next safe step:** await your decision on the order-of-operations
  above before any code change, data change, or migration.
