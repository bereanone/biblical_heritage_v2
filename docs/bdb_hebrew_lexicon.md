# Hebrew reference articles in the bundled Bible database

The next app bundle includes source-attributed Brown-Driver-Briggs (BDB)
articles from [BibleAquifer's BDBHebrewLexicon](https://github.com/BibleAquifer/BDBHebrewLexicon),
commit `09fbdf34f82c2e020f772cb578a2bcc0383f5a32`. Its README and resource
metadata declare the edition CC0/public domain. The source README also notes
uncertainty about the ancestry of a few foreign-script transcriptions. We
retain that provenance note rather than representing the transcription as an
unqualified original 1906 edition.

`tool/lexicon/build_reference_lexicons.py` reads its 23 `eng/json/*.content.json`
files and indexes a BDB paragraph only when that paragraph **begins** with an
explicit Strong's number and there is a single matching source paragraph for
that number. The resulting `bible_base.db` contains 5,024 uniquely mapped
Hebrew entries. Another 983 source IDs have multiple candidate paragraphs and
are deliberately left to the original brief Strong's definition, along with
unmatched IDs. This prevents assigning the wrong BDB article to a KJV word.
The original Bible text, token mappings, and all 14,306 Strong's dictionary
rows are unchanged; a data comparison against the previous asset found no
differences in those core tables.

The word panel shows the brief Strong's definition and a compact BDB preview
when an unambiguous BDB paragraph exists. Its full text is available on tap.
The citation is source-specific. BDB text is scholarly lexical commentary;
it does not replace the KJV's Hebrew token mapping or Scripture wording.

The enriched `bible_base.db` uses `PRAGMA user_version=20261005`. At startup,
the app checks its installed **reference** copy and atomically replaces an old
version with the verified asset from the new bundle. It never replaces
`user.db`, `eLibrary.db`, hashtags, notes, or imported books in that step.
