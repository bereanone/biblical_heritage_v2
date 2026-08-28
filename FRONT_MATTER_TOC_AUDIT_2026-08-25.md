# Front Matter / TOC Audit — 2026-08-25

**Status: DONE.** The repair ran and is applied to the live database. This file is the
handoff doc for this task — read it first if you're picking this up from a phone session or
a fresh Claude context.

## Goal (from Dean, 2026-08-25)

1. Review all eLibrary DB files (EGW + Pioneer) and locate where real front matter ends and
   true chapters begin.
2. Every book should open cleanly to non-front-matter content (no more landing on "Information
   about this Book" when there's no saved reading position).
3. TOC should be nested (chapters/sub-chapters), which mostly already works.
4. The current-position highlight in the Contents panel should have visibly higher contrast
   while scrolling.
5. Do this autonomously today — Dean is on the road and reachable only async via his phone app.

## Backup taken before any writes

- `recovery_backups/20260825_front_matter_audit/eLibrary.db.pre-front-matter-repair.bak`
- SHA-256 verified to match the live `eLibrary.db` at backup time (checkpointed WAL first, so
  it's a clean, consistent snapshot — not a live-WAL copy).
- If anything looks wrong after the repair runs, this file can be copied back over
  `~/Library/Containers/com.deanbowen.bibleAppMac/Data/Documents/BiblicalHeritage/v2/eLibrary.db`
  (with the app fully quit first) to fully undo everything below.

## Root cause (confirmed from last night's session)

`lib/features/utilities/data/pioneer_text_import_service.dart` (`_firstMeaningfulSectionIndex`,
~line 4788) decides where a book's real content starts at **import time**, by scanning each
section's *then-extracted* paragraph text with `libraryIsMeaningfulReadingSection`
(`lib/features/library/data/library_section_heuristics.dart`). Every section *before* the first
one judged "meaningful" gets permanently written as `is_front_matter = 1` in
`library_navigation_items`.

For a real chunk of the library, that import-time paragraph extraction came back empty/too-short
for early chapters (confirmed for "Christ in His Sanctuary": `library_text_blocks` has zero rows
for `content00.xhtml`, even though the live EPUB file has ~40KB of real chapter text in it, e.g.
"The Sanctuary Truth"). So real chapters got flagged as front matter, and the book defaults open
to whatever's left (the About page).

**Scale, measured 2026-08-25 against the live DB:**
- 345 of 460 library items with navigation data have at least one `content_kind='toc'`,
  `depth<=1` row incorrectly flagged `is_front_matter=1` whose href isn't a real front-matter
  file (aboutbook/cover/titlepage/copyright/toc).
- Heaviest in periodicals/devotionals (thousands of affected rows per title — every daily entry
  got swept in), but present in ordinary books too (Christ in His Sanctuary: 10 rows, even Early
  Writings: 7 rows).
- Confirmed via direct inspection this is a **flagging bug, not a content-loss bug** — the real
  EPUB files have the actual chapter text; the reader just wasn't told where to start.

## Import pipeline itself — also fixed

Fixing the database rows alone would only have masked the symptom: the next import of a new
title, or a re-download of an existing one, would have hit the exact same bug and produced the
exact same wrong result. So the root cause was fixed too, not just the data.

`_firstMeaningfulSectionIndex` in `lib/features/utilities/data/pioneer_text_import_service.dart`
(~line 4788) is the actual import-time function that decides where a book's front matter ends —
it's called once per book during import, and its result gets written straight into
`library_navigation_items.is_front_matter` for every section. It had the identical bug as
"the About-page trap" described below: it called `libraryIsMeaningfulReadingSection` directly,
with no check for whether a section's *label* (not just its content) marks it as front matter.
A page titled "Information about this Book" — full of real, substantial prose — could pass the
content check and get treated as the book's first real chapter, corrupting everything after it.

Fixed by adding the same `libraryIsFrontMatterOpeningLabel` gate used in the repair tool,
directly in the import code. Verified: `pioneer_text_import_service_test.dart` (30 tests,
including the ones specifically asserting front-matter behavior) and
`pioneer_text_import_screen_test.dart` (8 tests) both pass, `flutter analyze` is clean across
`lib/`. The "section-divider-with-nested-chapters" bug (the other one described below) does
*not* apply to the import code the same way — `document.sections` there is already a flat,
correctly-spine-ordered list covering every heading at every level, not scoped to top-level
entries only, so it never had that particular blind spot; that one was specific to an early,
since-corrected draft of the repair tool itself.

## Repair strategy

Don't try to patch history in the old import-time extraction. Instead: for every EPUB-backed
library item, re-derive "where does real content start" using the **live, already-fixed EPUB
parser** (`CommentaryResearchLibraryService.loadBookSections`, proven correct this session for
Early Writings and confirmed readable for Christ in His Sanctuary), re-run the same
`libraryIsMeaningfulReadingSection` heuristic against that live-parsed content, and correct
`is_front_matter` / `is_body_start` on the matching `library_navigation_items` rows by href.

Written as a proper, reviewable repair service (following the existing
`canonical_epub_generation_repair_service.dart` pattern in this repo), not a one-off SQL blast,
so it's testable and safe to re-run.

## Progress log

- [x] Backup taken and verified.
- [x] Root cause confirmed and scale measured.
- [x] Repair tool implemented — `tool/front_matter_repair/` (two files: a self-contained pure-Dart
      EPUB paragraph extractor, and the repair script itself). Not a one-off SQL blast; it's
      re-runnable and was iterated on with real dry-run data before touching production.
- [x] Dry-run report generated and reviewed before any write — this caught **two real bugs** in
      the repair logic itself (see "Bugs caught during dry-run testing" below), both fixed and
      re-validated before applying anything.
- [x] Repair applied to the live database and spot-checked against a sample across EGW books,
      pamphlets, periodicals, devotionals, and Pioneer author titles.
- [x] TOC nesting unaffected — the repair only ever writes `is_front_matter`/`is_body_start`,
      never touches `depth`/`parent_id`/`sort_order`, so the nesting logic
      (`buildLibraryNavigationTree`) was never in scope for this bug or this fix.
- [x] Contents-panel current-position highlight contrast increased (background tint alpha
      0.16 → 0.34, plus a new 4px primary-color left accent border on the selected row) —
      `library_book_reader_screen_helpers.dart` and `library_contents_popup.dart`.
- [x] Final results below.

## Final results (applied 2026-08-25)

Full machine-readable report: `tool/audits/front_matter_repair_report_2026-08-25.json`.

- **454** EPUB-backed library items scanned (every EGW and Pioneer-author title with navigation
  data).
- **446** corrected — real chapters that were wrongly marked front matter are now marked
  correctly, and each book's actual first chapter is now flagged as its body-start.
- **22,676** individual navigation rows corrected across those 446 books.
- **8** pamphlets skipped on purpose — their EPUB files genuinely contain no chapter file at all
  (just cover/titlepage/toc/about), so there's nothing to correctly detect as "the first
  chapter." These are unchanged from before (not made worse) and need a human decision, not an
  algorithm — see the list below.
- **0** titles had errors, missing files, or unreadable EPUBs — everything resolved cleanly.

### The 8 pamphlets that need a manual decision

Their source EPUBs have no real chapter content — only cover/titlepage/toc/about. Either the
source download is incomplete, or (for the "Special Testimony"/"Testimony for the Church" ones)
the actual text may only exist elsewhere (a different edition, or as a stored-text-blocks import)
and this particular EPUB copy was never meant to carry the body text itself. Worth a look next
time you're at a computer, not urgent:

- Knowing and Obeying the Lord (`..._pamphlets_en_ph045_epub`)
- Special Testimony Relative to Tract and Missionary Societies and Our Preachers (`..._ph083_epub`)
- Special Testimony on Canvassing for Christ's Object Lessons (`..._ph153_epub`)
- Special Testimony to the Managers and Workers in our Institutions (`..._ph088_epub`)
- TESTIMONY FOR THE CHURCH. — No. 14 (`..._t14_epub`)
- TESTIMONY FOR THE CHURCH. — No. 15 (`..._t15_epub`)
- TESTIMONY FOR THE CHURCH. — No. 16 (`..._t16_epub`)
- The Liquor Traffic Working Counter to Christ (`..._ph141_epub`)

**Decision (Dean, 2026-08-25, from home):** Leave as-is. These are short pamphlets — worst case
they open to the TOC/About page instead of a detected chapter 1, which isn't worth chasing a
re-download over. No further action planned unless a full-length title is ever found in the
same state.

## Bugs caught during dry-run testing (fixed before applying anything live)

Both of these were caught specifically *because* the dry-run-on-a-copy step was there — real
argument for keeping that workflow for anything like this in the future.

1. **The About-page trap.** The very first dry run picked "Information about this Book" itself
   as a book's first chapter, because it's full of real substantial prose and easily passed the
   plain content-length heuristic. Fixed by gating on the same front-matter *label* check the
   reader itself already uses (`libraryIsFrontMatterOpeningLabel`,
   `library_book_reader_screen.dart`'s `_firstRealContentNavigationHref`) before ever looking at
   paragraph length — a page titled "Information about this Book" or "Preface" is disqualified
   outright, no matter how much text it has.
2. **`resolveExistingAssetFile` (from last night's fix) could throw instead of returning null.**
   Running the existing test suite after today's repair caught this: when the primary file
   didn't exist (a normal, expected case this method is explicitly meant to handle) and the
   `defaultAppLibraryRootPath()` fallback lookup itself failed for any reason — e.g.
   `path_provider`'s platform channel not being available in a test/unit context — the method
   let that exception propagate instead of treating it the same as "no fallback found." Broke 4
   tests in `canonical_epub_generation_repair_service_test.dart` that legitimately test the
   missing-file case. Fixed by wrapping that one call in try/catch — same conservative "return
   null" result either way. Full test suite (71 tests across the areas touched today, plus the
   reader/canonical-reader suites) passes clean after the fix.
3. **Section-divider pages with real chapters nested underneath.** Several books (e.g. "Mind,
   Character, and Personality, vol. 2") structure themselves as a "Section" header — a near-empty
   divider page with just a heading and a page-break marker — followed by several real numbered
   chapters nested one level deeper. The first version of the repair only looked at top-level nav
   rows and their own paragraph text, so it saw the empty divider, found nothing, and gave up —
   leaving the *real* nested chapters still wrongly marked as front matter too. Fixed by
   rebuilding classification around the EPUB's actual spine order (read straight from its OPF
   manifest, not the nav tree's depth/sort_order) — every nav row referencing a given spine file,
   at any depth, gets that file's classification. This also fixed the divider pages themselves:
   they're correctly `is_front_matter=0` now (they're real structural markers, not front matter),
   they just don't get the `is_body_start` flag since they have no readable text of their own.

## Notes / things to watch for a resuming session

- The book-reader's "canonical" pipeline (`canonical_library_reader.dart`) is a second, newer
  reading pipeline separate from the legacy one — most of the library still reads through legacy.
  Don't let this repair accidentally activate canonical routing for titles that aren't already
  using it (that caused a real regression last night for Early Writings: nested TOC and the
  highlight disappeared because that pipeline doesn't have those features yet). This repair only
  touches `library_navigation_items` flags, not canonicalization, so it should be unaffected —
  but worth re-checking if anything routes oddly after this.
- macOS app must be fully quit before any direct sqlite3 writes to avoid WAL conflicts.
