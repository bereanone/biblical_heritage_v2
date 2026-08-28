# Progress Notes — 2026-08-27

**Worked on the "no nested TOC in EW, no current-location highlight" bug you reported this
morning.** This took a lot longer than expected because my first fix — while real — turned out
not to be the thing you were actually looking at. Full honest account below.

## What I fixed first (real bug, but not the one you were seeing)

Found and fixed a genuine parser bug in the *legacy* eLibrary reader (`library_book_reader_screen.dart`
/ `library_contents_popup.dart`): it estimated how deeply each TOC entry was nested but never
linked a nested entry to its parent, so any book with real multi-level nesting displayed flat.
Fixed the parser, wrote a repair tool for already-imported data, backed up and repaired both the
Mac and Android databases live (details in `BUGS.md`). Also found and actually fixed last night's
sort-order repair, which had never really reached Android (the "android report" was a mislabeled
copy of the Mac one).

**Then I went to go verify it on your phone and Early Writings still looked exactly the same.**

## The actual problem

Early Writings — and every other officially-downloaded EGW EPUB — doesn't use that legacy reader
at all. There's a second, separate reader (`canonical_library_reader.dart`) that official EGW
EPUBs get routed into automatically, built on a completely different storage table
(`library_document_blocks`) with no connection to the `library_navigation_items` table the legacy
reader (and my first fix) uses. That reader's "Contents" button was just a flat, unstyled list —
no nesting, no current-position indicator, by omission, not corruption. This is why nothing I'd
already fixed showed up: right screen, wrong bug.

Tracking this down required getting a live debug session onto your Android device (`flutter run`,
not `flutter install` — no data lost) and instrumenting the actual code path to see what was
really rendering, since static reading of the code kept pointing at the (correct, but unused for
this book) legacy reader.

**Fixed:** the canonical reader's Contents dialog now indents headings by their heading level
(chapter/section/minor) and highlights whichever heading the current reading position falls
under — bold, colored, left border, matching the legacy reader's existing highlight style.
Verified live on your phone: sub-headings within a chapter now nest correctly.

**Not fully fixed:** the canonical reader has no concept of "these separate chapter files belong
under this section" (e.g. Early Writings' "My First Vision," "Subsequent Visions," etc. as
children of "Experience and Views") — that relationship only lives in `library_navigation_items`
(which I did fix), and the canonical reader doesn't consult it. So EW's Contents is meaningfully
better (real nesting where there was none, current-position highlighting where there was none)
but the top-level chapter list is still flatter than the original book's real structure. Closing
that gap means teaching the canonical reader to cross-reference the legacy navigation tree —
a real follow-up, not something I want to guess further at without your steer on priority.

**Left uncommitted,** for your review before commit/push, including the earlier legacy-reader fix
(genuinely correct and still worth keeping — it's what canonical prep falls back to for anything
not yet eligible for the canonical pipeline).

## Safety net

Backups for today's `library_navigation_items` repair: `recovery_backups/20260827_nav_parent_link_repair/`
(macOS) and `recovery_backups/20260827_android_nav_repair/` (Android's pre-repair database,
pulled before any changes). Both SHA-256 verified. No backups were stored on the phone itself —
everything pulled from the device stayed on this Mac; the phone's own storage was only ever
briefly touched to push the repaired file back into place.

---

# Progress Notes — 2026-08-25

**Today's task is done.** Read this first from any session (phone or desktop) to get caught
up. Full technical detail is in `FRONT_MATTER_TOC_AUDIT_2026-08-25.md` — this is the short
version for checking in on the road.

## What got done today

**The big one: front matter / chapter-start bug, fixed across the whole library.**
345+ of your 454 EPUB-backed titles (EGW books, pamphlets, periodicals, devotionals, and
Pioneer-author books) had real chapters mislabeled as "front matter" in the database, which is
why some books opened straight to "Information about this Book" instead of chapter 1. Root
cause: an import-time bug in `pioneer_text_import_service.dart`. Built a proper, re-runnable
repair tool (not a one-off SQL fix), tested it carefully in dry-run mode against a copy first
— which caught two real bugs in the repair logic itself before anything touched production —
then applied it to the live database.

