# Bug fixes and saved mobile audio — build 132

Date: October 20, 2026. Working tree based on commit `67640b6293964f3df225285f43d8355613e5e835`.

## Result and scope

The current working tree fixes the confirmed title/author search gaps, full-text Top Shelf scoping, unsafe same-metadata duplicate repair, and saved-pronunciation default merging. All 33 historical BUGS.md entries now have a dated disposition; historical descriptions are preserved. Original SL27/anomalous EPUB content, remaining Greek/Strong's candidates, and physical-device endurance/recovery acceptance remain open.

The user's Android is explicitly a **test device only**. Its StudyBible package is `com.deanbowen.bibleappmac`; the older, separate `com.biblicalheritage.brhc` installation is not this update target.

## Mobile audio behavior

- Windows and Mac can generate full-book narration. iOS/Android book controls use recorded packages; an unavailable recording gives a message. The queue itself also checks the restriction so restored preferences and programmatic Play cannot bypass the UI.
- iOS/Android tag playback uses prerecorded Bible audio or already saved exact-text clips. Missing clips do not initiate local synthesis. Opening a tag does not trigger the older background note-preparation loop on mobile.
- Short note creation/edits queue persistent audio preparation. Changes to notes or their spoken titles prepare the currently saved values, including when an edit contains only a subset of the fields. Clearing/replacing a note invalidates stale queued work.
- The mobile note preparation budget is 1,600 characters including the title, with native synthesis chunks bounded to 320 characters. Longer text stays saved, but requires computer preparation for audio. This bounds work; it is not a duration/temperature guarantee. Existing thermal pause/pacing remains active during mobile generation.
- Android and iOS save note audio at normal speed and vary playback rate; selecting a different listening speed does not require a new note recording. Cache identity includes text/voice/pronunciation settings. A changed pronunciation setting can make a previous recording unavailable until the note is prepared again.
- Cache files are checked as complete PCM WAVs. Writes finish atomically, cleanup completes before success is reported, and playback cannot synthesize a replacement for a missing/corrupt mobile recording.
- Previously created notes may not have recordings; mobile playback reports that state instead of generating a large backlog. Save/edit a short note to prepare it. Unrecorded edited Bible text or library passages similarly report unavailable audio rather than silently substituting different content.

## Verification completed on the Mac

- First confirmed-defect run: **57 passed** (search, duplicate safety, pronunciation persistence).
- Mobile audio/tag regression run: **222 passed**, including cache misses that cannot call the renderer, iOS/Android speed reuse, edited text, incomplete files, stale saves, hard chunk limits, desktop availability, tag sequencing, and thermal-gate behavior.
- Twelve previously failing explicit-catalog test fixtures were isolated from automatic mobile shipped-book provisioning; their original assertions remain intact. **54 passed** after isolation. Widget suites use Flutter's desktop platform variant; mobile delivery tests remain separate.
- Complete final suite: **1,728 passed, 3 skipped, 0 failures**. Runtime about 265 seconds. These are host tests, not execution on Android/iOS hardware.
- Focused audio analysis: no errors/warnings; pre-existing helper style notices plus one unnecessary test import (subsequently removed).
- Android release-mode arm64 APK built successfully using the repository's explicit test-device Android Debug signing path. Package identity and version verified: `2.0.5`, arm64 split versionCode `2132` (base build `132` plus Flutter ABI offset).
- Shared pubspec and iOS project build settings are advanced together to `132`; Mac/iPhone/Watch packages have not been built or installed in this pass. Dependency lockfile unchanged.

## Device/release status

Android in-place installation completed successfully. Package manager confirmed versionCode `2132`, version `2.0.5`, and the original first-install date remained October 5. Launch returned `Status: ok` and the app process was running. A fresh screenshot showed the existing eLibrary reader open to **The $150,000 Fund**, with the new missing-recording message visible and no local full-book narration button. The captured startup log contained no reported Flutter unhandled exception or Android fatal exception. This establishes installation and that visible control state, not note generation or playback acceptance. No physical-device endurance/heat/battery outcome is established by the host tests or APK build. Wired charging also limits what can be inferred about battery drain.

No TestFlight build was created or uploaded. No iPhone update was installed. No App Store submission occurred. League branding remains a concept, not an implemented launch-screen change.

## Evidence

