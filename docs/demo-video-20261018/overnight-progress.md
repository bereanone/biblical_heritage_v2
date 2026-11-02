# Overnight checkpoint

Source changes applied in actual repo, preserving pre-existing dirty work. Exact before copies under before-fixes/; initial-fix-hashes.json records first three edits.

- Lexical return context consumed before reopening original word panel.
- Temporary mapped word selection cleared after initial/returned lexical panel closes and when interlinear is disabled.
- Category filter replaced opaque funnel with visible adaptive ON/OFF switch and all/selected-category scope. Existing callbacks/data unchanged.
- Current Listen item's full preview no longer forced into one line; other rows have two-line preview.
- Export introduction now has separate website instructions as user requested.

Checks: 29 existing targeted planner/list-entry/header tests passed. Added narrow-screen (430px) filter switch ON/OFF/callback test; all 4 list-entry tests pass. Targeted analysis of first three source files found only existing unused local_settings_store import in bible_explorer_screen.dart; no errors. No app builds, installations, database/content changes or audible verification.

Local Qwen coding review batch completed in local-farm/. Some proposals were incorrect (e.g. nullable fixes on nonnullable text and false duplicate-export diagnosis); these were rejected. Only independently inspected proposals applied. Independent qwen3.6 actual-diff review running via verify.py (session59551); inspect result before further work. Do not launch duplicate.

Still required:
1. Rich clipboard HTML/RTF export across platforms and Word paste verification; detail-card rich text rendering.
2. Audio overlap investigation (two AudioplayersTagClipPlayer instances alternate; inspect transition races and other audio sessions). DO NOT claim cause established; initial local report lacked evidence.
3. Duplicate scripture presentation citation: locate actual render path, not export or planner; initial local proposal was wrong.
4. Remove snackbars comprehensively, preserve meaningful errors via suitable visible feedback.
5. Shadow direct substantive source opening while retaining alternate mappings (not implemented).
6. Strengthen lexical behavior regression tests and analyze remaining changed files.
7. Demo note wording cleanup only with formatting preserved; no live note edit yet.
8. Build/installed UI validation and audible checks remain pending; video on hold, morning human dry run required.

Morning dry run: Acts5:15 passing by -> Mark1:29 -> Back -> close; no return banner at source. Interlinear OFF/ON no stale bold. Shadow direct entry. Both interlinear styles. Category switch visible on phone/Mac. Sabbath range8–11 visible and all four audible, no overlap; loop/pause. Rich note detail and Word paste retain bold/underline/italics/combo. Presentation citation once. No unwanted snackbars. Then rerun original demo sequence before video.

Second heartbeat checkpoint:
- Independent qwen3.6 review completed. Rejected claimed lifecycle regressions: reviewer failed to recognize await showDialog completes at dismissal and invented method names; actual diff consumes return context before panel reopening. It suggested displaying category name explicitly (reasonable future polish). Unlimited active row is inside a scrollable list, intentional for full range.
- Fixed standalone note detail-card rendering: now uses existing noteFormatJson with buildPresentationTextSpans, matching Present's formatting pipeline. Existing backup of tag_detail_screen.dart precedes both this and intro changes. No content/database edit.
- Flutter analysis of tag_detail_screen.dart, tag_dialog_hash_tab.dart, tag_playback_panel.dart passed with no issues.
- Located actual duplicate-citation renderer: presentation_slide_canvas.dart (~520-580) renders scripture body plus citation; inspect outer heading construction and settings before deleting citation. viewer_presentation_screen.dart only188lines, actual canvas2044lines. Previous local proposed export/planner fixes were invalid.
- Remaining major work unchanged: rich native clipboard payload, audio overlap/lifecycle, snackbars, shadow primary lexical mapping, meaningful lexical and presentation tests, installed/audible/human dry run.