**Results:**
- 446 titles corrected, 22,676 individual chapter entries fixed.
- 8 pamphlets skipped on purpose (their EPUB files genuinely have no chapter content at all —
  nothing to fix, needs your judgment call, not urgent — full list in the audit file).
- Database integrity verified after the fact (`PRAGMA integrity_check` → ok).
- Spot-checked several titles directly against the database, including the two trickiest
  cases found along the way (Christ in His Sanctuary, and Mind/Character/Personality vol. 2
  which has a "Section header + nested chapters" structure that needed a smarter fix).

**Also done:**
- TOC current-position highlight is now much more visible — stronger background tint plus a
  colored left accent bar on the selected row, so it's obvious where you are while scrolling.
- Confirmed TOC nesting itself was never affected by any of this (the repair only touches
  front-matter flags, never the tree structure).

**Important follow-up, fixed:** the original fix only corrected the existing database rows —
the actual import code that caused this had the same bug and would have reproduced it on any
future import (a new title, a re-download, etc.). Found and fixed that too:
`_firstMeaningfulSectionIndex` in `pioneer_text_import_service.dart` now uses the same
front-matter-label check as the repair tool, so future imports won't recreate this problem.
Verified against the existing import test suite (38 tests) — all pass.

**Also caught by running the full test suite afterward:** one of today's fixes had a real bug
— a fallback file lookup could throw instead of gracefully saying "not found" in an edge case,
which broke 4 existing tests. Fixed, then re-ran everything relevant (71 tests across the
areas touched today, including the reader screens) — all pass, and `flutter analyze` is clean
across the whole `lib/` folder.

**Not done, and not urgent:** couldn't get a live visual screenshot of the app to eyeball
the fix in the running UI — the dev build's window wasn't grabbing focus in this environment
(unrelated to the fix itself; worth just opening the app yourself when you're back to confirm
visually). The database-level verification plus the full test suite passing is solid, but a
quick look when you're home would be good confirmation.

## Safety net

Full backup of `eLibrary.db` taken and SHA-256 verified before any of today's writes:
`recovery_backups/20260825_front_matter_audit/eLibrary.db.pre-front-matter-repair.bak`.
If anything looks wrong, that file can be copied back over the live database (app fully quit
first) to undo everything from today.

## If you're checking in from your phone

Ask what the status is and I'll walk you through it in plain language, or dig into any
specific title you're curious about. **Resolved:** Dean decided to leave the 8 pamphlets as-is — they're short enough that opening to
the TOC/About page instead of a detected chapter 1 isn't worth chasing a re-download over.

---

# Progress Notes — 2026-08-25 (evening) — pre-release platform sweep

Same-day follow-up session: verifying the TOC scroll fix + a full bug-list sweep across iOS,
Android, macOS, and Windows ahead of a store release. Full detail in the chat transcript and
`BUGS.md`; short version here.

## The big find: a second, separate TOC bug (not the same one as above)

While spot-checking on macOS, found the Contents list showing front-matter items (Overview,
About the Author, license text) rendered *after* several real chapters instead of grouped at
their correct spot — e.g. Education showed "First Principles" and Chapters 1-4 before
"Information about this Book." Root cause: a numbering scheme in the EPUB indexer
(`commentary_research_library_service_epub_indexing.dart`) that assigned headings inside a
page a sort position that could collide with an unrelated chapter's position, scrambling the
display order. Fixed the code (proper tree-walk renumbering instead of arithmetic guessing —
this is shared code, so the fix applies to every platform), then found it wasn't isolated to
one book: **97 titles** in the live macOS library had this exact collision.

Repaired it the same way as this morning's front-matter fix: backed up the database (SHA-256
verified, in `recovery_backups/20260825_nav_sort_order_repair/`), dry-ran the repair against a
copy, then applied it live — 14,190 navigation rows renumbered, integrity check passed.
Verified visually afterward on "The Adventist Home."