Logs and original-file backups for this pass are under `/tmp/studybible-bug-fixes-20261020/` and `/tmp/studybible-bug-refresh-20261020/`. Key files: `fix-tests.jsonl`, `mobile-audio-regressions.jsonl`, `fixture-regressions-final.jsonl`, `full-suite-final.jsonl`, `android-build132.log`, `android-apk-metadata.txt`, `android-apk-signing.txt`, `android-install132.log`, `android-installed-package132.txt`, `android-launch132.txt`, `android-after-install.png`, and `android-app-start-log.txt`. These temporary paths are not a permanent archive; this document records their results without claiming unperformed verification.

## Physical Android note playback and brief thermal check

On October 20, two test notes were saved under `#AudioSavedTest`, alongside Revelation 9:19. The longer note contained 424 characters. The first attempt stopped with a missing-note-audio warning; later replay succeeded without another save, consistent with save-time preparation still being incomplete on the first attempt. The user confirmed hearing both notes all the way through. This exposes an unresolved readiness race: playback must distinguish ongoing save-time preparation from an absent recording. The current warning also remains visible until playback is retried/stopped or the player is closed.

The warning presentation has now been changed in source to dark red (`#8B0000`) on white with padding and a live-region announcement. Focused static analysis found no issues. This presentation change is not yet included in the installed Android build. Automatic readiness handling is not yet implemented.

A roughly two-minute loop test of the verse and both saved notes ran on the connected, charging Samsung. Readings were captured before playback and at 30-second intervals through 120 seconds; playback was stopped and looping disabled immediately afterward (final UI confirmation at about 127 seconds). The UI showed active playback at each timed sample and returned from the last note to the first verse during the run.

| Sensor | Before playback | At 120 seconds | Highest sampled during playback |
| --- | --- | --- | --- |
| Processor/AP | 33.9 C | 36.0 C | 36.9 C |
| Battery | 31.8 C | 30.6 C | 31.8 C including baseline |
| Skin | 33.5 C | 33.7 C | 33.7 C |

Android reported thermal status 0 (no thermal warning) throughout the samples. Battery status remained charging. A follow-up reading showed 98 percent charge; the falling battery measurement above is temperature, not charge percentage. Charging, display activity and diagnostic sampling prevent assigning temperature changes solely to audio playback. This short run does not establish long-session battery drain, endurance, or a guarantee against overheating. The loop log contained no matching synthesis/error lines; absence of log lines alone does not establish absence of synthesis.

Evidence: `/tmp/studybible-bug-fixes-20261020/android-two-minute-loop.jsonl`, `android-two-minute-loop-log.txt`, and `android-full-list-progress.xml`.

## Follow-up: build 133, note readiness and direct note creation

The user accepted the brief thermal check for now, with reconsideration if testers report problems. The note preparation race is fixed in source: saving registers all chunks of a note synchronously, and mobile playback waits for that existing save-time job before opening any chunk. Playback does not start generation. Whole-note save jobs are serialized; superseded queued revisions are skipped. Failed preparation releases waiters to the missing-recording error rather than hanging. The readable dark-red-on-white error is included.

A direct Add note button now opens the existing note editor from the hashtag picker, including for a tag with no verses or notes. The selected folder is passed to note insertion. The tag-entry field selects the list; it does not rename existing tags (renaming remains a separate action and confirmation).

Verification: 28 focused checks passed; the full tag-playback and responsive detail-screen run passed 204 checks with no failures. Analysis found no errors or warnings, with one existing unnecessary-interpolation style notice in the detail screen. The prior complete app suite result belongs to build 132; it was not rerun for this follow-up.

Android build 133 completed and installed in place successfully. Package manager confirmed split versionCode 2133 / versionName 2.0.5, retaining the original first-install date. Keep Current Data was selected on launch. Shared build settings are 133; no Apple build, TestFlight upload, or App Store submission occurred.

On the physical Samsung, Add note opened an editor for a new separate hashtag, #ReadyAudioTest133, without adding a verse. A 601-character multi-segment test note saved successfully. The first Play attempt visibly showed Preparing audio, then Playing, then Finished with no missing-recording error. This establishes the device state sequence and first-attempt completion; the user had moved to other audio, so it is not a new human listening acceptance claim. Speed changes and app-restart replay were not tested on this fresh note before the user asked to switch to Greek details. The earlier build's two-note playback was heard completely by the user.