Third heartbeat checkpoint:
- Fixed duplicate citation in actual presentation_slide_canvas.dart: omit bottom item citation only when it matches displayed slide title (normalize en/em dashes); preserve distinct citations below custom/grouped titles. Exact pre-change backup saved.
- Added presentation_citation_once_test.dart: matching scripture title shows citation once; custom title retains scripture citation. Both widget tests passed.
- Found live demo audio diagnostic evidence in app container Caches/com.deanbowen.bibleAppMac/narration-events.log. At22:16:29.482831 generated tag_verse_audio WAV begins;22:16:34.519569 completion;22:16:34.534171 first saved-Qwen WAV starts;22:16:38.135731 completion;22:16:38.154062 next saved-Qwen WAV starts;22:16:53.271840 completion;22:16:53.292152 next saved-Qwen WAV starts;22:16:59 stop. This establishes sequential generated intro followed by saved verse clips in log, NOT simultaneous overlap. User's audible overlap remains unverified; need inspect generated intro clip and alternate player/native completion race rather than claim confirmed overlap. No audio changed.
- Next: rich clipboard support (macOS MainFlutterWindow LibraryRootFlutterViewController, iOS didInitializeImplicitFlutterEngine registrar, Android configureFlutterEngine need channel registration; Dart export currently plaintext). Use existing presentation_text_format.dart to preserve ranges safely rather than inventing JSON schema. Existing noteFormatJson ranges support bold/underline/italic.

Fourth heartbeat checkpoint:
- Implemented rich HTML plus plain-text clipboard export via studybible/rich_clipboard channel. Dart helper study_export_clipboard.dart uses existing hash-validated formatting spans and escapes text. Standalone notes, Bible text overrides and attached Bible notes now preserve rich styles in HTML. Export retains plain representation. Some eLibrary excerpt paths still need rich mapping review.
- Native channel handlers added inside existing Mac/iOS/Android entry files; all prior dirty changes preserved with exact first backups. Mac writes NSPasteboardItem .string/.html together; iOS writes utf8 plain + HTML data; Android ClipData.newHtmlText. Dart fallback only for MissingPluginException, so native actual failures are not silently misreported.
- Flutter analysis of helper and tag_detail_screen passed. Rich export tests initially exposed invalid test fixture missing required base_text_hash (production correctly rejected unsafe styles); corrected fixture. Tests verify combined bold/italic/underline, escaping/newline and dual channel payload.
- Native compilation and real Word paste remain unverified. Do not mark export bug accepted without installed rebuilt UI and paste test.
- Local qwen3.6 review of rich platform diffs running via local-farm/verify-export.py (session28157), result rich-export-independent-review.md. Inspect before further changes; avoid duplicate job.
- Next outstanding priorities: comprehensive snackbar removal with meaningful errors; direct shadow lexical primary + alternatives; audio overlap diagnosis/hardening only with evidence; native syntax checks/targeted suite; morning dry run. Heartbeat stays active.

Fifth heartbeat checkpoint:
- Read local rich-export review. Rejected unsupported claims about invalid Unicode from Swift utf8 and missing HTML wrapper (Dart helper already wraps it); adjacent div elements are valid HTML. Empty div spacing deserves visual Word review but no evidence of content loss. No blind model changes applied.
- swiftc -frontend -parse macos/Runner/MainFlutterWindow.swift ios/Runner/AppDelegate.swift passed. This is syntax only, not native build/typecheck or installed paste proof.
- Removed routine default-set/tagged/rename/save-note/copy confirmation snackbars in tag_screen_dialog.dart and tag_detail_screen.dart; errors still visible through existing feedback. Other snackbars, notably rapid-tag confirmation plus global library/utilities/error paths, still require comprehensive replacement/removal. Do NOT claim all removed.
- Source analysis passed for tag_screen_dialog.dart, tag_detail_screen.dart and presentation_slide_canvas.dart.
- Direct shadow entry is still outstanding. Existing ViewerStrongsEntry has partOfSpeech; principled primary selection can choose unique substantive content word over article/pronoun mappings, but alternate mappings need a reachable control in word panel. Avoid discarding them or guessing POS labels without inspecting actual lexicon data.

