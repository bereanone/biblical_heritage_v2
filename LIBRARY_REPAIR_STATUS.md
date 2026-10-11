# Latest correction and continuation — September 10, 2026, 21:09 Eastern

The user wants development to continue tonight in the existing project. Scheduled task continue-elibrary-repair-today is PAUSED at the user's complaint that automatic continuation messages disrupt ongoing work. Do not re-enable it without a new request. Work continues in this task. A clarification is pending about tonight's scope: fully finish Daniel and the Revelation first versus the entire Pioneer library.

Four original Preface forms visually verified from the original 1897 scan PDF10-12 and now installed: DAR4.3 Psalms→Ps.; DAR4.5 fulfillment→fulfilment; DAR5.3 Revelation→Rev.; DAR6.1 Daniel→Dan. Exact contextual replacements only, no bulk spelling conversion. Original Saviour, to-day and other historical wording retained. Added four stable source anchors in a separately rehearsed unchanged-text stage before the wording stage; all 3588 block IDs,3325references,122navigation entries,73images and user positions/annotations preserved. Both stages reimport identically; all55illustrationlinks tested; navigation rows including index targets unchanged. Independent unaffected-table audits and fresh backup passed. Source SHA d6ff3cf5605162e583b262de1ca80586f5d25c6dafb63b80c80d8f42690a8760 at ImportedPioneerEpubs/DAR-1897-preface-wording-corrected.epub; canonicalizer34. Source evidence and four new corrections appended to approved-original-corrections.sqlite (now42current correction rows plus8earlier witnesses). No app code change or restart needed for this data slice; current open reader may cache content until reopening. No claim of a fresh UI check for these four new forms yet.

Existing app root remains /Users/deanbowen/Library/Containers/com.deanbowen.bibleAppMac/Data/Documents/BiblicalHeritage/v2. Actual project /Users/deanbowen/Development/StudyBible2. Backup /Users/deanbowen/.codex/.chatgpt-projects/g-p-6a920309b2408191a80052bf567ed45c/library-repair/data/main-dar-preface-wording-pre-install-backup. Evidence/tooling in tool/Verification/dar_preface_wording/ and library-repair/evidence/DAR-preface-wording/. Full source review and offline release packaging are still incomplete; original-only requirement remains absolute. No generated cover, no modern publisher additions, no standalone preview, no title-based identities, no Bible DB changes, no user-data overwrite, no commit/push.

# Original-only requirement and installed correction — September 10, 2026

The user's latest instruction is absolute: no modern alterations; preserve the original edition's wording, historical spelling, punctuation, structure and illustrations. This supersedes earlier permission for generated artwork. Correct transcription only from visual source evidence, never AI preference. Keep navigation, citation controls, search, annotations and provenance separate from authored content. Continue in the existing StudyBible2 project and actual main app, never a standalone preview.

Installed DAR source: ImportedPioneerEpubs/DAR-1897-original-frontmatter.epub, SHA256 48edb8c251949132f78b64665138325ace918827e1ca731bc626ea1b96ce6cde. Main root: /Users/deanbowen/Library/Containers/com.deanbowen.bibleAppMac/Data/Documents/BiblicalHeritage/v2. Canonicalizer 34. One preferred DAR remains visible. The generated cover, modern title page, APL copyright/contact/ISBN/editorial notice/promotional pages and logo are omitted from this revision. Original 1897 title-page facsimile and author copyright notice restored; portrait/title/copyright/Preface/Contents/Illustrations now follow the original order. The facsimile is an unaltered rendering of the original scan and includes the scan's Library of Congress stamp/pencil marks; no generated cleanup. Historical copyright notice retained as original content.

Rehearsal through existing app importer passed: 3588 blocks, all 3584 retained block IDs and wording preserved, 3325 references, 73 images, 122 navigation destinations, 55 illustration links and 1327 index links; full-library search, one preferred catalog entry and identical repeat import. Page reset metadata explicitly marks missing Contents page boundaries: the importer no longer inherits Preface page 6 into Contents/Illustrations. 59 old stale page-6 metadata assignments removed; actual DAR citations and text unchanged. Reader no longer inserts the modern 'Chapter outline' heading. Shelf cover fitting changed to contain the whole original image rather than cropping it.

Guarded live selected-title transaction completed after independent all-table rehearsal audit and fresh backup; all other title rows, all annotation rows and current saved position preserved. No user.db write, no Bible database change, no commit/push. Backup: /Users/deanbowen/.codex/.chatgpt-projects/g-p-6a920309b2408191a80052bf567ed45c/library-repair/data/main-dar-original-only-pre-install-backup. Code and audit records: tool/Verification/dar_original_only/ in the real project; complete witness/review data: /Users/deanbowen/.codex/.chatgpt-projects/g-p-6a920309b2408191a80052bf567ed45c/library-repair.

Release is NOT cleared. Many body comparison candidates and illustration provenance checks remain. Removal of known modern publisher material is not proof that all later wording or artwork is absent. Do not modernize or silently resolve source disagreements. The entire library has not reached the quality of this one selected title.

Database/packaging status: actual SQLite stores reference_prefix/reference_page/reference_paragraph/reference_origin/reference_witness/reference_context/content_role, structured formatted_content, block IDs/source maps, nested navigation and contributor relations. Image blocks reference content-hashed image files in the local canonical asset directory. Image bytes are NOT embedded in eLibrary.db, and the distribution-rights review ledger remains external. The current DB alone is not a complete portable release. A deterministic offline bundle/install of DB plus verified assets, with release provenance and all-device validation, remains to be completed before shipping. Existing user annotations must not be bundled.

Historical notes below are superseded where they conflict with this update.

Existing StudyBible app updated September 10, 2026.

Daniel and the Revelation now has one visible preferred 1897 reading copy in the normal app, with generated cover, readable original text, DAR references, upright responsive images, clickable illustration and index links, and saved reading positions. The missing Preface numeral 1. was verified against the original scan, restored in the EPUB and database, and visibly checked. Other library sources still require individual quality review; distribution clearance remains incomplete.

Actual project: /Users/deanbowen/Development/StudyBible2. Actual main database: /Users/deanbowen/Library/Containers/com.deanbowen.bibleAppMac/Data/Documents/BiblicalHeritage/v2/eLibrary.db. Current corrected source SHA256: 46fe41288580f58fada4a96fd279f7494f071c174aed3bbcd0437a37d50c3cc9.

Code and verification use this existing project. Temporary SQLite snapshots are migration safety checks only; no separate preview is required. The final main-app shelf and numbered Preface were visibly checked. Existing uncommitted work remains; no commit or push. Bible database untouched.

Verification records: tool/Verification/dar_main_rollout/. Fresh database backups and full source-review evidence are recorded in /Users/deanbowen/.codex/.chatgpt-projects/g-p-6a920309b2408191a80052bf567ed45c/library-repair/REPAIR-STATUS.md.

Historical September 9 status (superseded by the rollout above):

Library repair implemented and tested on September 9, 2026.

144 regression tests passed in this checkout. The separate preview contains 534 repaired books with 29,750 resolved Contents destinations. The installed app and production databases have not been migrated. Final visual checks require the Mac to be unlocked. Existing uncommitted work has been preserved; nothing has been committed or pushed.

Full status, evidence, backups, and rollout instructions:

[Library repair status](/Users/deanbowen/.codex/.chatgpt-projects/g-p-6a920309b2408191a80052bf567ed45c/library-repair/REPAIR-STATUS.md)
