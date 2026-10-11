# Abbott-Smith Greek meanings in the reader

The reader's numbered Greek meanings and their sense-specific Scripture
references come from George Abbott-Smith, *A Manual Greek Lexicon of the New
Testament* (1922). The source is the [TEI transcription maintained by
Translatable Exegetical Tools](https://github.com/translatable-exegetical-tools/Abbott-Smith),
commit `8c00cb244761aa23659421a8cbbbf7a3b27b7d59`. That project's README
explicitly declares its TEI transcription and markup public domain. CrossWire
also lists its AbbottSmith module as public domain. The scanned PDF has separate
restrictions and is not bundled here.

The exact TEI input has SHA-256
`99821bee411626b4aa3e674040297b54b267eff86cb4f9b7ef69a8bdb18b6f90`.
`tool/lexicon/build_abbott_smith.py` creates an intermediate lookup from that
input and the app's bundled Bible verse IDs. Then
`tool/lexicon/build_reference_lexicons.py` adds its source-attributed entries
to the versioned `assets/databases/bible_base.db` reference asset. The app
ships and reads that one Bible database; the intermediate lookup is not a
runtime asset. The build
contains 5,397 Greek Strong's entries with detailed senses, 9,612 numbered or unnumbered sense
sections, and 40,977 links to exact verses present in the bundled Bible. A
single source article may explicitly list several Strong's IDs; the builder
indexes each listed ID. Nested sense sections are kept separately so their
citations are not duplicated under parent headings. References that
cannot be resolved exactly remain readable text, never guessed links. The
source and hash are also recorded inside the generated database.

The asset also retains source notes for 76 IDs whose TEI article has no
definition sense, for 5,473 indexed IDs total. All 5,473 match Greek IDs in
the current app. The app has 5,625 Greek dictionary IDs, so 228 retain the
existing brief gloss as their primary definition. Of these,
149 do not occur in the current interlinear token table, and 102 are
placeholder rows without a gloss. Of the 79 IDs that do occur, 60 have a TEI
article with only a cross-reference or spelling note and no definition sense;
19 are absent from that TEI source. The 60 display their Abbott-Smith source
note beside the existing short definition; no other article's senses are
silently assigned to them. The other 19 still display the existing short
definition. Hebrew uses separately attributed BDB articles where the match is
unambiguous; Abbott-Smith does not cover Hebrew. The current Strong's
dictionary remains in place for its familiar number, lemma, pronunciation,
grammar, and brief definition, visible even when a detailed sense is
available. Its exact original import source is not documented in this
checkout, so this addition does not claim or change that provenance.

The importer preserves each TEI sense and its inline reference relationships.
It does not infer a sense from an occurrence list. The UI attributes Abbott-Smith
beside the detailed definitions, offers a single Copy definition action, and
keeps verse links within their actual senses. Related-term text is displayed
only when present in the source. A verse link opens the exact bundled Bible
verse; the return control restores the selected word and panel position.