Sixth heartbeat in progress:
- Read-only bundled lexicon query confirms shadow G4639 is noun; article G3588 is definite article. POS labels include noun, proper noun, verb, adjective, substantive.
- Implemented unique substantive mapping auto-selection (only when all entries load and exactly one content word exists); ambiguous content mappings still use chooser. All mappings retained in _LexicalSourceContext through copy/return paths. Word dialog has explicit Source dropdown for multiple mappings. Switching updates citation/occurrence return context to selected source; no source records discarded.
- Modified files: bible_explorer_navigation.dart, bible_explorer_screen.dart, viewer_strongs_launcher.dart. Existing first backups retained. Targeted analyze no errors, only baseline unused local_settings_store import warning.
- Lexical layout + citation + clipboard tests running session50174. Need add specific source-switch regression and primary-selection test next, inspect actual source logic before declaring done. No installed UI verified.
- Lexical suite initially failed2 stale test label expectations: tests sought Copy definition while existing page-one source says Copy entry (unrelated to new selector; page-one source not changed). Updated test label expectations after backup. Need inspect last session86262 result; previous full failure log /private/tmp/lexical-test.log. Citation+rich export checks passed in combined run.
- Further suite mismatch: old test requires BottomSheet and golden, while BEFORE-FIX launcher already used Dialog. Restored test file exactly from backup rather than updating unrelated stale layout/golden contract. Thus lexical suite remains6pass/1fail after label correction experiment, or5pass/2fail in original labels. Current test file is original. Need targeted new selector test avoiding stale golden, and report baseline clearly. Do not say full lexical suite passes.

Seventh heartbeat checkpoint:
- Added lexical_source_selector_test.dart with fake lexicon and actual dialog: primary shadow opens directly, article alternate remains accessible via Source dropdown, switching invokes selected-source callback and updates displayed definition. Test passed. Existing stale golden suite left unchanged.
- Source selection still needs primary-choice unit coverage and real Acts5:15 UI confirmation; new test directly exercises launcher, not database mapping ranking.
- Audio evidence remains sequential intro then Qwen, not reproduced overlap. Two-player adapter doesn't explicitly await inactive-player stop before starting next; Darwin completion-before-release documented in its comment. Potential hardening requires lifecycle/late-start regression coverage before modifying. Avoid declaring it user's exact cause.
- No native builds/installed app or Word paste yet. All live data preserved; existing app still old build.

Eighth heartbeat checkpoint:
- Demo-flow feedback cleanup: shared showReadableSnackBar no longer creates snackbars. Rapid-tag confirmations are silent (saved markup reflects success); remaining actionable messages display readable dialogs. Removed remaining routine range tag/clear/memory and tag detail assignment/save/merge confirmations. Tag detail helper now routes actual remaining feedback through dialog helper. All relevant source analysis passed.
- Global snackbar calls in library/utilities/app thermal notice still outstanding; do not claim all app snackbars removed. Avoid generic hide-all that suppresses errors. Need systematic caller review, quiet successes and visible meaningful errors.
- Focused demo regression suite running session96914; inspect result. Source changes not installed; human acceptance remains pending.

Ninth heartbeat checkpoint:
- Previous focused demo suite completed:11 tests passed, including narrow category filter, selector, rich clipboard, presentation citation and header responsiveness.
- Started release Mac compile verification (not installation), log /private/tmp/studybible-demo-macos-build.log. Check running process/session before retrying. This is source/package proof only; live app data and Word remain untouched. Do not run simultaneous builds.
- Need prioritize global snackbar caller audit and audio lifecycle investigation; many source fixes are applied but cannot yet claim all requested bugs fixed.
- Mac build running session22280. Last log Building macOS application; no result yet. Next heartbeat must poll/check log rather than start again.

Morning live session:
- Universal Mac failure narrowed: lipo reports both architectures but multi-arch verify returns requires exactly one input file; single arm64 verify succeeds. Earlier missing-architecture explanation corrected to user.
- xcodebuild separate DemoValidationArm64 output ARCHS=arm64 ONLY_ACTIVE_ARCH=YES completed BUILD SUCCEEDED. No installed app replacement or live data changes.
- User has Android tester, authorizes proceeding with Android test package and checklist. Android arm64 release APK build launched; log /private/tmp/studybible-demo-android-build.log. Need check result before sharing. No device install.
