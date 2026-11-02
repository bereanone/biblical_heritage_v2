# Apple permanent unlock and trial — work in progress, 20 October 2026

Not submitted. Do not publish or advertise purchases as live based on source/tests/build alone.

## Agreed policy

- Standard permanent unlock USD19.99, Apple automatic comparable country prices.
- Family Sharing enabled on permanent unlock; keep existing donation products separate.
- ADL and HH offers USD9.99. Philippine Missions offer PHP9 (supersedes 90% approximation and PHP29).
- Fourteen-day free trial, voluntary purchase afterward, no automatic charge. Expiry locks access without deleting saved work.
- Existing customers retain access; store restoration required after reinstall.
- France excluded pending export classification. Do not assert Apple-only encryption: Dart HTTPS and archive crypto need review.
- Gift free offer optional, not created. Tester codes deferred.
- Website must gain Play links and accurate trial/purchase/offer information with launch. Do not publish a premature announcement.

## Verified store records

App Biblical Heritage #StudyBible 6760154157, iOS and macOS same listing.
- Permanent Non-Consumable `studybible_full_access`, Apple6825069268.
- Free Non-Consumable `studybible_trial_14_days`, Apple6825120696, display `14-day Trial`, description `Full access for 14 days. No automatic charge.`
- Trial free-price schedule saved. Availability 174/175; France checkbox inspected unchecked. Save after availability must complete before navigating.
- Permanent unlock availability was last selected174/175 and user told Save; recheck persisted state before submission.
- Paid offers HH,ADL,PHMissions exist,174 regions each, zero codes generated. Reference names do not create redeemable customer codes. PHMissions has comparable offer prices in other regions, not automatically restricted to Philippine accounts.
- Approved donations299,999,2499 untouched.
- Both Apple agreements, banking, tax previously confirmed active. Tax category inherits parent.
- Trial review notes attempted but field appeared blank after user interaction: do not claim persisted notes. Review screenshot still missing on both products. Promotional artwork optional and existing artwork can be reused.

## Source implementation

`StudyBiblePurchaseBridge` appended to registered native iOS AppDelegate and macOS MainFlutterWindow (same implementation, no Xcode file references added). StoreKit2 verified currentEntitlements, verified purchase result, transaction updates, restore via AppStore.sync; revoked transactions omitted. Free trial is separately redeemed and measured from original verified purchase date,14x24hours. Trial is not Family Shared. Permanent ownership accepts purchased or family-shared transactions. No brand/code grants ownership.

Native keychain stores legacy grant and high-water timestamp. Initial existing-install grant uses already-present enrollment grandfather marker; production signed AppTransaction also recognizes pre-payment original app builds1..144 on iOS, original1.0/1.0.0/1.0.1 on Mac. This migration policy needs security/release review; sandbox app transaction never grants automatic legacy access. No user accounts/backend created.

Dart purchase service, application-level gate above Navigator, first-run ministry setup before access screen, Utilities StudyBible access screen with restoration/redeem. Price comes from StoreKit, never hard-coded conversion. Trial expiry checked via timer/resume. Store errors preserve last verified in-memory state; secure native high-water guards clock rollback. WatchRemoteBridge blocks commands and stops native playback when access callback denies. Cold-start Watch path before Dart initialization still needs verification/hardening; do not claim covered by prior Watch tests.

Billing is OFF by default in source until sandbox acceptance. Explicit test/build switch:
`--dart-define=STUDYBIBLE_APPLE_BILLING=true`
Use this for payment test/store candidates, and verify packaged flag. Android billing not implemented and not gated by Apple.

HH source profile now999; legacy provisional enrollment trial14days. pubspec/Watch build references moved145. Mac Release window title Biblical Heritage; DEBUG retains beta label. Mac current installed remains142; no title install yet.

## Proof and next work

- Eighteen focused tests pass: Apple access policy/service plus enrollment suite, including exact trial boundary, rollback high-water, cancel/pending, localized price, restore/revocation, failure preserving access.
- Focused Dart analysis passed.
- First iPhone145 native+gate build compiled successfully (before final singleton/manage-access/first-run ordering edits). Final145 compile started, inspect `/tmp/studybible-payments-ios145-final-build.log` before installation.
- No145 installation yet at time of writing. iPhone physically connected; iPad and Watch paired available. Existing iPhone144, Mac142. Data-preserving installs only.
- Build/tests do not prove sandbox purchase, restore on another device, family sharing, trial redemption, expiry with live audio, Watch expiry, or offer redemption. These remain acceptance gates.
- Need product screenshots, final store metadata, generated offer codes after eligible, full sandbox run, packaging/signing/archive and App Review attachment. No TestFlight upload or submission done.
- Source package remains dirty with many unrelated edits. Preserve all. No commit/push.