**Not yet applied to your other devices' local databases** (iOS, Android, Windows each keep
their own separate SQLite file, same as always) — the code fix means any *fresh* install/index
generates correct data automatically, but a device with already-imported content would need the
same repair tool (`tool/nav_sort_order_repair/`) run against its own database if it shows the
same symptom.

## Windows: found and fixed a startup crash unrelated to the above

Windows builds were crashing at launch with "Bad state: databaseFactory not initialized" —
100% reproducible, blocking eLibrary (and everything else needing the database) entirely on
Windows. One-line root cause in `sandbox_bootstrap.dart`: the code read a value before ever
assigning it, which throws on Windows specifically (macOS/Linux never hit it because their
native database plugin auto-populates that value first). Fixed and verified end-to-end on the
Parallels Windows VM — rebuilt, relaunched, confirmed it reaches real app functionality
(Bible reader, cross-references) rather than the crash screen.

## TOC scroll-to-chapter fix (the original ask)

Verified via the full automated test suite (976 tests, including 2 new tests written
specifically for this fix) and by confirming the fix is shared Dart code with no
platform-specific branching, so it should behave identically on iOS/Android/macOS/Windows.
Did not get a clean live click-through confirmation on macOS this pass — my screen automation
kept colliding with a VS Code window sharing the same screen region as the test build, so by
mutual agreement we relied on the test suite instead of more risky clicking.

## Platform status

- **macOS:** Real device, live-tested. TOC ordering bug found and fixed live. Cross-reference
  and reader screens confirmed working.
- **Windows (Parallels VM):** Crash found and fixed; confirmed working end-to-end after rebuild.
  Note: had to fix a database-open permission/attribute snag from the initial file copy too —
  unrelated to the app itself, just how the build folder got created.
- **Android (real device, USB):** With your OK, uninstalled/reinstalled today's debug build
  (your data wasn't lost — Android keeps the actual files in a separate folder from the app
  itself; reconnecting the library folder restored everything). Downloaded and indexed 423 EGW
  books fresh through the in-app flow, confirming that pipeline works end-to-end. 6 books came
  back unreadable and got set aside automatically (originals preserved) — worth a look when
  you have a minute, not urgent. This device's data still has the *pre-fix* sort-order bug
  since it was built from the same debug binary as before the fix — a future real reinstall
  would generate it correctly.
- **iOS:** Release build compiles and code-signs cleanly. Live install to your iPhone (wireless)
  failed at the last step — most likely just needs the phone unlocked/awake for a wireless
  deploy to complete; didn't push further since I can't unlock your phone remotely.

## Also swept from the known-issues list

- Hashtag category retention, notification suppression, search result count/bolding/ref-codes
  (all previously verified fixed on Android): confirmed by code review to be shared,
  non-platform-specific logic — should already be correct everywhere.
- iPhone "local search reverted to old behavior": looked for the old book-scoped search modal
  in the code — it's fully gone, no trace. Most likely you were on a build that predated an
  earlier fix; today's build doesn't have the old code path at all.
- iPhone bottom toolbar "altered": real, but intentional — a phone-width reorder from Aug 11
  moved the autoscroll button earlier in the row since it's used more than the day/night
  toggle. Nothing removed, just a reachability change. Flagging in case you want it reverted.
- iPad eLibrary search showing far fewer results than Mac: the underlying count-query bug was
  already fixed (verified on Android, confirmed platform-agnostic in code), but each device's
  search index is separate and local — an iPad that hasn't had "Index New/Changed Books" run
  won't show results for anything it hasn't indexed yet, independent of any code bug.
- Two copies of the app on one iPhone: a device-management thing, not a code issue — nothing to
  fix in the app itself.

## Left uncommitted, as requested

Everything from today (this morning's front-matter work plus tonight's fixes) is still sitting
as uncommitted working-tree changes, per your instruction, for your review before commit/push.

## Safety nets

- This morning's backup: `recovery_backups/20260825_front_matter_audit/`
- Tonight's backup: `recovery_backups/20260825_nav_sort_order_repair/`
Both are full pre-change copies of `eLibrary.db`, SHA-256 verified.