Evidence: android-build133.log, android-install133.log, android-installed133.txt, note-readiness-tests.log, note-readiness-regressions.jsonl, android-readiness133-note.txt, android-readiness133-first-play.jsonl and android-readiness133-latest.xml in the existing temporary evidence folder.

## Greek-details demonstration

At the user's request, the Android Bible reader was switched to interlinear mode at Revelation 9:19. The English word power was tapped. The app opened word details displaying Greek ἐξουσία, Strong's G1849, transliteration exousía, and the displayed meaning authority. This verifies this tap and displayed target, not all historical Greek/Strong's assignment candidates. The prior report concerned possible data-assignment mismatches, not a freshly confirmed unreliable tap handler. No Bible word assignments or Pioneer source files were changed during this demonstration.


## About disclosure and Pioneer comparison (2026-10-20)

The splash-screen About dialog now describes supplied Bible/library/extended-library narration as AI-generated synthesized speech and credits the pronunciation references actually documented in the earlier audit: Oxford University Press, *Helps to the Study of the Bible*, “Dictionary of Scripture Proper Names, with Their Pronunciation and Meanings” (CCEL reproduction); Hermann Michaelis and Daniel Jones, *A Phonetic Dictionary of the English Language* (1913); and the *Zondervan Pictorial Encyclopedia of the Bible* via Bible Gateway. The disclosure concerns finished narration, without making a claim about every synthesis input. It acknowledges pronunciation variants and possible synthesis errors. The dialog scrolls to accommodate the text. Targeted Dart analysis and diff checks pass; these About changes have not been packaged or installed.

All seven EPUBs from historical bug 16 were copied from the Mac legacy library into temporary storage and converted by the current v43 canonicalizer using a new temporary database. All seven conversions passed. The live catalog was opened read-only; original EPUB hashes were unchanged after the check.

| Title | Stored Mac blocks | Fresh isolated blocks |
| --- | ---: | ---: |
| The Immaculate Conception of the Blessed Virgin Mary | 1 | 48 |
| The Ten Commandments | 129 | 128 |
| A Review of the Remarks of O.R.L. Crozier on the Institution, Design and Abolition of the Sabbath | 1 | 373 |
| Samuel and the Witch of Endor | 1 | 203 |
| Sermon on the Two Covenants | 1 | 196 |
| The Perpetuity of the Royal Law | 1 | 165 |
| The Rich Man and Lazarus | 1 | 86 |

For the six former single-block books, the complete fresh body text equals the EPUB body character-for-character after whitespace normalization, with case, punctuation, digits, and ordering retained. For The Ten Commandments, the same comparison passes after excluding standalone print-page labels 2–32 from the source body; page 2 was separately confirmed in the following block's source-page metadata. This establishes prose preservation for these seven source files under the current importer, not scan-to-EPUB accuracy, visible layout, or installed mobile behavior. The legacy catalog still contains v12/v13 generations. No live reindex, app install, or phone interaction was performed in this comparison.

Evidence: `/tmp/studybible-bug-fixes-20261020/pioneer-review/manifest.json`, `current-summary.json`, `preservation-summary.json`, `pioneer_review_test.dart`, and `test.log`. The initial scratch test required missing creation/update metadata to be supplied; the corrected harness passed all seven conversions. No production parser changes were needed.


## Follow-up: About notice installed on Android, build 134

The connected Samsung initially confirmed Android versionCode 2133 and its About dialog lacked the new notice. Build 134 was then packaged and installed in place with the existing Android test signing configuration and normal release runtime. Package manager confirmed versionCode 2134, versionName 2.0.5, and the unchanged October 5 first-install date. Keep Current Data was selected at the update prompt.

The actual About screen was opened on the phone and visually verified: version 2.0.5+2134, the complete AI narration disclosure, and the Oxford, Michaelis–Jones, and Zondervan pronunciation credits were visible. About was left open. Shared source build settings are 134; no Apple package or store upload was performed.

Build recovery: the first no-pub build encountered a stale integration-test plugin registration. Regenerating dependencies cleared it. A debug-backup-enabled build left Flutter's usual APK path stale; inspection caught that path still reporting 2133. The previous package was inadvertently reinstalled from that path before the final verified update. The final build disabled debug backup access, and package checks confirmed version 2134, a release AOT library, and both disclosure/reference strings before installation. Final installation succeeded, followed by the on-device checks above.

