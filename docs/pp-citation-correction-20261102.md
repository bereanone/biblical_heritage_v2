# PP historical Bible-citation correction — 2026-11-02

The PP reading candidate uses the 1913 historical transcription, checked against
1890 and 1913 printed scans. Published PP page/paragraph identities are comparison
anchors; the collected JSON is a local extraction, not an official publisher JSON.
Originals remain unchanged. This is preparation work, not an installed release.

## Shared correction

Speech, link recognition, and verse popup lookup now share one book-alias table.
This closes historical abbreviation gaps such as Eze., Neh., Cant., Kgs., and Chr.
Chapter ranges, Roman numerals, single-chapter books, and chapter continuations
after Revised Version or margin annotations retain their intended targets.
Speech expands names and ranges, including “chapter”, “verses”, and “through”,
without rewriting the printed citation. PP paragraph reference labels are silent.
Unknown syntax and verse suffixes remain fail-closed; comma-separated numbered
books cannot add a verse to the preceding passage.

## Validation

- 21 focused tests passed, including the actual historical PP footnote corpus,
  66-book/1,189-chapter verse limits, popup interactions, existing LOF range cases,
  and the previous date rules (all 12 months).
- Import/navigation checks: 80 additional checks passed, including an actual
  PP candidate import in a disposable database. All 2,228 body blocks retain
  published codes. The private EPUB has 985 explicit citation links.
- Canonicalizer version 44 refreshes existing managed-book citation nodes; stable
  text and identity reconciliation remain covered by the generation checks.
- Candidate source audit: 985 detected citations; no unlinked numeric
  chapter-and-verse references; displayed citation text preserved.
- Source variants: 579 lexical comparisons adjudicated; eight scan-supported
  transcription repairs. Historical spellings and edition differences retained.
- Formatting: removed plain-text italic delimiters from 47 candidate paragraphs,
  preserving XHTML emphasis and poem line breaks.
- EPUBCheck: zero errors; the app-specific citation URI produces the expected
  unregistered-scheme warnings. This is not a distribution-ready EPUB.
- Narration: private local SC3 production and word alignment, no automatic
  publication. ASR results are review flags, not proof of audible correctness.
- Remaining book work: punctuation/formatting review, original illustration
  restoration, final cover/front matter, audio attachment and installed-reader checks,
  listening review, in-place update tests and physical-device verification.

## Platform evidence

| Platform | Shared citation source | Installed PP/display/audio proof |
| --- | --- | --- |
| Mac | Focused checks passed | Not installed or verified |
| iPhone | Same Flutter implementation | Not installed or verified |
| iPad | Same Flutter implementation | Not installed or verified |
| Android | Same Flutter implementation | Not installed or verified |
| Watch | Phone companion playback; no independent book reader | Not verified |

No personal database, note, highlight, bookmark, setting, reading position, saved
voice profile, or installed recording was changed. No store submission performed.
The production scan and raw narration stay on PurpleSSD; large data is excluded
from Git. Existing verified library/audio backup bases are not duplicated.