## Device follow-up and phone toolbar correction

- Payment build145 installed in-place on iPhone; installed version2.0.5/build145 verified with CoreDevice. User launched it and confirmed Bible playback; this is not sandbox purchase acceptance. User's Mac About still142 (unchanged).
- Trial draft now Saved with English wording, free price schedule,174countries, France inspected unchecked. Review notes persisted on final observed Saved page. Review screenshot still pending. `/tmp/studybible-trial-configured.jpg` is configuration proof, not an in-app purchase review screenshot.
- User reported Highlight and paintbrush crowded/offset phone reference. Both moved to second row; top reference now geometrically centered with symmetric reserved space. Long canonical book names scale to fit. Search-hit navigation uses separate strip only while active, preventing title displacement. Wide/tablet toolbar unchanged.
- Eleven toolbar tests pass including320/430width Song of Solomon center and both highlight controls on row2, callbacks and tablet layout.
- Source/build references146; iPhone146 compiling at `/tmp/studybible-ios146-build.log`, install still pending at this entry. Native legacy cutoff remains144 (the last pre-payment beta), deliberately not increased with each subsequent build.

- iPhone146 compiled successfully, installed in place and launched. CoreDevice verified2.0.5/build146. User physically accepted the toolbar placement ("Yeah, that'll work"). No sandbox trial/purchase/restoration acceptance yet. Installed146 retains explicit Apple-billing build flag. Mac/iPad/Android still not updated with this package.


## Mac selection follow-up (build 148)

- User accepted expansion in the Mac handle prototype (147) but reported that source phrase grouping prevented shrinking to one English word.
- Visible English words now have independent selection coordinates while original source token IDs and Strong’s phrase associations remain intact. New saved highlights retain source bounds plus nullable `start_word`/`end_word` precision; legacy records are not rewritten.
- Both handles can adjust repeatedly; release does not open actions. A separate tap inside the selected text opens actions; clicking outside text and handle targets clears the temporary selection.
- Fourteen focused tests passed, including saved single-word rendering, old highlight rendering, geometry, endpoint adjustment, outside clicks, and repeatable additive schema setup. Focused analysis passed.
- Build/install and physical Mac acceptance are tracked separately. iPhone remains on 146; neither word precision nor the handle prototype has been installed there.
- User confirmed prior iPhone access remains permanent for existing customers, backup creation, and restore-picker opening. Completed backup restore remains untested.
- The isolated StoreKit transaction test did not execute: simulator linking could not find SherpaOnnxC. No successful trial, purchase, refund, or restoration transaction test is claimed.

### Device packaging follow-up

Mac 148 was accepted by the user for selecting one word, expanding/shrinking handles, tapping inside for actions, and clicking outside to deselect. Android arm64 release test APK 148 built successfully (ABI versionCode expected 2148), not installed because Android is disconnected.

The first iPhone148 package contained stale simulator-native objective_c and sqlite3 frameworks. The first installation rejected their ad-hoc signatures; signing alone allowed installation but exposed the wrong-platform startup failure. Both libraries were replaced from the native-hook outputs explicitly targeting arm64/iphoneos. All root frameworks were verified with vtool as IOS, then re-signed with the existing development identity and the app's original entitlements. Corrected in-place installation succeeded, and installed version is 2.0.5 build148. Native launch with console capture was issued; startup and human selection acceptance are separate checks still pending at this note. Watch app and Watch widget both verified 2.0.5+148 in the built package.

User acceptance after repaired iPhone148 installation: app opens normally; handles expand/shrink, tapping inside opens actions, clicking outside clears selection. User read About as 2.0.5+148, matching devicectl and Mac148. iPad is not installed/accepted; Android APK is built but disconnected; Windows shares the reader source but has not been compiled on this Mac.