Evidence under `/tmp/studybible-bug-fixes-20261020/`: `android-build134-final.log`, `android-install134-final.log`, `android-about-before134.xml`, `android-about134.xml`, and `android-about134.png`. No live Pioneer reindex was performed as part of this About update.


## Entry controls: portrait review and compact design

Android build 135 (versionCode 2135) installed in place and was opened on the existing #AudioSavedTest list with three entries. A physical portrait screenshot confirmed that the verse and notes used the available card width, with a separate scrolling action row above. A horizontal swipe revealed Trash without opening an editor or changing the three-entry count. The user preferred making all four actions visible rather than relying on scrolling.

The final source uses two-line Move up / Move down labels, caps only the action labels at a 1.2 text-scale factor with a 14-point base, and retains minimum 48-by-48 logical-pixel action targets. The verse/note content retains its independent reading-size setting. Actions wrap on unusually narrow screens; no horizontal toolbar scrollbar or bottom slider remains. Help describes landscape as an optional way to gain room. Seven focused tests passed using the bundled Roboto font, including a 3x ambient text scale, phone/narrow/wide widths, preservation of the uncapped reading text, all actions remaining in bounds, the actual portrait screen, and existing trash behavior. Static analysis found no errors or warnings; one existing string-interpolation style advisory remains in the surrounding screen.

The build 136 package was verified before installation: Android versionCode 2136, release AOT code, new compact-control Help text, and the earlier About disclosure. Installation/device confirmation is recorded below when complete. Evidence is under `/tmp/studybible-bug-fixes-20261020/`: `tag-entry-final-layout-tests.log`, `android-build136.log`, `android-install136.log`, `android-layout135.png`, and `android-layout135-scrolled.xml`.

The user's size-optimization question was assessed without changing content or compression. The inspected release APK was approximately 3.006 GB; audio/model assets accounted for 2.850 GB packed, while compiled Dart code was about 12.45 MB. The user requested avoiding risk for negligible code-size savings; no size-optimization work was authorized or performed. Audio assets and compression settings remain unchanged in the layout update.

Build 136 installation was confirmed with Android versionCode 2136 and the original first-install date. Relaunched and selected Keep Current Data; the existing three-entry #AudioSavedTest list was retained. Device UI hierarchy shows Edit, two-line Move up/down, and Trash on one row. The user noticed the arrow icons were missing. Restored arrow icons above the two-line labels without increasing button width; all seven focused layout and gesture tests passed. Build 137 is being prepared; installation is not yet verified.

Build 137 device confirmation: ADB install returned Success; installed versionCode 2137 and original first-install date verified. Relaunched and chose Keep Current Data. The three-entry #AudioSavedTest list remains present. Screenshot android-layout137.png visibly confirms up/down arrow icons above the stacked labels, with Edit and Trash on the same row and full-width note text. Seven focused tests cover enlarged text; this device screenshot verifies the current phone font setting, not a separate large-font device test. No audio or compression changes were made. Evidence: android-build137.log, android-install137.log, android-layout137.xml/png, tag-entry-arrow-tests.log under the existing temporary evidence directory.

### Adaptive controls for wider layouts

After accepting the compact phone layout, the user requested more room on larger screens. Entry controls now use actual available width: below 480 logical pixels they retain arrows above two-line labels; at 480 or wider they show arrows beside single-line labels with additional padding and spacing. Toolbar-only text scaling remains capped at 1.2, reading text keeps its chosen scale, and very narrow rows wrap. Help describes both layouts. All nine focused layout/gesture tests pass, including widths 180, 290, 479, 480, and 700 with 3x ambient text scaling; source analysis reports no issues for the action widget and its tests. Shared source build numbers advanced to 138. Android build/install and orientation verification are pending. Evidence: tag-entry-adaptive-tests.log and android-build138.log in the existing temporary evidence folder.

