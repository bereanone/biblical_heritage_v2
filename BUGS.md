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

## Verification Needed

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

### eLibrary Contents showing no nesting or current-location highlight for EGW official EPUBs (Early Writings, etc.)

**Area:** eLibrary / canonical reader Contents dialog

**Status:** Partially fixed, 2026-08-27. Reported live on Android as "no nested TOC in EW, nor can I see on the TOC any highlighted indication of my current location."

**Real root cause (this took most of the investigation to pin down):** official EGW EPUB downloads like Early Writings don't actually use `library_book_reader_screen.dart` / `library_contents_popup.dart` at all — `supportsCanonicalEpubReader` routes them into a completely separate reader, `CanonicalLibraryReaderScreen` (`canonical_library_reader.dart`), built on its own storage table (`library_document_blocks`), independent of `library_navigation_items`. All of the `library_navigation_items` work below (parent-link bug, sort-order repair) is real and still worth having — it's what the *legacy* reader uses, and canonical prep still falls back to it when a book isn't (yet) eligible — but it isn't what actually renders Early Writings' Contents. That dialog (`_openContents` in `canonical_library_reader.dart`) was just `headings.map((h) => ListTile(title: Text(h.plainText)))` — a flat list, no depth, no indication of current position, by omission rather than data corruption.

**Fix:** `_openContents` now indents each heading by its `heading_role` (h2/'chapter' → depth 0, h3/'section' → depth 1, h4-h6/'minor' → depth 2) and highlights whichever heading the current reading position falls under (bold, colored text, left accent border) — the same visual treatment the legacy popup already had. Verified live on the device: within-chapter sub-headings ("Texts Referred to on Preceding Page" under "My First Vision") now nest correctly.

**Known remaining gap:** `heading_role` only reflects structure *within* a single spine file (from that file's own `<h1>`–`<h6>` tags). It has no idea that "My First Vision," "Subsequent Visions," etc. are conceptually children of the "Experience and Views" *section* — each is its own spine file, and the real parent/child relationship for that only exists in `library_navigation_items` (which this reader doesn't consult). So EW's top-level chapter list is complete and now internally-nested, but the top-level items don't yet group under their section headers the way they did in the legacy reader's TOC. Closing that gap means cross-referencing `library_navigation_items`'s (now-correct) parent/child tree with the canonical `library_document_blocks` headings — a real follow-up, not something to guess at further without your input on priority.

Also inconsistent: a few sub-headings detected by the canonicalizer's *heuristic* classifier (not a real `<h#>` tag — e.g. "About the Author," "Further Links" inside `aboutbook.xhtml`) get `heading_role: 'chapter'` instead of `'section'`, so they don't indent even though they're conceptually nested. Same underlying limitation, not something this pass fixed.

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

## Maintenance Instructions

When updating this file:

* Add newly confirmed bugs under **Open Bugs**.
* Put uncertain or unreproduced problems under **Verification Needed**.
* Move resolved bugs to **Fixed** rather than deleting them.
* Record enough reproduction detail that another developer or Codex session can understand the issue.
* Avoid changing unrelated code simply because an item appears here.
* Verify a bug still exists before attempting a repair whenever practical.
* Prefer narrowly targeted fixes over broad refactors during this testing phase.