Selection instructions now describe both handles, single-word shrinking, inside tap for actions, outside tap to deselect, paintbrush/Highlight shortcut, and Clear Markup. Added shared in-app help beside Apply Markup in the reader menu and replaced the stale Range Actions footer. Written instructions: docs/selection-and-highlighting.md. These Help text changes are saved in source after accepted build148; not rebuilt or installed yet.
Android actual Gradle output verified versionCode2148 / versionName2.0.5. Flutter’s convenience export was stale139; preserved that old file and cloned the verified2148 output into the convenience export location. No Android device is connected, so no installation.

### Continuous highlight follow-up (149 source)

User reported black gaps between saved highlighted words after the word-selection split. Highlight rendering now bridges whitespace only when both neighboring words belong to the same saved highlight (or the same temporary range). Exterior spaces and gaps between independently saved ranges remain unpainted. Inside-space taps count as inside the range. Seventeen focused checks passed, including Day/Night, source-token and precise-word saved ranges, handles, and the updated Range Actions Help. Focused analysis passed. iPhone149 compilation started; no149 installation is claimed yet.

Before physical iOS installation/upload, run the read-only `tool/check_ios_device_package.py` against the built app with its expected build number. This verifies each root native framework targets IOS rather than IOSSIMULATOR, requires device signing, checks Watch version alignment, and verifies the package signature. This catches the148 simulator-cache packaging failure before installing.

Physical iPhone149 package verification passed (all root frameworks IOS, development signing, Watch app/widget versions149). In-place device installation succeeded. devicectl independently confirms2.0.5+149, and native relaunch succeeded. User visual acceptance of continuous highlight is still pending. Matching Mac149 is compiling.

Mac149 replacement completed after confirming148 was closed. Retained /Applications/Biblical Heritage.before-update-20261020-212205-build148.app and database snapshot build/update-backups/20261020-212205. Reopened installed app, selected Keep Current Data, visibly verified About2.0.5+149, then Bible Explorer. Screenshot /tmp/studybible-mac149-continuous-highlight.png shows Daniel7:19 saved blue highlight continuously covering interior spaces, unlike the148 screenshot. User physically accepted iPhone149 continuous highlighting. Mac visual behavior is tool-verified; fresh user acceptance remains separate. No build150 was created. Android prepared package remains148 and disconnected; iPad not installed; Windows source shared but not compiled. Website changes and store release have not been published/submitted.

## Overnight handoff, October20

User stopped App Store work until tomorrow. Prioritize App Store, not BiblicalHeritage.net. Neither website instructions nor a release was published; earlier voice claims of publication were incorrect. Created the iOS2.0.5 version draft in App Store Connect (Prepare for Submission); no149 build uploaded or selected, no Add for Review submission. Existing draft inherited stale donations-only description and old review notes; update those for14-day trial/permanent unlock before submission. Trial and unlock are saved drafts; trial review screenshot is still missing. Both new IAPs must be attached to the new version. Payments/restore sandbox transaction testing has not completed; simulator link issue SherpaOnnxC remains.

Mac149 and iPhone149 are installed, About verified149, and continuous highlights accepted. Handle help is included. iPad not updated; Android148 APK prepared but not installed. User is disconnecting iPhone and connecting the Android test phone and authorized putting149 on Android while asleep. This is the only overnight continuation authorized after stopping store work. Keep all device data; no uninstall/reset.

Android149 initial overnight package installed but native process aborted: release Dart VM required a precompiled snapshot. APK inspection confirmed no libapp.so and an included debug kernel. The testBedBackupAccess debuggable-release flag caused Flutter to select debug assets for a release engine. Source release variant now remains isDebuggable=false; explicit test debug certificate remains unchanged. Rebuilding same149 with backup-access debug flag disabled. Added tool/check_android_release_package.py to reject missing AOT/debug-kernel release APKs before installation. No Android149 readiness/visual acceptance is claimed until startup is stable. Original install date remained unchanged.

Corrected Android149 release rebuilt successfully with precompiled app ELF library and no debug kernel. Packaging guard and signature verification passed. Same149/ABI2149 reinstalled in place successfully at21:42:54; original first install October5 unchanged. Native launch Status:ok, process25299 remained alive after15seconds, and per-process logs contained zero startup failure matches. No visual/touch149 acceptance on Android is claimed; leave that for tomorrow. Store work remains paused and no website/publication/submission occurred. Durable restart point: docs/release-handoff-20261020.md.