User clarification: the approved Android test phone must remain unchanged; wider controls are for tablet-sized iOS or Android screens, not all Android devices or rotated phones. The pending Android build was stopped and no build 138 installation was performed. The final source rule requires both a window shortest side of at least 600 logical pixels and at least 480 logical pixels available to the actions. Smaller/split panes and phone portrait/landscape remain compact. Eleven focused tests pass, including portrait and landscape phone dimensions at 3x ambient text scaling; action-widget/test analysis reports no issues and diff whitespace checks pass. These are host-side layout checks, not physical iPhone/iPad verification. Source build number 138 is reserved for the next package; the test phone remains on the previously confirmed build 137. Evidence: tag-entry-tablet-tests.log.

### Add Note beside Tag Verse — build 138

At the user's request, the separate Add Note control above the hashtag field was removed. Tag Verse and Add Note now form an adjacent pair with matching size/style, acting on the selected hashtag. On phones they sit beneath the full-width tag field; larger layouts keep the pair together beside it. Empty tags still open the existing note editor; note storage/audio behavior is unchanged. Help describes the two choices. Sixteen focused tests passed, including adjacent equal-height buttons and the empty-tag callback. Targeted analysis found no issues.

After the requested pause and resume, the saved release package was verified as Android versionCode 2138 with compiled release code containing the new labels and Help text. In-place installation returned Success and preserved the original first-install date. Relaunched and selected Keep Current Data. On the physical Samsung, the #hi hashtag screen was opened; the screenshot and UI hierarchy confirm Tag Verse and Add Note adjacent, equal-sized, under the tag field, with no separate Add Note control above. Existing saved tags remain visible. The phone is left on this screen without additional note edits. Evidence under /tmp/studybible-bug-fixes-20261020/: add-note-placement-tests.log, android-build138-add-note.log, android-install138-add-note.log, android138.xml, android-add-note138.png. Tablet/iPhone layout is source/test coverage only; no Apple build or store upload occurred.

### Installed hashtag Help verification

On installed Android build 138, opened the main hashtag question-mark button and confirmed the Instructions dialog displays Tag Verse/Add Note adjacency, empty-tag note creation, independent folder filtering, and List settings → Folder for moving lists. Closed Help, opened the existing #hi list, and opened its Instructions question mark. The How this screen works dialog displays the current compact/tablet controls, optional landscape editing, Add entry, and the existing/new-folder Move workflow. Both buttons visibly opened their respective dialogs on the physical Samsung. No content or folder assignment was changed during this check. List Help remains open for review. Evidence: android-help-main-open.xml and android-help-detail-open.xml under the existing temporary evidence folder. No additional build was needed.

### Fresh public EPUB imports on Android

The user requested testing what a new user can download today, rather than repairing older installed copies. Downloaded The Rich Man and Lazarus and History of the Sabbath and First Day of the Week from the live Adventist Pioneer Library EPUB links. Both files passed ZIP/container checks. The Rich Man download is byte-identical to the earlier audited source. Using installed build 138 on the physical Samsung, followed Utilities → Set Up My Library → Import Book → Choose EPUB, selected each fresh download, confirmed title/author, and received 1 book ready. This is the current generic Import Book workflow, not a re-enabled APLIB acquisition catalog.

Rich Man: reader displays title, author, separate paragraphs, and its final numbered paragraphs through the final Matthew 25:41 reference. Contents contains the source-authored single entry; after scrolling into the book, selecting it returned to the opening heading. History: source NCX has 39 entries including 35 nested entries; phone Contents visibly preserves indentation beneath Parts, and selecting Chapter 2 reached its matching heading. A later Chapter 13 attempt initially appeared near Chapter 11, but user and automation were operating the phone concurrently. The user reported selecting Chapter 13 successfully and the captured reader state confirms Chapter 13. That earlier observation is not sufficient evidence of a defect; no navigation fix was applied. Automation stopped when the user resumed control.

An optional All Collections ending-text search remained busy during the check and was closed; its timing/result remains unverified, rather than a confirmed missing-text defect. Automatic approval review rejected copying the entire device library database due to private content beyond the requested book; no bypass or broad database export was performed. All device verification used the visible reader and Contents. Evidence: fresh-aplib/fresh-downloads.json, android-import-result.xml, android-reader-open.png/xml, android-contents.xml, android-toc-return.xml, android-ending.xml, android-history-contents.png/xml, android-history-chapter2.xml, android-history-chapter13-settled.xml, android-history-retry-visible.xml under the existing temporary evidence folder. These checks cover these two fresh books, not every source or every chapter link.
