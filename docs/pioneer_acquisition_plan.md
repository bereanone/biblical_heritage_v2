# Pioneer Authors Acquisition Plan

Status: finalized 2026-07-08, based on the EGW Writings-only EPUB audit
(`tool/audits/egw_pioneer_epub_availability.csv` / `.json`).

## Audit result (summary)

- 581 Pioneer Authors book rows on EGW Writings (Adventist Pioneer Library →
  Pioneer Authors, folder 16; 31 authors; 361 unique book codes).
- Only 5 unique direct EPUB files exist on EGW's media host
  (`media2.egwwritings.org`). The only clean standalone monographs are
  **AWLF** (A Word to the "Little Flock", James White) and **WOR**
  (Waggoner on Romans). GCDB/BTS/PUR are shared/bundled periodical codes —
  treat with caution.
- 570 works have no EGW EPUB and require the CaptureClipper path.

## Finalized acquisition rule

1. **EGW Writings EPUB first — only when verified available.** Verify with a
   HEAD check against `https://media2.egwwritings.org/epub/en_<CODE>.epub`
   before offering it. Do not assume availability from any catalog.
2. **CaptureClipper/.studybook packages are the PRIMARY acquisition path for
   Pioneer Authors** — not a fallback. ~98% of the collection is read-online
   only on EGW Writings.
3. **PDF is fallback/special-case only** (same availability as EPUB on EGW;
   no independent coverage).
4. **EllenWhiteAudio, AdventAudio, and APLIB are excluded.** Prior tests
   produced unusable/garbage sources. Do not re-enable them in catalogs,
   registries, or UI.

## Known bad-source references still in the tree (not yet removed)

Removal is Phase E and requires explicit approval. As of 2026-07-08 the
excluded providers still appear in:

- `assets/elibrary_sources/pioneer_sources.json` — 9 `aplib`, 1 `adventaudio`,
  1 `ellenwhiteaudio` source candidates (vs 1 `egwWritings`); registered in
  `pubspec.yaml` assets.
- `lib/features/utilities/data/pioneer_ellenwhite_audio_service.dart` — whole
  service scrapes `ellenwhiteaudio.org/ebooks-of-the-pioneers/`.
- `lib/features/utilities/data/pioneer_epub_collection_service.dart` — default
  refreshers/URLs for `adventaudio.org` Epub.zip and `www.aplib.org`
  pioneers-ebooks; providers `aplib`/`APLIB`.
- `lib/features/utilities/data/pioneer_source_catalog.dart` — provider
  parsing/labels for `adventaudio`, `ellenwhiteaudio`, `aplib`.
- `lib/features/utilities/data/pioneer_text_import_service.dart` — EPUB parser
  profiles `aplibZip`, `ellenWhiteAudio`.
- `lib/features/utilities/data/pioneer_install_status_service.dart` — SQL
  heuristics matching `www.aplib.org`, `adventaudio.org`,
  `ellenwhiteaudio.org` (these detect/flag bad imports; keep the detection
  even in Phase E).
- Tests mirroring the above under `test/features/utilities/data/` and
  `test/features/utilities/presentation/`.

## Implementation phases

- **Phase A (next): StudyBible2 .studybook import polish/test** — the import
  picker/unpack path must be reliable on iPad before anything else matters.
- **Phase B: CaptureClipper export package from completed folder.**
- **Phase C: CloudLibrary latest-copy layout.**
- **Phase D: StudyBible2 installed/update/reimport states.**
- **Phase E: remove/quarantine bad alternate source configs** (list above);
  requires explicit approval; keep `pioneer_install_status_service` detection
  heuristics so legacy bad imports remain identifiable.
