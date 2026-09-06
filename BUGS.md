# StudyBible2 Bug List

This file tracks bugs and verification items found during manual application testing.

## Open Bugs

### 1. New hashtag categories are not retained/recognized immediately

**Area:** Hashtags / Categories

**Status:** Fixed on Android

**Android verification (2026-08-16):** Fixed on Android. Creating `Android New` while `#MyTest2` was still unsaved immediately selected the category. Saving the tag retained that assignment, and the category appeared in the category list with the tagged verse. Empty categories are now persisted independently of tag membership.

**Problem:**

When creating or editing a hashtag, the user can create a new category and assign the hashtag to it. However, the newly created category is not reliably retained or made available immediately.

Observed workflow:

1. Create a hashtag such as `#MyTest`.
2. Create a new category while editing/creating the hashtag.
3. Assign the hashtag to that new category.
4. Save/use the hashtag.
5. The hashtag may still show its previous category, and the newly created category does not appear in the category list/filter.

The category only appears reliably after a hashtag is later moved into or assigned to that category through another workflow.

**Expected behavior:**

* A newly created category should be persisted immediately.
* It should appear immediately in all relevant category selectors and filters.
* The hashtag should retain the newly selected category after save.
* A category should be valid even if it temporarily contains zero hashtags.

Do not require an existing hashtag membership before a category becomes recognized.

---

### 2. Remove nuisance success notification after hashtag category changes

**Area:** Hashtags / UI notifications

**Status:** Fixed on Android

**Android verification (2026-08-16):** Fixed on Android. Moving the test hashtag between categories completed without a success snackbar/ribbon. Failure notification paths remain intact in the implementation.

**Problem:**

After moving a hashtag to another category, a bottom snackbar/ribbon appears with a success message similar to:

`My Test moved to New Tags`

The notification remains visible and may require manual dismissal.

These routine success notifications are unnecessary and interfere with normal workflow.

**Expected behavior:**

* Do not show routine success snackbars/ribbons for successful hashtag category changes.
* Successful operations should normally complete silently.
* Preserve meaningful error/failure notifications.
* Do not remove warnings or notifications that require user action.

The desired general rule is: **silent on ordinary success, notify on failure or something requiring attention.**

---

### 6. TOC navigation not scrolling to selected chapter

**Area:** eLibrary / Table of Contents navigation

**Status:** Fixed in code. Verified via the automated test suite (975/976 tests
passing, including two new tests added for this fix) and by code review
confirming the fix is shared Dart logic with no platform-specific branching —
the same code path runs on iOS, Android, macOS, and Windows. Not re-confirmed
by direct visual click-through on macOS this pass (see 2026-08-25 pre-release
sweep note below).

**Platform:** macOS (confirmed broken); iOS confirmed working — likely macOS-specific.

**Problem:**

Opening the Contents (TOC) panel and tapping a chapter/section entry does nothing — no scroll/navigation occurs to that location in the reading view.

**Expected behavior:**

Tapping a TOC entry should scroll/jump the main content view to that chapter's position.

**Repro:**

On Mac: open any book → tap Contents → tap any chapter entry → nothing happens. On iOS, the same steps work correctly.

**Cause:**

Some EPUBs, including Early Writings, contain both section-level and nested TOC targets. Navigation previously tried to resolve a nested target before its new section had been mounted, which was especially reproducible when navigating backward to the opening chapters on macOS. Some imported TOC and text-block ordering values also use different numeric domains.

The EPUB also exposes metadata/help TOC rows whose source files are not part of
the reader's imported content. These dead rows are now omitted from Contents;
only entries with a readable section or readable descendant are displayed.

**To test:**

Verify several Early Writings entries near the beginning, middle, and end on macOS. Each should land on its matching rendered heading.

---

### 7. Canonical EPUB reader eligibility check accepts any EPUB with a relative path, not just managed-folder paths

**Area:** eLibrary / canonical reader routing (`lib/features/library/presentation/canonical_library_reader.dart`)

**Status:** Open. Found 2026-09-03 during the SL27 provenance follow-up (see `docs/pioneer_import_refactor.md`); not fixed — flagged only, per that investigation's read-only scope.

**Problem:**

`supportsCanonicalEpubReader` (`canonical_library_reader.dart:354-360`) only checks two things: that `fileFormat` is `'epub'` and that `relativePath` is non-empty:

```dart
bool supportsCanonicalEpubReader(LibraryCatalogItem item) {
  if ((item.fileFormat ?? '').trim().toLowerCase() != 'epub') return false;
  return item.relativePath.trim().isNotEmpty;
}
```

It does not check that the item actually lives inside a managed import folder (`ImportedPioneerEpubs`, `ePubs/EGW/EGW_Books`, etc.), and does not check `source_type` at all — contradicting its own doc comment ("Provenance must not choose a second rendering/navigation model").

**Confirmed live** by running `flutter test test/features/library/presentation/canonical_library_reader_epub_pilot_test.dart` in isolation: two existing tests fail against the current implementation —

* "an EPUB outside official managed storage is never routed through the canonical EPUB reader" (line ~199) — expects `supportsCanonicalEpubReader` to return `false` for a `user_import` EPUB at `Imports/user_uploaded.epub`; it returns `true`.
* "a pioneer_archive_org_download EPUB outside ImportedPioneerEpubs is still ineligible — the folder-path check still applies" (line ~238) — same shape, also fails.

Both report `Expected: false / Actual: true`.

**Risk:** any EPUB-format library item with a non-empty `relativePath` — including a plain user-imported EPUB from an arbitrary location — is currently eligible for the canonical reader, regardless of folder or source type. Not confirmed to have altered SL27's own content (SL27's canonical row lives inside the correct managed folder), but it's a real gap in the same reader-routing function the 2026-08-31 archive.org OCR-heading fix (above) modified, and the two tests that would have caught this appear to have been written for a folder-path check that was never implemented (or was implemented and later dropped).

**Do not fix without review** — the correct managed-folder check needs to be confirmed against every current `pioneer_*` and `official_download`/`user_import` relative-path convention before being reintroduced, to avoid narrowing eligibility for a cohort that's supposed to pass.

---

### 8. `_retireLegacySameTitleEpubRows` silently retires unrelated `pioneer_epub_import` rows by exact title match during captured-HTML import

**Area:** Pioneer import pipeline (`lib/features/utilities/data/pioneer_text_import_service.dart`)

**Status:** Fixed 2026-09-05. `_retireLegacySameTitleEpubRows` no longer matches on `LOWER(title)`; it now only retires a `pioneer_epub_import` row when it carries the incoming work's `source_work_id`, or when its stored `pioneer_source_fingerprint` (sha256 of the file bytes) equals the sha256 of the bytes just imported — i.e. only a provable same-identity or byte-identical row can be retired, never a same-titled but unrelated one. No other call site in the codebase used title-only matching for a retirement/overwrite decision.

**Problem:**

`_retireLegacySameTitleEpubRows` (`pioneer_text_import_service.dart:3390-3409`), called automatically from `_deleteCanonicalCapturedImportRows` (`:3370-3388`) as part of every captured-HTML import/repair run, soft-deletes any `library_items` row that matches on **title string alone**:

```dart
where:
    'id != ? AND deleted_at IS NULL AND LOWER(title) = LOWER(?) '
    "AND LOWER(COALESCE(source_type, '')) = 'pioneer_epub_import'",
whereArgs: <Object?>[keepItemId, work.title.trim()],
```

There is no check that the matched row is actually the same physical file, edition, or scan as the work being imported — a case-insensitive exact title match against any live `pioneer_epub_import` row is sufficient to retire it.

**This already happened to live data, most likely:** `library_item_pioneer_epub_import_id_718cdf8d_8560_4c64_93e9_81d198a6eb36` — the canonical Pioneer EPUB row for "The National Sunday Law [SL27]" analyzed in the 2026-09-01 SL27 provenance diagnostic — has `deleted_at = 2026-08-30T15:55:16Z` in the live database, a day before that diagnostic ran (and not mentioned in it). Its title matches this helper's target exactly. No corresponding entry exists anywhere in this file or `docs/pioneer_import_refactor.md` describing a deliberate, reviewed retirement of this row. This is circumstantial — there is no separate audit log to confirm the exact triggering import run — but every available fact is consistent with this helper being the cause. See `docs/pioneer_import_refactor.md`'s 2026-09-03 entries for the full comparison.

**Risk:** a captured-HTML import or repair run for one title can silently retire a same-titled `pioneer_epub_import` row with no confirmation the retired row was actually redundant, and no audit trail beyond the row's own `deleted_at` timestamp. The project already has multiple same-titled-but-different-edition rows in the catalog (three separate archive.org scans of "The National Sunday Law," tagged `[RLL]`/`[SL18]`/`[SL27]` — each a distinct title string in practice, so not cross-matched by this helper, but the pattern of "same book, multiple legitimate source editions" is real and not accounted for here).

**Do not fix without review** — before changing this helper's matching logic, its intended legitimate use case (retiring a genuinely-superseded old import of the *same* file) needs to be understood so the fix doesn't block real cleanup while closing the false-match risk.

---

### 9. `elibrary_catalog_duplicate_repair_service.dart`'s `_equivalent` falls back to title/author/file-name matching when `source_work_id`/`source_package_id` are both empty

**Area:** Startup-time catalog repair (`lib/features/utilities/data/elibrary_catalog_duplicate_repair_service.dart:320-350`)

**Status:** Open. Logged 2026-09-05 alongside the entry 8 fix, same false-match shape (two rows treated as the same work by title/author/file-name alone when neither has a `source_work_id`/`source_package_id`), but this is a separate, startup-time repair path — not touched as part of that fix. Not fixed, flagged only.

