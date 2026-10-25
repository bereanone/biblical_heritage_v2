# Planned Tasks

## v15 canonicalization rollout

**Status:** Completed 2026-09-07 after Dean's explicit approval.

The v15 combined page-marker and inline-whitespace canonicalizer fixes have
passed a scratch-only rehearsal. The verified upstream backup, scratch path,
full 12-title cohort, exact command/tool, fused-boundary before/after,
page-marker and Contents spot checks, and integrity result are in `BUGS.md`
under “Pioneer EPUB standalone print-page blocks split reading flow” and
“Inline formatted-text node boundaries drop spaces and fuse words.”

The reviewed 12-title Pioneer cohort was re-canonicalized live with the v15
runner. All 12 are complete at v15; there were 0 failures and 0 missing
sources; live integrity is `ok`. The fresh production backup and full report
are recorded in `BUGS.md` entry 17. The broader upgrade inventory remains out
of scope without separate review.

## Make Bible audio controls obvious on the phone

**Status:** Local next-build candidate implemented at Dean's request, 2026-10-23; supersedes the September 25 deferral. Not packaged, installed or shipped.

The bottom-right gear menu now opens **Bible Audio Settings**. Long-press Play opens the same panel. Read aloud, speed, independent recorded book/chapter/verse announcement switches and the pronunciation editor are grouped there. Audio setup is removed from the Bible autoscroll and loop popups; existing saved keys/values and other readers' defaults remain intact. Turning Read aloud off pauses playback. Pronunciation text clearly explains that edits do not change the prerecorded Bible voice.

Verification: 21 focused tests passed; targeted analysis found only the pre-existing unused import in `bible_explorer_screen.dart`. A Flutter-rendered 390×844 phone preview was inspected without clipping (`docs/release-evidence/2026-10-23-android-audio/bible-audio-settings-phone.png`). Component rendering is not installed-device acceptance. Dean should review the panel in the next test build. The Sony playback report remains a separate open verification item in `BUGS.md`.

Original request: Dean found the current Bible/audio screen unclear about what to press. Make the
primary Play/Pause action visually prominent and plainly labeled in the ordinary
Bible reader. Keep the bundled recorded-Bible path easy to find without a
Utilities import step. Check the design on the phone with Dean before calling it
resolved. This is a usability follow-up, separate from any blank-screen or
playback failure that must be fixed immediately.

## Mixed-language note narration

**Status:** Deferred to the next version at Dean's request, 2026-10-07.

Support a single note or text block containing English and occasional Greek or
Hebrew words by routing language segments to suitable speech engines and playing
them in order. Preserve the original displayed and stored text. Verify biblical
Greek/Hebrew pronunciation and smooth voice, volume, and pacing transitions;
model language support alone is not listening acceptance.

Do not implement this in the current tester/release. Prioritize existing audio
correctness, synchronized verse indicators, announcement defaults (book and
chapter on, verse off; preserve saved choices), phone-build consistency, final
polish, and delivery of the verified tester package.


## App demonstration and October 18 cleanup

See [[docs/demo-video-20261018/Demo Plan|Demo plan, user decisions and verification records]]. Source work is in progress; compiled packages are not installed or accepted. Trash/history settings are separate from the movie critical path.
