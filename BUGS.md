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