**Problem:** `_equivalent()` prefers matching two `library_items` rows by `source_work_id`, then `source_package_id`, but when both are empty on both sides it falls through to requiring only a matching normalized `file_name` plus non-conflicting normalized `title`/`author` — the same class of coincidental-match risk as entry 8, just in the startup repair path instead of the captured-HTML import path.

**Do not fix without review**, per the same reasoning as entry 8 — understand this service's actual repair intent first so a fix doesn't block legitimate dedup while closing the false-match risk.

---

### 10. `PioneerTextImportService`'s non-EPUB-bulk import paths never assigned a cover for a brand-new row

**Area:** Pioneer import pipeline (`lib/features/utilities/data/pioneer_text_import_service.dart`)

**Status:** Fixed 2026-09-05, verified against real production data.

**Problem:** `PioneerCoverAssignmentService.ensureCoverPath()` (embedded-EPUB-cover extraction, falling back to a generated placeholder) was already wired into `pioneer_epub_bulk_import_service.dart:190` and `pioneer_archive_org_install_service.dart:408`, but never called from any of `PioneerTextImportService`'s own writers (`importLocalEpubFile`, HTML-capture import, copied-range import). Those paths only ever resolved a cover via `cachePioneerCaptureCoverPath()`, which merely *caches* a cover path the caller already knows about (e.g. from catalog/capture metadata) — it does not extract an embedded EPUB cover or generate a placeholder. A brand-new row imported through any of these paths with no already-known cover path silently ended up with `cover_path = NULL` forever.

**Confirmed live:** `library_item_research_pioneer_at_jones_sl27` (re-imported the same morning via `importLocalEpubFile`) had `cover_path` empty in the live database.

**Fix:** Added `PioneerTextImportService._fallbackCoverPathForNewItem()`, called from both of the service's own row writers (`_writeImportedWork`, used by `importLocalEpubFile`/HTML-capture/`importSelectedWorks`; and `_writeCopiedRangeImportedWork`, used by `importFromCopiedRange`/`importHtmlCaptureFolders`). It calls `PioneerCoverAssignmentService.ensureCoverPath()` only when the row is brand-new (`createdNew`) and no cover path was already resolved — never touching `cover_path` on a pre-existing row, matching the same "brand-new row only" gate already used by the two working paths. `_repairBrokenCapturedHtmlItemInPlace` (an existing-row repair path) was left untouched — it only ever operates on an already-existing item.

**Live data note:** this fix only affects future imports of a brand-new row; it is not a backfill for already-imported rows with a missing cover (a separate, larger backlog — not in scope here).

---

### 11. `_extractHtmlBlocks` failed to strip the real `<span class="refcode">{...}</span>` marker, showing every ref code twice

**Area:** Pioneer import pipeline (`lib/features/utilities/data/pioneer_text_import_service.dart`)

**Status:** Fixed 2026-09-05, verified against the real SL27 EPUB and live production data.

**Problem:** Two compounding bugs in `_extractHtmlBlocks`'s per-block ref-code handling:

1. The nested-marker lookup only ran when the block had **no** own `data-refcode` attribute (`ownRefCode == null ? _htmlAttribute(innerHtml, 'data-refcode') : null`) — so a block that carried both its own `data-refcode` *and* a nested visible marker (the normal, real-world shape) skipped the nested-marker stripping check entirely.
2. Even with that guard removed, `_stripRefCodeMarkupElement`'s regex only matched a nested element that itself carried a `data-refcode` attribute. The real markup convention — confirmed both against the actual production `SL27.epub` and against `LibraryDocumentCanonicalizer`'s own already-tested `_stripRefCodeSpans`/`_refCodeSpanPattern` — is `<span class="refcode">{SL27 iii.1}</span>`, with **no** `data-refcode` attribute on the span itself. So the marker was never detected or stripped at all, regardless of bug 1.

Net effect: every paragraph's visible text ended with its own bracketed ref code a second time, e.g. `...as may be seen by the official report of the hearing.-Fiftieth Congress... {SL27 iii.1}`, and heading text like `INTRODUCTION {SL27 iii}`.

**Confirmed live:** all 912 text blocks under `library_item_research_pioneer_at_jones_sl27` carried a trailing `{SL27 ...}` marker before the fix.

**Fix:** `_extractHtmlBlocks` now always runs the nested-marker strip (`_stripRefCodeMarkupElement(innerHtml)`), independent of whether the block has its own `data-refcode`; `ownRefCode` remains the authoritative value written to `ref_code`/`elibrary_ref_index` either way. `_stripRefCodeMarkupElement`'s pattern was widened to match a nested element by *either* a `data-refcode` attribute *or* a `class` attribute containing the `refcode` token (mirroring `LibraryDocumentCanonicalizer._refCodeSpanPattern` exactly), and now strips every matching occurrence in the block rather than only the first.

**Live data repair (2026-09-05):** Backed up `eLibrary.db` (SHA-256 verified, `recovery_backups/20260905_114117_pre_sl27_refix_reimport/`). Rehearsed the fix against a scratch copy of the live database first (confirmed cover assigned, zero remaining `{SL27 ...}` markers), then deleted the existing `library_item_research_pioneer_at_jones_sl27` row (a same-day row from an earlier reimport, so no risk to older personal data) and re-imported it live via `importLocalEpubFile` against the real source EPUB (`.../CloudFiles/books/Pioneers/SL27.epub`). `PRAGMA integrity_check: ok` after. Verified directly: cover file now exists on disk and is set on the row, 13 navigation items, 912 text blocks, 0 remaining `{SL27 ...}` occurrences.

---

### 12. Single-spine-file EPUBs (e.g. SL27) had every chapter's content misattributed to whichever heading the parser found first ("INTRODUCTION" bled into "APPENDIX A" and every other chapter)

**Area:** Two independently-duplicated pipelines, same root cause —
`LibraryDocumentCanonicalizer._readSections()`
(`lib/features/library/data/library_document_canonicalizer.dart`) and the
research/commentary indexer's `_readBodySections`
(`lib/features/reader/data/commentary_research_library_service_epub_parsing.dart`).

**Status:** Fixed 2026-09-06.

