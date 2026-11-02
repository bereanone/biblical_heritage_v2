# Cross-platform content correction workflow

Start this workflow automatically for every reported content or reader defect.
Its purpose is to make a correction reach every applicable display, narration,
and update path, rather than fixing only the path where it was first observed.

1. Identify the exact defect and the user's expected result. Record the work,
   edition/source digest, stable reference, paragraph/block/cue identity, app
   version, device, selected audio package, and displayed reader implementation.
   Verify the intended wording against an appropriate source. Keep that source
   and the original defective assets intact.
2. Trace every representation of the affected passage: original EPUB/HTML,
   direct-file reader output (both text and markup), canonical document blocks,
   legacy/search/reference copies, speech input, prerecorded audio, cue metadata,
   caches, source-hash gates, manifests, and package selection. A corrected
   canonical database does not prove that the direct EPUB reader is corrected.
3. Maintain an evidence matrix for iPhone, iPad, Android, Mac, and Watch.
   For each applicable platform record display path, narration path, installed
   content version, correction delivery, and proof level. Mark unsupported Watch
   capabilities not applicable and unavailable device checks unverified. Inspect
   connected authorized devices where practical. Do not substitute build success,
   a simulator, an asset hash, ASR, or another platform for physical or audible
   proof. Follow the user's current installation scope.
4. Correct the narrow shared cause and any platform-specific consumers. Preserve
   stable paragraph/navigation identities, reference codes, reading positions,
   and user annotations. Separate published corrections from untouched original
   source evidence; retain a reversible record of changed content rows/assets.
   Protect user-modified content and unrecognized editions from blanket rewrites.
5. Match repaired audio to the user-approved voice, wording, loudness, natural
   delivery, and surrounding pauses. Preserve existing cue times and surrounding
   pauses. Any unavoidable timing change must be explicitly reviewed before
   promotion and every dependent timing reference updated; never introduce an
   unreviewed timing shift. Provide a context sample
   containing the unchanged passages before and after the repair. State whether
   automated transcription or the user actually verified the sound.
6. Make app updates replace stale managed text and audio automatically. Check
   both old and new installed data, direct reader parsing, idempotent startup
   corrections, reimport, hash/version changes, cached recordings, optional
   packages, interrupted installs, and selection precedence. Verify replacements
   completely before selecting them; retain the prior working package on failure.
   Never require a user to clear data, delete a book, reimport, reset settings,
   or reinstall from scratch to receive a published correction.
7. Add focused regression checks for the actual failed path and update behavior.
   Exercise the actual affected source when available. Validate shipped manifests,
   asset digests, source compatibility, and cue alignment. Include negative checks
   for unrelated editions and user data. Keep release build numbers synchronized
   across phone, tablet, Android, Mac, and Watch components when preparing a release.
8. Install only within the user's authorized device scope, after a verified data
   backup. Reuse existing verified copies of unchanged library databases and audio;
   do not transfer those large files again for routine app updates. Check the exact
   device identity and saved file size/modification metadata before reusing a
   database base file, and verify the retained local digest. Save changed user data,
   database WAL files, settings, and reading positions separately. Keep one stored
   copy of each identical backup file while preserving complete restore records.
   Test the installed updated app, not just a staged package. Compare
   the affected visible passage and selected recording; confirm expected controls.
   Distinguish installed/selected assets, actual visual or playback observations,
   and human acceptance. Record unavailable checks as remaining work.
9. Before releasing to everyone, rehearse an in-place update over an older
   affected installation on each applicable available platform and verify user
   data preservation and automatic content replacement. Do not claim seamless
   all-platform delivery while applicable platform/update checks remain unverified.
   Local user testing may proceed before release readiness; store submission
   remains subject to the user's existing authorization boundary.

Keep a compact incident receipt with the evidence matrix, changed assets/paths,
backups, validation, installed targets, human acceptance, and outstanding checks.
Report what is actually fixed without requiring the user to interpret build logs.

## Android USB test delivery

The connected Samsung is a test vehicle. Do not upload or publish to Google Play
without the user explicitly authorizing that action. Compare actual source and
packaged assets; a build number does not establish whether corrections are present.

The Play-installed app and the existing USB test app have different signing keys.
Preserve both applications and their data. Use the guarded `usbTestApplicationId`
option with `com.deanbowen.bibleappmac.ministrytest`, explicit test signing, and an
Android update counter greater than the installed test app when updating over USB.
Never uninstall the Play app to bypass a signature mismatch.

Install-time packs retain original Flutter asset paths. Include both library audio
packs alongside Bible audio and reader voices; verify every compiled asset occurs
exactly once and matches its digest. Verify every generated APK remains below the
Android signature parser size limit before installing. Confirm the actual installed
AssetManager can open the approved recordings; archive checks alone do not prove it.

## Book-player reading-speed standard

On Mac, iPhone, iPad, and Android, book playback exposes a labeled `Speed` control
near Play. On Mac, separate it from the transport cluster toward the center of
the row. Narrow screens may place it directly beneath the transport. Reading
speed must be accessible without opening scrolling settings. Show the current
multiplier and label 1.0× as Normal in the menu. Use the shared
`ReadingSpeedButton` for recorded and generated narration.

Keep speed, silent autoscrolling, and playback-follow scrolling independent.
Changing speed while paused must leave playback paused and preserve the selected
word/location. Save the preference and apply it to the player actually producing
the audio. When the Watch owns the phone player, send the speed change to that
player and reflect its reported rate; never start a second player.

The current supported range is 0.75×–1.5×. Speed changes do not regenerate or
replace approved audio. Any future redesign must retain an obvious, labeled
speed control and a Normal reset on each applicable platform.

Audio Off is a saved playback preference. Saving it stops narration and hides
Play and Speed, including prerecorded playback. Text selection, chapter changes,
stale callbacks, repeat actions, and Watch commands must not turn Audio back on.
Turning Audio On restores paused controls without starting speech. Silent
autoscrolling remains available independently of the audio preference.
