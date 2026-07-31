# Library title metadata audit — 2026-07-30

Database inspected read-only:
`~/Documents/Databases/eLibrary.db`

## Result

The audit found **11 unique malformed title rows** among non-deleted library
items:

- 10 rows contain literal `&quot;` entity text.
- 1 additional row repeats the same title three times (`The Daily`).
- No embedded HTML tags or unmatched literal quote rows were found.
- The six SQL matches for suspicious trailing punctuation were false positives
  caused by the semicolon at the end of `&quot;`.
- Four short `MR###` rows are valid Manuscript Release identifiers and already
  have an established canonical display-title path; they are not malformed
  missing-cover initials.

## Entity-encoded rows

All ten are `pioneer_epub_import` rows and are classified as **import/parser
defects requiring renderer normalization for already-imported data**:

1. Come Out of Her, My People — Charles Fitch
2. Due Process of Law and The Divine Right of Dissent — A. T. Jones
3. Note on South African Missionary — A. T. Jones
4. What Think Ye of Christ? — E. J. Waggoner
5. Appeal from the U. S. Supreme Court Decision Making this “A Christian
   Nation” — A. T. Jones
6. Miller's Reply to Stuart's “Hints on the Interpretation of Prophecy” —
   William Miller
7. Review of the Two Sermons of Rev. R. G. Baird on the “Christian Sabbath” —
   J. H. Waggoner
8. The “Abiding Sabbath” and the “Lord's Day” — A. T. Jones
9. The “Christian” Demand for War — E. J. Waggoner
10. The Puritan Sabbath for “Physical Rest” [Australian] — A. T. Jones

The source EPUB uses valid XML entities. The Pioneer folder inventory parser
previously stripped tags but decoded only `&amp;`, `&lt;`, and `&gt;`; it
stored the remaining entity syntax in `library_items.title`.

## Repeated-title row

`"The Daily" "The Daily" The Daily` — W. W. Prescott is classified as a
**source metadata defect plus renderer normalization need**. Inspection of the
actual source EPUB's `OPS/epb.opf` proves that its `dc:title` contains the title
three times, separated by `&#13;`. The database accurately retained that bad
source value.

## Correction policy

The existing database was not rewritten. A centralized UI display normalizer
corrects all eleven rows at render time. The Pioneer inventory parser now uses
the same normalization for future imports, preventing recurrence without
altering source EPUBs.