**Problem:** A book authored as one physical file per book rather than one
per chapter (the real shape produced by a Capture Clipper full-work
capture, e.g. SL27's `content.xhtml` holding INTRODUCTION, ARGUMENT,
ARTICLE, the REMARKS/REPLY exchanges, APPENDIX A, OPEN LETTER, and APPENDIX
B — all 13 authored TOC destinations — in one file) was always read as
exactly **one** section per physical file in both pipelines. Every block
extracted from that file — regardless of which of the book's real chapters
it actually belonged to — inherited the same single section identity
(whichever `<title>`/first heading the parser found), so:
- The canonicalizer's `library_document_sections.title` for the whole book
  was just one label, and anything keying off section identity (e.g.
  `openingDisplayOrder`'s front-matter-skip fallback) saw one large,
  wrongly-labeled blob instead of 13 distinct chapters.
- The research pipeline's `library_text_blocks.section_title` — used
  directly in the commentary/research cross-reference UI to say which
  chapter a matched paragraph came from — labeled **every** paragraph in
  the file with that same single title, so a reference match physically
  inside APPENDIX A could show up labeled INTRODUCTION.

Neither pipeline had ever split a single physical file into per-chapter
sections by the book's own internal anchors; only per-heading *block*
detection worked correctly within that one section (already covered by the
existing "EPUB nav anchors remain reachable" test), which is why headings
themselves were never duplicated — only their section/paragraph
attribution was wrong.

**Fix:** Added a new shared helper,
`EpubInternalAnchorSectionSplitter`
(`lib/features/utilities/data/epub_internal_anchor_section_splitter.dart`),
used by both pipelines instead of two divergent implementations. It reads
the book's own NCX (preferred) or EPUB3 `nav.xhtml` navigation targets,
and — only when 2+ of those targets land inside the same physical file via
distinct internal anchors — slices that file's raw HTML into one section
per target, from each anchor up to the next (mirroring the anchor-to-next-
anchor slicing already proven in
`pioneer_text_import_service.dart`'s NCX-anchored EPUB importer,
`_parseNcxAnchoredEpubSections`, generalized to also read `nav.xhtml`).
Ordinary EPUBs (one file per chapter, exactly the common case) are
completely unaffected: a file with 0-1 targets pointing into it keeps
today's single-section behavior byte-for-byte.

This split also uncovered and required fixing a second, previously-latent
bug: `stableLibraryDocumentBlockId`'s ordinal (and, separately,
`elibrary_ref_index`'s per-href `paragraph_index`) both used to reset to 0
per section on the assumption that each section had its own distinct href.
Two split sections now share an href, so a same-typed, same-anchor(null)
block (an ordinary paragraph) at the same local position in two different
split sections collided on the same stable id / unique key. Both are now
tracked as a running counter per normalized href across all of that href's
sections (`blockOrdinalByHref` in the canonicalizer,
`paragraphIndexByHref` in the ref-index builder) instead of resetting per
section. `LibraryDocumentCanonicalizer.version` bumped 11 → 12 to force
re-canonicalization of already-imported affected books.

**Verification:** `EPUB nav anchors remain reachable and do not promote
bylines` and the new `a single spine file holding multiple chapters via
NCX anchors gets its own distinct section per chapter...` regression test
(both in `test/features/library/data/user_epub_import_service_test.dart`)
pass end-to-end through the actual "add my own EPUB" import path
(`UserEpubImportService.copyIntoLibrary` +
`LibraryAcquisitionOrchestrator.prepareExistingEpub`) — the same path SL27
had a duplication in. The real `SL27.epub` fixture used by the pre-existing
`SL27 preserves every Capture Clipper TOC destination and local heading`
test is not present on this machine, so that specific test still fails here
exactly as it did before this fix (fixture-missing, not a regression — the
new synthetic test above covers the same "APPENDIX A must not inherit
INTRODUCTION's identity" shape it was designed to catch). Also re-ran, each
individually: `library_document_canonicalizer_test.dart` (16/16 pass),
`library_document_canonicalizer_generation_test.dart` (17/18 pass — the one
failure, the "ARGUMET"→"ARGUMENT" OCR-typo test, was confirmed via an
isolated stash of just this fix's files to already fail identically without
it; unrelated, pre-existing, out of scope),
`commentary_research_library_service_epub_validation_test.dart` +
`_epub_storage_test.dart` + `_dual_read_test.dart` (12/12 pass),
`pioneer_text_import_service_test.dart` (31/31 pass, confirms the reused
`PioneerEpubNavigationParser`/NCX-anchored importer are untouched),
`pioneer_epub_inspection_parser_test.dart` (6/6 pass), and
`library_navigation_tree_test.dart` (4/4 pass, including its own
SL27-regression-named "top-level headings that share one physical file via
distinct anchors stay siblings" test). No repair, migration, or data
mutation was performed — this is a code-only fix; already-imported affected
books will re-canonicalize on next open due to the version bump.

**Follow-up (2026-09-06) — the research pipeline had no equivalent
staleness mechanism, so already-imported items never picked up this fix:**
see entry 13 below for the version-gate this was closed with, and entry 14
for a critical false-positive bug the closing pass found in the middle of
it, and a corrected discovery that entry 12's fix does not actually reach
the SL27 item the user re-tested against.

---

### 13. The research pipeline (`library_text_blocks`/`library_navigation_items`) had no version/staleness gate at all — already-indexed items were skipped forever, never picking up parsing-logic fixes like entry 12's

**Area:** `lib/features/reader/data/commentary_research_library_service.dart` +
`commentary_research_library_service_epub_indexing.dart`,
`lib/core/database/elibrary_schema.dart`.

**Status:** Fixed 2026-09-06.

**Problem:** Unlike `LibraryDocumentCanonicalizer`, which compares a
`version` constant against a stored `canonicalizer_version` column and
automatically rebuilds stale generations, the research pipeline's two entry
points into `_storeLibraryTextBlocks`/`_storeNavigationMetadata` both
treated "rows already exist" as permanently done:
- `indexLocalCatalogedEpubs` (wired to the "Index New/Changed Books"
  button) selected only items missing `library_text_blocks` rows entirely —
  an already-indexed item was excluded from its query before any per-file
  logic ran.
- `ensureNavigationIndexed` (called automatically after every canonical
  activation) returned immediately if `library_navigation_items` already
  had any row for that item.

So entry 12's `EpubInternalAnchorSectionSplitter` fix — correct on its own
— could only ever affect a book on its *first* import; every
already-imported book kept whatever rows an older build produced, with no
way to pick up the fix short of manually deleting those rows and
reimporting (the same one-off procedure used for entry 11).

**Fix:** Added `library_research_index_conversion` (`library_item_id`
primary key, `index_version`, `indexed_at`) — the research pipeline's
equivalent of `library_document_conversion`/`canonicalizer_version` — via
`ELibrarySchema` (`currentVersion` 5→6, new
`researchIndexVersionMigrationKey` migration). Added
`CommentaryResearchLibraryService.researchIndexVersion` (currently `1`).
Both entry points now treat a missing or stale stored `index_version` as
equivalent to "no rows exist yet" and rebuild: `indexLocalCatalogedEpubs`'s
selection SQL gained an `OR NOT EXISTS (... index_version >= ?)` clause;
`ensureNavigationIndexed`'s skip check now requires both nav rows present
*and* an up-to-date version row; `_indexFile`'s own finer-grained
`needsIndex` check gained the same condition, for the separate (non-bulk)
caller that iterates every discovered file directly. Both entry points
write the current version back after a successful rebuild.

**Verification:** New test in
`commentary_research_library_service_epub_validation_test.dart` — seeds a
real indexed item, downgrades its stored `index_version` to 0 and plants an
obviously-stale marker nav row, then confirms a second
`ensureNavigationIndexed` call replaces the marker row (a version-unaware
"already has rows" skip would have left it in place forever) and writes
back the current version. Ran individually, each pass with no new
failures beyond the pre-existing ones already tracked under entry 12:
`library_document_canonicalizer_test.dart` (16/16),
`library_document_canonicalizer_generation_test.dart` (17/18),
`user_epub_import_service_test.dart` (4/5, SL27 fixture still absent from
this machine), the three `commentary_research_library_service_epub_*`/
`_dual_read` suites (13/13, including the new test),
`canonical_library_reader_epub_pilot_test.dart` (6/8),
`library_navigation_tree_test.dart` (4/4), `pioneer_text_import_service_test.dart`
(31/31), `pioneer_epub_inspection_parser_test.dart` (7/7, including the new
test added for entry 14).

**Important scope note found while closing this out:** this mechanism only
covers items whose content actually flows through
`CommentaryResearchLibraryService` (`library_items.file_format = 'epub'`).
It does **not** reach SL27 — see entry 15.

---

### 14. Critical: reusing `PioneerEpubNavigationParser` for entry 12's fix would have shredded ~98 ordinary, correctly-structured EGW EPUBs into fake page-fragment "sections" the first time anyone reindexed the catalog — caught before any live reindex ran

**Area:** `lib/features/utilities/data/pioneer_epub_inspection_parser.dart`
(`PioneerEpubNavigationParser.parse`), which entry 12's
`EpubInternalAnchorSectionSplitter` and the existing
`pioneer_text_import_service.dart` NCX-anchored importer both depend on.

**Status:** Fixed 2026-09-06, caught during a read-only pre-flight scan
before any live data was touched.

**Problem:** Before attempting the SL27 live reindex entry 13 was built
for, a read-only diagnostic (`tool/research_index_version_reindex/
scan_single_spine_shape.dart`) checked all 450 already-indexed EPUB
research items for the "2+ authored destinations share one physical file"
shape entry 12's fix targets — expecting a small number of genuine
Capture-Clipper-style single-spine-file books. It found **98**, including
core, obviously-not-single-file titles like *The Great Controversy* (26),
*Testimonies for the Church, vol. 6* (41), and *Life Sketches of James
White and Ellen G. White 1888* (78).

Root cause: `PioneerEpubNavigationParser.parse` (already shipped,
independently used by `pioneer_text_import_service.dart`'s
`_parseNcxAnchoredEpubSections`) scanned an NCX's entire raw text for any
`<navLabel><text>...</text></navLabel><content src="..."/>` pair, without
scoping to `<navMap>`. A real, well-formed EPUB's NCX commonly carries a
sibling `<pageList>` — printed-page-number targets (e.g. "iv", "v", "vi")
mapped onto anchors *inside* ordinary chapter files, for print/page
cross-reference — using that exact same tag shape. Every page number
landing inside one chapter file (dozens per chapter, in *The Great
Controversy*'s case) looked identical to a genuine multi-chapter
single-spine-file book. Had this shipped unfixed and someone pressed
"Index New/Changed Books" after this pass's version bump (entry 13), every
affected EGW book's real chapters would have been shredded into dozens of
fake page-fragment "sections" on next reindex.

**Fix:** `PioneerEpubNavigationParser.parse` now scopes its scan to the
content between `<navMap>` and `</navMap>` when that tag is present (falls
back to the whole document only for a malformed NCX with no `<navMap>` at
all, unchanged from before). `<pageList>`/`<navList>` content is no longer
read as chapter/section navigation. This is a correctness fix to
already-shipped, shared code — it also protects the existing Pioneer NCX-
anchored importer from the same latent contamination for any Pioneer book
with a page list, not just the new code path.

**Verification:** New test in `pioneer_epub_inspection_parser_test.dart`
("ignores a sibling &lt;pageList&gt; so printed-page targets are never
mistaken for chapter navigation") proves a 3-page-target `<pageList>`
sharing one chapter file no longer contaminates the 2-chapter result.
Re-ran the same 450-item live scan after the fix: **2** affected (down from
98) — `The Cross and its Shadow` (3) and `The Story of the Seer of Patmos`
(24), both genuine, non-pageList NCX structures (confirmed directly against
their raw NCX bytes). Both are pre-existing "hardcoded canonical bridge"
legacy items the 2026-08-30 nav-tree investigation already flagged as
special-cased and fragile — **not bulk-reindexed in this pass**, per the
instruction to report the count/list rather than act on it; a decision on
whether/how to reindex these two specifically is still open.
`pioneer_text_import_service_test.dart` (31/31) and
`pioneer_epub_inspection_parser_test.dart` (7/7, including the new test)
both pass after this change. No live data was touched by this discovery —
it was caught by the read-only scan before the SL27 reindex (entry 15)
was even attempted.

---

### 15. SL27's actual content pipeline is `PioneerTextImportService.importLocalEpubFile`, not the research pipeline entry 13's version gate covers — the requested SL27 live reindex was not performed

**Area:** Cross-pipeline identity — `library_items.file_format`/
`relative_path` for SL27 vs. what `CommentaryResearchLibraryService`'s
version gate (entry 13) can reach.

**Status:** Investigated 2026-09-06, live reindex intentionally **not**
performed — needs a decision before any further action.

**Problem:** The user rebuilt from source, reloaded SL27, and reported the
duplication bug still present. Before running the requested live SL27
reindex, live inspection of `eLibrary.db` (read-only; see below) found:

- SL27's catalog row (`library_item_research_pioneer_at_jones_sl27`) has
  `file_format = 'html'`, `mime_type = 'text/html'`,
  `relative_path = 'TextCaptures/Research/Pioneer Authors/a_t_jones/
  SL27.html'` — **not** an EPUB in the catalog's own record. That source
  `.html` file does not currently exist on disk under the app's live
  Library Root at all.
- `ensureNavigationIndexed` (entry 13's gate) bails out immediately for any
  non-`.epub` file; `indexLocalCatalogedEpubs`'s selection SQL only
  considers `file_format = 'epub'` rows. SL27 is unreachable by either,
  regardless of the new `index_version` mechanism — the version gate this
  pass built is real and correctly closes the gap for genuine EPUB-backed
  research items, but it was never going to touch SL27 specifically.
- SL27's `epub_href` values in `library_text_blocks`
  (`OEBPS/content.xhtml#heading-2-N`, fragment included) and its
  `library_navigation_items` rows (`anchor_id` always `NULL`, the fragment
  folded into `href` instead) match the exact output shape of
  `pioneer_text_import_service.dart`'s `PioneerImportSection`/
  `_parseNcxAnchoredEpubSections` — not
  `CommentaryResearchLibraryService`'s shape (bare `href` +
  a separate `anchor_id` column, confirmed against the passing "EPUB nav
  anchors remain reachable" test). This is consistent with entry 11's
  note that SL27 was last reimported via `importLocalEpubFile` on
  2026-09-05 — a third pipeline this pass never touched.
- Directly inspecting the live rows: `library_text_blocks.section_title`
  and `library_navigation_items.href`/`parent_id` for SL27 **already** show
  11 distinct, correctly-titled sections with correct parent/child nesting
  (INTRODUCTION, ARGUMENT, "ARTICLE" with REMARKS/REPLY correctly nested
  under it, APPENDIX A with OPEN LETTER nested under it, APPENDIX B — all
  present exactly once, no duplication visible in the stored data itself).

**Conclusion:** The live data for SL27 does not show the duplication this
pass's fixes target — it already looks like a correct, already-split
result (most likely from the entry 11 reimport, unrelated to anything in
entries 12-14). Reindexing SL27 through the mechanism entries 12-13 built
would be a no-op (it can't reach an `.html`-format catalog row) and was
**not attempted**. Two possibilities remain open, and only the user can
say which matches what they're actually seeing: (a) the "stacking" symptom
is a presentation/reader-layer issue — however the app renders/groups
`library_text_blocks` or `library_navigation_items` for a research-role
item, independent of the (apparently correct) stored data, or (b) there is
still something wrong that a raw SQL dump doesn't surface and a screenshot
or precise description of what's stacking would help pinpoint it.

**Safety note:** A full SHA-256-verified backup of the live `eLibrary.db`
was taken (`_pre_research_index_version_reindex_backup_20260906_105729`,
alongside the app's other timestamped backups) and the running app was
quit before any inspection, per established discipline — but **no write
was made to the live database**; it is byte-identical to that backup.


### 3. eLibrary search results may return too few matches

**Area:** eLibrary Search

**Status:** Fixed on Android

**Android verification (2026-08-16):** Fixed on Android. The `All Collections` search for `angels` initially displayed 8 results even though the Android search index contained 148 matching paragraphs across 8 books. The count query incorrectly counted distinct books and then used that value as the paragraph-result limit. It now counts matching paragraph rows; the rebuilt Android app reports all 148 results.

Previous testing suggested some searches may return fewer results than expected.

One historical test case was searching for terms such as `angels` in EGW/eLibrary material.

Verify:

* Search result completeness.
* Results across multiple books/collections.
* No artificial result truncation or filtering.
* Correct behavior with `All Collections` selected.

Do not change search logic unless the problem can still be reproduced.

---

### 4. Search-result hit text bolding

**Area:** eLibrary Search UI

**Status:** Verified on Android

**Android verification (2026-08-16):** Verified on Android. The matching word `angels` is visibly bold within result snippets while surrounding text retains its normal weight and formatting.

Previous testing indicated matched words/phrases in eLibrary search results were sometimes not visually bolded/highlighted.

Verify that:

* The actual matching search term is visibly emphasized.
* Highlighting works consistently across search-result types.
* Highlighting does not damage surrounding formatting.

If current behavior is already correct, mark this item fixed rather than making unnecessary changes.

---

### 5. Reference codes in eLibrary search results

**Area:** eLibrary Search UI

**Status:** Verified on Android

**Android verification (2026-08-16):** Verified on Android. Search-result cards display reference codes where indexed, including `DAR 401.1`, `DAR 726.3`, and `DAR 328.3`. Search formatting does not suppress the codes.

Previous testing indicated that reference codes were not always visible in the search-result view, even though they may appear correctly in normal eLibrary reading views.

Verify specifically in **search results**, not only normal document viewing.

Expected behavior:

* Reference codes should display where appropriate.
* Existing ref-code hide/show controls should continue working.
* Search-result formatting should not accidentally suppress them.

If current behavior is correct, mark this item fixed.

---

## Fixed

### Pioneer EPUB imports (`pioneer_epub_import_id_*`): navigation tree and search text blocks never built

**Area:** Pioneer EPUB import pipeline (`library_acquisition_orchestrator.dart`, `pioneer_archive_org_install_service.dart`)

**Status:** Fixed (code + live data repair), 2026-08-30; archive.org-cohort Contents/position follow-up fixed (code + live data repair), 2026-08-31 — see the dated entries below.

**Problem:** 522 of 524 `pioneer_epub_import_id_*`/`pioneer_<author>_<code>` library items had completely empty navigation — zero rows in `library_navigation_items` and zero rows in `library_text_blocks` — even though their body text had parsed fine into `library_document_blocks`/`library_document_sections`. Only "The Cross and its Shadow" and "The Story of the Seer of Patmos" were correctly indexed, and only because they still had a surviving row under the *older* `library_item_research_pioneer_*` id scheme.

**Cause:** Two entirely separate pipelines write a library item's readable content, and only one of them ever builds `library_navigation_items`:
- The old folder-scanning indexer (`CommentaryResearchLibraryService._indexFile`/`_storeNavigationMetadata`, in `commentary_research_library_service_epub_indexing.dart`) builds both the navigation tree and `library_text_blocks` — this is what every `official_download` item and the two legacy-id Pioneer titles go through.
- The newer canonicalizer (`LibraryDocumentCanonicalizer.canonicalize`, reached via `CanonicalActivation.activate`) only ever writes `library_document_blocks`/`library_document_sections` — it has no navigation-building code at all.

Every Pioneer EPUB import (`import_pioneer_library_screen.dart`'s bulk folder import, the `pioneerthin.zip` combined install, and `pioneer_archive_org_install_service.dart`'s per-title archive.org downloads) funnels through `CanonicalActivation.activate` alone and never separately called the old indexer, so it never got a navigation tree — not a one-off import mistake, but a structural gap in the pipeline that would reproduce for every future Pioneer import.

`CommentaryResearchLibraryService.indexLocalCatalogedEpubs` — a public method already wired into other screens' "Index Now" flows — could in principle have filled this gap, but (a) `LibraryCatalogService.countUnindexedManagedItems()` (which gates the prompt) only checks `folder_type IN ('commentary', 'research')`, excluding `folder_type = 'pioneer_epub_import'` entirely, and (b) even if run directly, it recomputes the target id via `_itemId(folderType, relativePath)`, which for Pioneer rows (identity is based on the EPUB's own `dc:identifier` or original source path, not the copied destination path) does not match the item's real id — it would have written a second, orphaned row instead of fixing the real one.

**Fix:** Added `CommentaryResearchLibraryService.ensureNavigationIndexed({db, libraryItemId, file})` — a small, side-effect-scoped method that builds navigation + text blocks for an exact, already-known `libraryItemId` (never recomputing or touching the `library_items` row itself), is a no-op if navigation already exists, and never throws (a parsing failure here must never fail the book's activation). Called it from `LibraryAcquisitionOrchestrator.prepareExistingEpub` (the single choke point behind every bulk EPUB import) and from `pioneer_archive_org_install_service.dart` right after each successful `CanonicalActivation.activate`, so every future Pioneer import — bulk folder, combined zip install, or per-title archive.org download — gets a working navigation tree automatically, with no dependency on a separate manual "Index Now" step.

**Live data repair (2026-08-30):** Backed up `eLibrary.db` (SHA-256 verified). Wrote `tool/nav_tree_repair/run_nav_tree_repair.dart` (same `flutter test`-driven pattern as the archive.org repair tool), dry-ran it, then applied live: found 468 items with real content but no navigation, built navigation + text blocks for all 419 `pioneer_epub_import` items reachable on disk (421/421 now have navigation) plus 2 already resolved from an earlier partial run, and correctly left 49 `pioneer_archive_org_download` items alone because their source files are missing on disk (see "known remaining gap" in the archive.org entry above — the same pre-existing, unrelated issue). `PRAGMA integrity_check: ok` after. The two already-working legacy items (CIS/SSP) and their `duplicate_retired` shadow rows were untouched, as intended.

**Also checked (not a blocker):** No correlation between "direct source EPUB" vs. "pieced-together" source and whether navigation ended up populated — navigation was 0% for both the uniform `aplib`-sourced bulk import (421 items, ~99.5% canonicalization success) and the individually-sourced archive.org downloads (100 items, 49% canonicalization success) for the exact same reason (the pipeline never built it at all). The archive.org batch's lower canonicalization success rate is a separate, already-tracked issue (missing source files, see above), not a navigation-building problem. Separately confirmed: 79 titles exist as duplicate rows under two different Pioneer id schemes (bulk `aplib` import vs. individual archive.org download) — both copies now have working navigation, but the duplication itself is unrelated to this bug and was left alone as instructed.

**Correction after live testing (2026-08-31): the "421/421 have navigation" success metric did not predict working Contents/position UI, because it only measured whether a `library_navigation_items` row exists — not whether it encodes any real chapter structure.** Dean spot-checked the app and found Contents/position broken on most titles, one "Daniel and The Revelation" duplicate that wouldn't open at all, and one clean success ("Christ Our Righteousness"). Root cause, found by diffing the two: the canonical reader's Contents dialog (`_openContents` in `canonical_library_reader.dart`) and its opening-position logic (`LibraryDocumentRepository.openingDisplayOrder`) both key entirely off `library_document_blocks` rows with `block_type = 'heading'` — not off `library_navigation_items` (that table only feeds the *optional* nesting/depth lookup added 2026-08-28, and gracefully no-ops when it finds nothing). So the real question was never "does a nav row exist," it's "did the canonicalizer find any real `<h#>`-tagged chapter markup in the source EPUB":
- **`pioneer_epub_import` (bulk `aplib`-sourced, e.g. "Christ Our Righteousness")**: real per-chapter `.xhtml` spine files with real `<h#>` tags. Checked all 245 items with >150 body blocks — zero have fewer than 3 headings; heading counts scale sensibly with book length. This cohort's Contents/position genuinely works. (Titles with 0-1 headings in this cohort, checked individually, are short single-section pamphlets/sermons that legitimately have no sub-chapters — not a bug.)
- **`pioneer_archive_org_download` (the 100 per-title archive.org downloads, e.g. "Daniel and The Revelation" / `pioneer_uriah_smith_dar1909`)**: these are raw archive.org OCR conversions — one HTML file *per scanned page* (`page_0.html`, `page_1.html`, ...), no `<h1>`-`<h6>` tags anywhere, and `nav.xhtml` contains no real chapter list at all (verified: just a single "Notice" entry). Chapter titles exist only as unmarked OCR text run together mid-paragraph at the top of whichever page they fall on (e.g. `"07 - THE FOUR BEASTS Chronological Connection..."` inline with body text in `page_100.html`). The canonicalizer's heading heuristic has nothing to detect. Checked every archive.org item with real content and >50 blocks (20/20, 100%): every single one canonicalized to exactly **1 heading total** (the book title) regardless of actual length — "Health, or, How to Live" (417 blocks) and "The Autobiography of Elder Joseph Bates" (238 blocks) collapse to the same single heading as a 13-block tract. Confirmed systemic across the whole cohort: all 49 archive.org items with content and >0 blocks have ≤1 heading. This is why Contents renders as empty/useless and "current position" has nothing to highlight against for this entire cohort — not a wiring bug, a source-data-fidelity gap in canonicalized heading extraction for page-scanned EPUBs.
- **The Daniel and The Revelation mystery, resolved:** three rows exist for this title. The working with-cover copy (`library_item_research_pioneer_uriah_smith_DAR_US`, `egw_html_capture`) never touches the EPUB canonicalizer at all — it's a browser-captured, chapter-chunked import with its own real 23-item nav tree via the old indexer, which is why it alone worked. The no-cover copy (`pioneer_uriah_smith_dar1909`, `pioneer_archive_org_download`) is the OCR-scanned edition described above (1 heading / 744 blocks). A third row (`library_item_pioneer_epub_import_importedpioneerepubs_daniel_and_the_revelation_epub`) is already `deleted_at`-retired and correctly excluded from every list query.
- **The real root cause of "won't open at all"/"TOC disagrees with displayed content," found 2026-08-31: `pioneer_archive_org_download` items never actually reached the canonical reader described above at all.** `supportsCanonicalEpubReader` (`canonical_library_reader.dart`) gates eligibility with an exact `source_type` switch — `official_download`, `user_import`, `pioneer_epub_import`, `pioneer_egw_epub_source` — and `pioneer_archive_org_download` was never added to it, even though the archive.org installer writes into the exact same `ImportedPioneerEpubs` folder as `pioneer_epub_import` and canonicalizes the same way. Every item in this cohort therefore silently fell back to the **legacy** reader for every open, regardless of how much real content the canonicalizer had built. The legacy reader's Contents/tap-to-navigate comes from an entirely independent pipeline (`library_navigation_items`, built by the old folder-scanning indexer's own separate EPUB parse) — a second, disconnected source of truth from whatever the legacy renderer actually displays, which is exactly the "two different, out-of-sync sources" symptom Dean reproduced on-device (Contents shows entries, tapping any of them does nothing, and the list doesn't match what's rendered).
- **Fixed (2026-08-31).** Two changes, both live in the canonicalization/routing pipeline itself (not a one-off data patch):
  1. **Reader routing** — `supportsCanonicalEpubReader` now accepts `pioneer_archive_org_download` alongside `pioneer_epub_import` (same `ImportedPioneerEpubs` folder-path eligibility check, `canonical_library_reader.dart`). This alone makes every item in the cohort route through the canonical reader, where Contents and reading position both come from the *same* `library_document_blocks` heading rows — eliminating the two-pipeline disagreement for all of them, even the ones with only the single book-title heading.
  2. **OCR chapter-heading recovery** — `LibraryDocumentCanonicalizer` (bumped to version 8) now recognizes the unmarked `"NN - TITLE"` run OCR leaves mid-paragraph (e.g. `"07 - THE FOUR BEASTS Chronological Connection..."`) and splits it out as a real `heading_role: chapter` block, the same role real `<h2>`-derived chapter headings carry. Recovery requires the number to match the next expected chapter in strict sequence (same monotonic-tracking technique already used for the `"CHAPTER <roman numeral>."` pattern in the browser-capture importer), so an incidental `"NN - CAPS"` run elsewhere in body prose can only be misread as a heading if it lands on the exact next chapter number in order — effectively never. The detection gate (`_needsOcrChapterHeadingRecovery`) only activates when *no* section in the whole spine has a real `<h1>`-`<h6>` tag, checked generically (not by source type), with one carve-out found by testing against the real files: the EPUB nav document itself (`epub:type="toc"`) is excluded from that scan, since these archive.org exports embed it as the *first* spine entry and it carries its own real `<h2>` page title — without the carve-out that one structural heading wrongly "proved" the whole book had real semantic markup and blocked recovery outright. Because this lives in the canonicalizer, it applies automatically to any future import with the same shape, not just this batch.
  - **Verified against the real files, not just synthetic fixtures**: unzipped the actual archive.org EPUBs from the live Library Root and ran the canonicalizer against them directly. "Daniel and The Revelation" (the flagship example from the original report) went from 1 heading to 23 (the book title plus all 22 real chapters, "01 - DANIEL IN CAPTIVITY" through "22 - THE TREE AND THE RIVER OF LIFE", matching the book's own printed TOC exactly) with clean title boundaries — including two edge cases only found by testing against the real text: back-to-back chapter headings on the same page (chapter 1's title must not swallow chapter 2's leading number) and a final chapter running straight into unmarked back matter with no boundary at all (must stop before "APPENDIX"). Both are now covered by regression tests in `library_document_canonicalizer_generation_test.dart`.
  - **Honest scope check across the rest of the cohort**: grepped every one of the 49 archive.org items with content that are actually present on disk for the `"NN - TITLE"` pattern. **Daniel and The Revelation is the only one that uses it** — every other title (48/49) is a short tract/pamphlet/sermon whose original print has no internally-numbered chapters at all, or uses a different convention this fix does not attempt (e.g. "Health, or, How to Live" prints its section markers as spelled-out "NUMBER ONE"/"NUMBER SIX", not digits). Those 48 correctly remain at a single book-title heading after this fix — consistent with the same, already-established pattern elsewhere in this codebase where a short single-section work legitimately has 0-1 headings. The fix is real, live-tested, and will recover chapters automatically for any current or future title that does use the numbered convention; it does not manufacture chapter structure for books that never had it. The reader-routing fix (above) is what actually resolves the reported symptom uniformly across all 49, regardless of how many headings each ends up with.
  - **Live data repair (2026-08-31):** Backed up `eLibrary.db` (SHA-256 verified, `recovery_backups/20260831_ocr_chapter_heading_repair/`). Re-ran the existing `tool/pioneer_archive_org_repair/run_pioneer_archive_org_repair.dart` (its "Step 2" already force-recanonicalizes every surviving archive.org item with a file present on disk — exactly what picking up the new canonicalizer version needed, no new tool required) dry-run against a scratch copy first, then applied live: 100 items scanned, 49 recanonicalized (0 failed), 51 left untouched because their source files are still missing on disk under the current Library Root (the same pre-existing, already-documented gap from the 2026-08-30 repair — unchanged by this fix). `PRAGMA integrity_check: ok` after. Verified directly by query: Daniel and The Revelation now has 23 headings (was 1); the other 48 items' heading counts are unchanged, as expected.
  - Added tests: `library_document_canonicalizer_generation_test.dart` (OCR recovery on a synthetic multi-page fixture, a real-shaped nav-document exclusion case, the back-to-back/APPENDIX title-boundary cases, and a control case proving a book with any real semantic heading is never touched) and `canonical_library_reader_epub_pilot_test.dart` (`pioneer_archive_org_download` eligibility, in and outside the managed folder). `flutter analyze` clean on every touched file and project-wide; full `test/features/library/` + `test/features/utilities/` sweep (805 tests) has exactly one failure, and it's the same pre-existing `elibrary_setup_screen_sections_test.dart` failure already documented in `Progress.md` as belonging to unrelated in-progress work in the working tree, confirmed unrelated by isolating this fix's files.

---

### Pioneer archive.org downloads: every book corrupted (no real text, no navigation), plus duplicate library entries

**Area:** Pioneer EPUB import pipeline (`pioneer_archive_org_install_service.dart`, `pioneer_epub_folder_inventory_service.dart`)

**Status:** Fixed (code + live data repair), 2026-08-30.

**Problem:** Reported as "fix the Pioneer EPUB import pipeline so it builds navigation and text blocks correctly for all of them, plus dedupe the Daniel Revelation copies." Live-database inspection found all 101 `pioneer_archive_org_download` items had exactly one corrupted `library_document_blocks` row (the raw ZIP bytes of the `.epub` file, visibly starting with `PK\x03\x04`) and zero navigation rows, plus three duplicate `library_items` rows for one physical file each: "Daniel and The Revelation" (Uriah Smith), "The Cross and its Shadow," and "The Story of the Seer of Patmos" (S. N. Haskell).

**Cause:** Two independent bugs:
1. `_stageActivateAndPromote` canonicalized each download against a *staging* file named `.<title>.epub.<timestamp>.downloading`. `LibraryDocumentCanonicalizer.canonicalize` decides whether to unzip a source purely by its file extension, and the staging file's real extension was `.downloading`, so every archive.org download was treated as plain text instead of an EPUB.
2. Two different duplicate-causing bugs: the manifest lists two real, distinct archive.org editions of "Daniel and The Revelation" (`DAR`/`DAR1909`) whose sanitized file names collided, so the second download overwrote the first on disk while both kept separate `library_items` rows; separately, the local-folder scanner's legacy-identity bridge excluded any candidate row whose `source_type == 'pioneer_epub_import'`, which wrongly excluded the hardcoded canonical bridge targets themselves (CIS/SSP) once they'd been bridged once, causing every later re-scan to mint a fresh duplicate id instead of reusing the canonical one.

**Fix:** Staging file names now keep a real `.epub` extension (timestamp moved to the front of the name instead of the end). The archive.org installer now detects title collisions across the whole manifest up front and folds each colliding work's unique `code` into its file name. The folder scanner's legacy-bridge exclusion now matches on the scanner's own id-prefix pattern instead of `source_type`. See `Progress.md`'s 2026-08-30 entry for full root-cause detail and test coverage.

**Live data repair (2026-08-30):** Backed up `eLibrary.db` (SHA-256 verified), quit the running macOS app first, dry-ran `tool/pioneer_archive_org_repair/run_pioneer_archive_org_repair.dart` against scratch copies, then applied live: 3 duplicate pairs retired (soft-deleted, `PRAGMA integrity_check: ok` after), 49/100 surviving archive.org items recanonicalized from 1 garbage block to real content (DAR1909 went from 1 to 744 real blocks).

**Known remaining gap:** 51 of the 101 archive.org-downloaded items have no file at their expected path under the current Library Root at all (likely the documented macOS security-scoped-bookmark reset issue — the files may still exist under a previous Library Root folder). These were marked `needs_attention` with their corrupted generation cleared, so a future "Update Verified Pioneer Books" run will re-download them fresh instead of skipping them as already-complete. Dean should check whether an older Library Root folder still holds these 51 files before assuming a full re-download is needed.

---

### eLibrary Contents showing no nesting or current-location highlight for EGW official EPUBs (Early Writings, etc.)

**Area:** eLibrary / canonical reader Contents dialog

**Status:** Partially fixed, 2026-08-27. Reported live on Android as "no nested TOC in EW, nor can I see on the TOC any highlighted indication of my current location."

**Real root cause (this took most of the investigation to pin down):** official EGW EPUB downloads like Early Writings don't actually use `library_book_reader_screen.dart` / `library_contents_popup.dart` at all — `supportsCanonicalEpubReader` routes them into a completely separate reader, `CanonicalLibraryReaderScreen` (`canonical_library_reader.dart`), built on its own storage table (`library_document_blocks`), independent of `library_navigation_items`. All of the `library_navigation_items` work below (parent-link bug, sort-order repair) is real and still worth having — it's what the *legacy* reader uses, and canonical prep still falls back to it when a book isn't (yet) eligible — but it isn't what actually renders Early Writings' Contents. That dialog (`_openContents` in `canonical_library_reader.dart`) was just `headings.map((h) => ListTile(title: Text(h.plainText)))` — a flat list, no depth, no indication of current position, by omission rather than data corruption.

**Fix:** `_openContents` now indents each heading by its `heading_role` (h2/'chapter' → depth 0, h3/'section' → depth 1, h4-h6/'minor' → depth 2) and highlights whichever heading the current reading position falls under (bold, colored text, left accent border) — the same visual treatment the legacy popup already had. Verified live on the device: within-chapter sub-headings ("Texts Referred to on Preceding Page" under "My First Vision") now nest correctly.

**Known remaining gap:** `heading_role` only reflects structure *within* a single spine file (from that file's own `<h1>`–`<h6>` tags). It has no idea that "My First Vision," "Subsequent Visions," etc. are conceptually children of the "Experience and Views" *section* — each is its own spine file, and the real parent/child relationship for that only exists in `library_navigation_items` (which this reader doesn't consult). So EW's top-level chapter list is complete and now internally-nested, but the top-level items don't yet group under their section headers the way they did in the legacy reader's TOC. Closing that gap means cross-referencing `library_navigation_items`'s (now-correct) parent/child tree with the canonical `library_document_blocks` headings — a real follow-up, not something to guess at further without your input on priority.

Also inconsistent: a few sub-headings detected by the canonicalizer's *heuristic* classifier (not a real `<h#>` tag — e.g. "About the Author," "Further Links" inside `aboutbook.xhtml`) get `heading_role: 'chapter'` instead of `'section'`, so they don't indent even though they're conceptually nested. Same underlying limitation, not something this pass fixed.

**Section-grouping investigation (2026-08-28):** Looked into cross-referencing `library_navigation_items` and `library_document_blocks` to close the gap above. Findings:

* Schema: `library_navigation_items` (`lib/core/database/elibrary_schema.dart:338-361`) vs. `library_document_sections`/`library_document_blocks` (same file, `44-54`/`56-69`). There is no `heading_role` column — it's `formatted_content` JSON at `$.metadata.heading_role` (`LibraryDocumentBlock.headingRole`, `lib/features/library/data/library_document_models.dart:102-103`).
* **Correction after checking the live database directly (static code reading alone was misleading here):** a third pipeline — the "research library" full-catalog EPUB scan (`commentary_research_library_service_epub_indexing.dart`, folderType `'research'`/`'commentary'`) — walks every file in the managed EGW folder and writes `library_navigation_items` for `official_download` items by parsing each real `.epub`'s actual navMap/spine independently, then reconciling IDs onto the same `library_items.id` via `_normalizeManagedLibraryItemIdentity`. So **every** `official_download` item already has a full nav tree; canonicalization (`library_document_blocks`) just hasn't caught up yet for most of them.
* **Live counts (non-deleted `library_items`):** `official_download`: 454 total, 454 with `library_navigation_items` (100%), 5 with `library_document_blocks`. `pioneer_epub_import`: 422 total, 0 with nav rows, 422 with document_blocks. `egw_html_capture`: 2 total, 2 with nav rows, 0 with document_blocks. `pioneer_egw_epub_source` (the synthetic-href path flagged below): 0 items currently in the live catalog.
* **Href-equality join works reliably where it matters.** For all 5 `official_download` items currently canonicalized, every chapter heading's `library_document_blocks.source_href` exactly matches (after normalization) a `library_navigation_items.href` — 233/233 chapter headings across those 5 titles (e.g. Acts of the Apostles 60/60, Evangelism 168/168) — because both pipelines independently parse the same real `.epub`'s navMap/spine. The earlier claim that href-joining "doesn't work" was based on the `pioneer_egw_epub_source` path only (`pioneer_text_import_service.dart:5091-5109`, synthetic `captured/{workAbbrev}/...` hrefs) — real, but currently a zero-item edge case, not the dominant path. `pioneer_epub_import` (422 items) has no nav rows at all regardless of join key, so it depends entirely on graceful degradation. Nested TOC structures ("Experience and Views" style) are confirmed common, not hypothetical — e.g. Selected Messages Book 1 has a 322-row, depth-3 nav tree.
* **Recommended approach (revised):** in `canonical_library_reader.dart`'s `_openContents`, read-only and additive — query `library_navigation_items` for the same `library_item_id`, build its tree via the existing `buildLibraryNavigationTree()` (`lib/features/library/presentation/library_navigation_tree.dart:16` — reuse, don't reimplement), and match `heading_role: 'chapter'` blocks to nav items by **normalized href first** (same normalization as `normalizeLibrarySourceHref`), **falling back to normalized label text** only when href doesn't resolve (covers the synthetic-href path if it's ever populated again). Skip nav rows the legacy reader already treats as non-sections via `_isNavigationSupportEntry` (`library_contents_popup.dart:168-179`). No nav rows for the item (the entire `pioneer_epub_import` cohort today) → render exactly as today, no behavior change. No schema change, no data duplication.
* Alternatives considered and set aside: writing a derived `section_parent_href` onto `library_document_blocks` at canonicalization time (rejected — duplicates data that a same-item nav-tree lookup already provides for the cohort that matters, for no benefit); deriving grouping purely from spine order/heuristics with no nav dependency (would still be needed as a separate follow-up for the `pioneer_epub_import` cohort, which has no nav rows to join against at all — out of scope for this pass).
* **Implemented in code (2026-08-28), pending live visual verification:** the canonical Contents dialog now loads the same-item navigation rows, builds them with `buildLibraryNavigationTree()`, and uses normalized href matching first with normalized label fallback. Matched canonical headings inherit the EPUB navigation depth while retaining their within-file `heading_role` depth; support rows are skipped, and books with no navigation rows render exactly as before. Targeted canonical-reader tests cover cross-file grouping, no-nav fallback, support-row promotion, and label fallback; static analysis passes.

---

### eLibrary TOC (legacy reader) showing no nesting at all for books with real sub-chapters (Early Writings, SDA Bible Commentary, etc.)

**Area:** eLibrary / Table of Contents navigation (legacy `library_book_reader_screen.dart` / `library_contents_popup.dart` — used as the canonical-reader fallback, and for any book not yet eligible for canonical)

**Status:** Fixed (code + live data repair), 2026-08-27.

**Platform:** All (shared Dart parsing code — no platform branching).

**Problem:**

Books whose real embedded TOC/navMap has genuine multi-level nesting — e.g. Early Writings' "Experience and Views" section containing "My First Vision," "Subsequent Visions," etc., or the SDA Bible Commentary volumes' "Genesis" containing "Chapter 1," "Chapter 2," etc. — rendered as a completely flat list in this reader. Every nested chapter showed at the top level instead of grouped under its section.

**Cause:**

`_extractNavigationEntriesFromDocument` in `commentary_research_library_service_epub_parsing.dart` estimates a nesting `depth` for every anchor parsed out of a book's embedded TOC document (by counting unclosed `<ol>` tags), but always hard-coded `parent_id: null` regardless of that depth. The Contents UI (`buildLibraryNavigationTree`) builds its entire tree from `parent_id`, ignoring the `depth` column — so real nesting was silently discarded at import time. This predates the 2026-08-25 front-matter/sort-order work; it only became visible once a book with genuine multi-level TOC nesting was checked closely.

**Fix:**

`_extractNavigationEntriesFromDocument` now walks entries in document order with a depth stack, linking each entry to the nearest preceding entry with a smaller depth (the same shape of fix as the sort-order tree-walk). `commentary_research_library_service_epub_indexing.dart`'s `rootsByHref` construction was adjusted to stop excluding now-parented entries, so a nested chapter still anchors its own spine page's body content (previously a no-op check, since parent_id was always null before this fix — leaving it as-is would have spawned duplicate entries for every nested chapter).

**Live data repair (2026-08-27):** Built `tool/nav_parent_link_repair/run_nav_parent_link_repair.dart`, which repairs already-imported rows by recovering each entry's original document order from the numeric suffix baked into its `id` and re-running the same depth-stack walk. Backed up both databases (SHA-256 verified), dry-ran against copies first, then applied it live to **both** the macOS database (macOS app fully quit first) and the Android device's database (pulled via adb, repaired, app force-stopped, pushed back, re-verified via a fresh pull): 48 titles affected on each, 3,584 navigation rows re-parented, `PRAGMA integrity_check` passed on both, and both verified via direct query afterward (Early Writings' 73 nested chapters correctly parented under their 3 sections).

**Also applied to Android (2026-08-27):** last night's sort-order collision repair (see entry below) had never actually reached Android's live database — the report file labeled "android" turned out to be a byte-for-byte duplicate of the macOS report, not a real run against the device. Ran it for real this time: 97/97 items, 14,190 rows renumbered, verified zero remaining collisions on-device after relaunching the app.

**Not yet checked:** iOS and Windows local databases weren't reachable from this session. Same symptom would need the same two repair tools (`tool/nav_parent_link_repair/` then `tool/nav_sort_order_repair/`) run against their own `eLibrary.db` — check with the affected-item queries in each script before assuming it's needed.

---

### eLibrary TOC showing front matter interleaved with chapters ("scrambled" ordering)

**Area:** eLibrary / Table of Contents navigation

**Status:** Fixed (code + live data repair), 2026-08-25.

**Platform:** All (shared Dart indexing code — no platform branching).

**Problem:**

For books whose EPUB has a real embedded TOC/navMap, the Contents list could
show front-matter items (e.g. "Information about this Book" and its
sub-items: Overview, About the Author, Further Links, License, Further
Information) rendered *after* several real chapters instead of grouped
together at their correct position — e.g. Education showed "First Principles"
and Chapters 1–4 before "Information about this Book" and "Foreword," when
the source EPUB has those two front-matter entries first. Reported live as
"front matter mixed in with chapters, totally scrambled" and "navigation is
erratic and inaccurate."

**Cause:**

In `commentary_research_library_service_epub_indexing.dart`, a heading found
inside a root's page was assigned
`sortOrder = rootSortOrder * 1000 + headingIndex` so it would sort after its
root. That scheme only avoids collisions when roots are spaced at least 1000
apart — but real-TOC-derived roots are numbered sequentially (0, 1, 2, ...),
so a heading's derived sortOrder landed directly on top of an unrelated
root's sortOrder. The row ordering comparator (`_compareNavigationDrafts`)
sorted by that colliding `sortOrder` first, so items with the same numeric
value from *different* parents ended up interleaved, with depth/parentId
string comparison arbitrarily deciding the tiebreak.

**Fix:**

Replaced the arithmetic sortOrder scheme with a proper depth-first tree walk
(`_orderNavigationEntriesHierarchically`) that renumbers every entry
sequentially in true document order, using the existing parent/child
relationships (which were always correct) rather than trying to keep
disjoint numeric ranges. Applies to all platforms since it's shared,
non-platform-specific Dart code.

**Live data repair (2026-08-25):** 97 titles in the live macOS
`eLibrary.db` had this exact collision. Backed up the database (SHA-256
verified), dry-ran a renumbering repair
(`tool/nav_sort_order_repair/run_nav_sort_order_repair.dart`) against a copy,
then applied it live: 14,190 navigation rows renumbered across 97 items,
`PRAGMA integrity_check` passed afterward. Verified visually on "The
Adventist Home" — front matter now groups correctly before Foreword/Section
1. Other devices' local databases (iOS, Android, Windows) were not part of
this repair and would need the same repair tool run against their own
`eLibrary.db` if they show the same symptom — check with the same collision
query in the repair script before assuming it's needed.

---

### Cross-reference popup ignored Bible Reader font size

**Area:** Bible Reader / Cross References

**Status:** Fixed

**Android status (2026-08-16):** Verified on Android. Cross-reference text followed both maximum and minimum Bible Reader font sizes without restarting. Long content remained scrollable, text did not clip or overlap, and tapping a reference navigated to the target verse.

The cross-reference popup/panel previously used a fixed/default font size instead of respecting the user's Bible Reader font-size setting.

This was corrected so cross-reference text now follows the current reader font size on supported platforms, with scrolling handling larger text as necessary.

---

### NT duplicate Greek/Strong's assignment import bug

**Area:** Bible text database / Greek / Strong's

**Status:** Fixed

A confirmed NT import defect caused surplus duplicate Greek/Strong's assignments.

Repair results:

* 3,893 surplus Greek/Strong's assignments cleared.
* All 373,501 token rows preserved.
* All English glosses preserved.
* Flagged verses reduced from 3,158 to 955.
* Repair verified as idempotent: second pass planned 0 changes.
* SQLite integrity check passed.
* Known visible defect in Revelation 1:1 was corrected.

The remaining 955 findings include split/joined Greek forms, tagging conventions, and possible textual variants and should **not** be bulk-modified without stronger evidence.

---

### eLibrary Setup screen: scrambled sections and unreadable/indeterminate progress bar

**Area:** eLibrary Setup (`lib/features/utilities/presentation/elibrary_setup_screen.dart`)

**Status:** Fixed

**Android status (2026-08-28):** Verified live on `SM S166V`. Confirmed via screenshots: the idle screen now shows one "eLibrary" card (indexing-pending/needs-attention banners, storage status, Index New/Changed Books, and collection selection all together), followed by a separate "Pioneer Books" card, followed by the collapsed "Advanced" section — no more interleaving. Started a real "Install Selected" download and watched the full-screen focal progress panel replace the whole screen (no scrolling) with a thick, high-contrast, determinate bar that visibly grew 3% → 9% → 14% as files were prepared. Cancelled the run cleanly; the app returned to the idle eLibrary card afterward with no corrupted state.

Two rounds of user-reported issues on this screen, both now addressed:

1. **Scrambled/interleaved layout.** The idle screen stacked indexing status (`LibraryIndexingPendingCard`, `LibraryNeedsAttentionCard`, `ELibraryStorageSection`) above the Pioneer Books card, which was itself sandwiched above the collection-selection card (`ELibraryInstallCollectionsSection`), forcing users to scroll past Pioneer to reach the actual eLibrary download controls. Fixed by merging the indexing/storage/collection-selection widgets into one outer "eLibrary" `Card` (their individual `Card` wrappers and duplicate headings were stripped so they read as one section with an internal `Divider`), and moving `CaptureClipperImportsSection` (Pioneer Books) to its own card immediately after — no longer interleaved.
2. **Progress bar unreadable, and indeterminate during indexing.** The bar was the default thin `LinearProgressIndicator` using theme-derived colors (brown accent vs. a near-black default track), and the indexing sub-phase of the running flow hardcoded `value: null`, producing a sliding/scanning indeterminate animation even though real completed/total counts were already being tracked (`_manualIndexCompleted`/`_manualIndexTotal`, populated by the same `indexLocalCatalogedEpubs` call used elsewhere on this screen). Fixed by adding `BigProgressBar` (`lib/features/utilities/presentation/big_progress_bar.dart`) — a thicker bar (22px) with a neutral, theme-accent-independent track color for reliable contrast — and wiring the indexing sub-phase of the full-screen running panel to the existing completed/total counters instead of forcing indeterminate.

The whole running/indexing state (both the official EGW download and the "Index New/Changed Books" quick action) also now replaces the screen with a single centered focal panel instead of being buried at the bottom of a long scrollable list, so progress is visible without scrolling. No download/indexing logic or sequencing was changed — this was UI/layout only.

**Follow-up round (2026-08-28): indeterminate indexing bar was still reachable from other entry points, plus a "flashing" indeterminate style.** After the fix above, live testing found the indexing progress bar was still indeterminate in places, for two separate reasons:

1. **Duplicate, unfixed "Index New/Changed Books" entry point.** `lib/features/utilities/presentation/library_root_setup_screen.dart` (reached via eLibrary Setup → **Manage Storage** → **Advanced Diagnostics**) has its own "Index New/Changed Books" button — same label as the one already fixed on the main eLibrary Setup screen, easy to confuse for the same control. It called `indexLocalCatalogedEpubs()` with **no `onProgress` callback at all** and rendered no bar, just static button text. A full audit of every call site of `indexLocalCatalogedEpubs()` and every "indexing" progress display in `lib/features/utilities/presentation/` and `lib/features/library/presentation/` turned up four real user-facing indexing entry points total: (a) auto-index after an eLibrary download (`elibrary_setup_screen.dart`'s `_RunningFocalPanel`), (b) the standalone "Index New/Changed Books" button on the merged eLibrary card (`ELibraryStorageSection`), (c) the legacy/duplicate `elibrary_download_screen.dart` screen's own indexing block (still using a bare `LinearProgressIndicator`), and (d) this `library_root_setup_screen.dart` button. All four now wire `onProgress` and render one new shared widget, `IndexingProgressStatus` (`lib/features/utilities/presentation/big_progress_bar.dart`), so a future fix or style change only needs to happen once. `elibrary_download_screen.dart`'s download-phase bar (a separate, always-indeterminate `const LinearProgressIndicator()`) was also switched to `BigProgressBar` with a real percentage for consistency, since it's the same screen.
2. **`BigProgressBar` fell back to Flutter's default indeterminate animation whenever `value` was null** (i.e. while the real total is still being discovered) — a segment sliding back and forth, which reads as "stuck scanning," not "making progress." `BigProgressBar` was changed from a `StatelessWidget` to a `StatefulWidget` that, when `value` is null, animates a simulated smooth fill easing up to 85% and holding there instead of Flutter's built-in indeterminate sweep; once a real value arrives it snaps to it. This applies everywhere `BigProgressBar` is used (download prep, indexing discovery, Pioneer install "Preparing…"), not just indexing.

**Pioneer Library download also had no progress bar at all.** `lib/features/library/presentation/import_pioneer_library_screen.dart`'s online (archive.org) install path tracked its own `_onlineProgress` (current/total) and rendered it only as plain text ("Downloading… (7 of 104)"); the shared `LibraryAcquisitionProgressView` bar underneath was bound to a *different*, never-updated `_progress` field, so it silently rendered nothing. Fixed by also updating `_progress` (as a `LibraryAcquisitionBatchProgress`) from the same `onProgress` callback, so the existing shared view picks up real data. `LibraryAcquisitionProgressView` itself (`lib/features/library/presentation/library_acquisition_progress_view.dart`, also used by "Download Ellen White Library") was upgraded from the default thin bar to `BigProgressBar` plus a bold percentage line, matching the eLibrary download style.

**Android verification (2026-08-28, `SM S166V`):** Rebuilt and relaunched after each round of fixes.
* Pioneer online install: watched a real "Install Pioneer Library" run show a thick, high-contrast, determinate bar with bold percentage ("20%", "Man's Nature and Destiny (21 of 104)") — previously text-only.
* eLibrary download phase: unaffected, still correct (confirmed working in the prior round, re-confirmed this round).
* Indexing via the previously-unfixed `library_root_setup_screen.dart` button: triggered a real run against 107 genuinely-unindexed books and watched the bar and bold percentage climb smoothly and continuously (0% → 23% → 67% → 99%, "Indexing N of 107" updating each frame) — this is the entry point that was completely unwired before this round, now confirmed fixed live with real data, using the same shared `IndexingProgressStatus` widget as every other entry point.
* The simulated-growth replacement for indeterminate `BigProgressBar` states was verified by code review and via the same live runs (the "discovering candidates" window was too brief to reliably screenshot mid-animation on this device/library size, but the implementation is a small, self-contained `AnimationController` easing the bar toward 85% — the same mechanism is exercised, and visually inspected as non-flashing, wherever `value` is momentarily null).

**macOS verification (2026-08-28, native desktop build, `flutter run -d macos --release`):** Rebuilt and click-driven through the running app (via `cliclick` + synthetic scroll-wheel events + screenshots), exercising all three checklist items live:
* eLibrary download phase: selected the small "EGW Misc Collections" collection (15 files) and tapped Install Selected. The full-screen focal panel showed the thick, high-contrast, determinate `BigProgressBar` with bold percentage text climbing in real frames (7% → 27%, "N of 15 prepared", live filenames), then completed and auto-indexed cleanly with no leftover indeterminate state.
* Indexing entry points: confirmed present with `IndexingProgressStatus` wiring at both (b) the eLibrary card's own "Index New/Changed Books" and (d) `library_root_setup_screen.dart`'s Advanced Diagnostics "Index New/Changed Books" — both ran end-to-end against an already-fully-indexed library (0 new candidates) and completed instantly with no crash or stale indeterminate bar, matching Android's finding that this window is too brief to screenshot mid-animation when there's nothing to index. Not independently re-confirmed with a genuinely large unindexed batch on macOS (Android already did this with 107 real books); code path is identical Dart, no platform branching.
* Legacy `elibrary_download_screen.dart` (via Utilities → Download Books → Start Download): reached and exercised; initially blocked by an unrelated pre-existing "Legacy Library Root" / "Library Root Folder is not selected" state on this machine (the known macOS security-scoped-bookmark-reset issue documented above in this file's CLAUDE.md context) — resolved by confirming the existing folder via Library Root Setup → "Use this folder as Library Root" (non-destructive, no file moves), after which the screen was reachable again.
* Pioneer Library online (archive.org) install: from Utilities → Set Up My Library → Pioneer Library → **Update Verified Pioneer Books** (the archive.org path, `import_pioneer_library_screen.dart`'s `_installOnline`, distinct from the local-folder import path) — confirmed a real run showing the determinate `BigProgressBar` with bold percentage and live titles ("Downloading The Law of Moses (1 of 104)" → 1% → "Downloading The Sanctuary (2 of 104)" → 2% → 13%), previously plain-text-only per the bug description above. Cancelled cleanly mid-run ("Installation cancelled. Your existing Library was not changed.") once confirmed, to avoid an unnecessary full 104-title pull against archive.org.

No regressions or indeterminate/unreadable bars found on macOS. All three checklist items (download bar, four indexing entry points, Pioneer bar) confirmed working with the same shared Dart widgets as Android, as expected since there is no platform-specific branching in this code.

**iOS verification (2026-08-28):** Builds succeeded on both wireless devices (iPhone 15 Plus, iPad Pro 12.9"), but live UI verification is blocked pending physical device interaction that can't be done remotely:
* iPhone install initially failed with a code-signing error (`objective_c.framework`/`sqlite3.framework` had invalid/adhoc signatures inside the local build output at `build/ios/iphoneos/Runner.app`) — a stale local build-artifact issue unrelated to this fix, worked around by re-signing those frameworks and the app bundle directly (no source changes). After that, install succeeded via `devicectl`, but launch is refused because **the device is locked** (`FBSOpenApplicationServiceErrorDomain`/"Locked" — iOS won't launch apps on a locked screen, confirmed via `xcrun devicectl device process launch`).
* iPad: `flutter run --release` installed and launched the app successfully (confirmed via Xcode's Devices window, which also showed the previously-installed `com.deanbowen.bibleAppMac` v50 already present, and a fresh screenshot taken through Xcode's "Take Screenshot" device action). The app is sitting on a pre-existing "Legacy data found" migration prompt (unrelated to this fix — asks how to handle old tags/notes/bookmarks from an older app version) that requires a real tap to get past; no touch-injection tool is available for a physical iOS device from this environment.

Both are one tap/unlock away from being verifiable the same way macOS was. Not yet re-confirmed live on iOS — do not consider this closed for iOS until the four indexing entry points, the download bar, and the Pioneer bar are actually seen determinate on-device.

Windows and Linux desktop builds could not be attempted in this environment at all: both require compiling natively on that OS (no cross-compilation from macOS), and only macOS, iOS, and Android hardware/toolchains are available here.

---

## Maintenance Instructions

When updating this file:

* Add newly confirmed bugs under **Open Bugs**.
* Put uncertain or unreproduced problems under **Verification Needed**.
* Move resolved bugs to **Fixed** rather than deleting them.
* Record enough reproduction detail that another developer or Codex session can understand the issue.
* Avoid changing unrelated code simply because an item appears here.
* Verify a bug still exists before attempting a repair whenever practical.
* Prefer narrowly targeted fixes over broad refactors during this testing phase.
