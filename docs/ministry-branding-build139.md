# Ministry branding test build 139

## Agreed behavior

One Play app. New installs get one promotional-code setup screen with an Install without promotional code option. Default Biblical Heritage presentation remains unchanged without a code. ADL selects Advent Defense League; Heritage & Hope aliases select Heritage & Hope Ministries. Brand selection persists across launches and upgrades. Utilities offers optional brand changes without resetting access. Existing installs retain full access locally; a code does not change ownership. Curated books remain available regardless of branding.

ADL approved artwork and the user-approved Heritage & Hope concept are included. Small About and gear-labelled Utilities actions appear at the lower right; the reader retains theme selection. Support opens the selected ministry website in an external browser. If no browser opens, the address remains copyable. Community Links shows that ministry's website without borrowing Biblical Heritage's Facebook copy.

Websites supplied by the user and verified 20 October 2026:
- https://adventdefenseleague.com
- https://heritageandhope.org
- Default: https://biblicalheritage.net

Official ministry starter hashtags have NOT been supplied. ADL has an empty Advent Defense League folder ready for additive seeds; sample tags in concept art are not approved seed content. Heritage & Hope has no invented tag list. The first preview cropped the approved artwork and rebuilt its lower section. The user rejected that change. The corrected welcome displays the complete original 1024 x 1536 image without cropping or replacement typography. An invisible Explore hit area matches the artwork button. The user subsequently clarified that the entire artwork must fill the available screen and small translucent About/Utilities buttons must overlay the attribution row, About left of the logo and Utilities right of the attribution. The image now scales to the viewport without cropping; it may scale differently horizontally and vertically to avoid blank bands. There is no footer or top test banner. Sample study tags shown in the concept are not seeded as approved ministry content.

## Validation

33 focused tests pass: enrollment persistence and early-user status, interrupted first launch, optional/no/invalid codes, additive tag seeding, both ministry welcome footers with large text and dark app theme, website launch requests for all three brands, Utilities layout/routes, and Android library authorization. Scoped source analysis reported no issues before the final footer wrapping adjustment. Startup authorization tests use an isolated enrollment store rather than a real host-machine settings path.

A source/test result is not an installed-device result. Build, install and visible-device verification are still pending at this record's creation.

## Production work still required

No billing SDK, Play product setup, verified purchase restoration, account-bound early-user ownership, secure trial enforcement, or store upload is included. The local seven-day timestamp is recorded only: it does not lock the app. Intended one-time unlock is $19.99 standard and $9.99 ADL; Heritage & Hope discount is unapproved. No actual discount or purchase is currently offered. Lost-device/reinstall ownership restoration without a backup is not solved by a local settings record.

## Ministry approval checklist

Confirm displayed ministry name, rights to use supplied artwork, promotional code, support/community website, any approved wording, starter tag folder and exact tag content, approved purchase terms, and a contact for future changes. Website donations are handled by the ministry, not by the app. This is an approval checklist, not an executed agreement.

## Separate Android preview

User approved a separate test copy without audio or library downloads. Staging project: `/tmp/studybible-ministry-preview139`; application ID `com.deanbowen.bibleappmac.ministrytest`; launcher label StudyBible Ministry Test. Entry point preserved at `tool/ministry_setup_preview.dart`. The staging project shares real source screens and enrollment logic, but saves setup/origin to its own app-private files and does not seed library data. The preview About dialog is explicitly a test notice, not the full production About disclosure. Explore explains the limited scope; Utilities is the real screen using an injected isolated enrollment service. Only branding, website links and persistence should be tested in this copy. The normal app is not overwritten.

## Android preview installation evidence

The separate release preview built successfully (64,628,325 bytes), package `com.deanbowen.bibleappmac.ministrytest`, versionCode 2139. APK inspection confirmed both ministry images, zero audio assets and zero library/database assets. ADB installation returned Success. Installed preview version confirmed; normal StudyBible remains versionCode 2138. Preview was launched explicitly; UI hierarchy and screenshot confirmed the automatic Preparing to install #StudyBible screen, promotional-code input, Apply promotional code, and Install without promotional code. No code was entered by automation: left on the initial screen for user testing. Capture: `/tmp/studybible-bug-fixes-20261020/ministry-preview-first-launch139.png`. Visible ministry selection, on-device website opening, and relaunch persistence await user/device testing. All 33 focused regression tests pass after the Utilities service-injection change; preview/shared-source analysis reports no issues.

## Approved-artwork correction

User rejected the redesigned/cropped welcome. Both asset files were compared byte-for-byte by SHA-256 against their approved originals and match. Corrected source uses full-image contain rendering at the original 2:3 ratio, not a cropped header or rebuilt text. Twenty ministry tests pass, including uncropped artwork geometry, correct asset selection, Explore activation, and large-text footer actions for both ministries. Replacement preview build/device verification pending at this entry.

## Final overlay placement requested by user

The user rejected the separate footer and blank bands. The source now fills the available phone screen with the original complete image, places About left of the Biblical Heritage logo and Utilities right of its attribution, and removes the preview banner. Only Explore, About and Utilities are interactive. Hashtag graphics are expressly decorative; users reach actual hashtag lists inside the app. Twenty ministry tests pass, covering full viewport image layout, all three action callbacks, inactive hashtag regions, persistence and setup behavior. Rebuilt preview install/visible verification pending at this entry.

Final overlay preview rebuilt and installed successfully. Launched with the user's saved ADL selection; code entry did not repeat. Android UI dump and screenshot confirm artwork occupies the complete content region [0,100]-[1080,2205], About overlays the lower left [22,2017]-[205,2152], Utilities overlays the lower right [875,2017]-[1069,2152], and Explore remains in the artwork button. No preview banner, separate footer or blank app bands are present. Screenshot: `/tmp/studybible-bug-fixes-20261020/ministry-overlay-visible.png`. System status/navigation bars remain standard Android UI. Final scoped analysis reports no issues; twenty ministry tests passed before the final opacity literal correction. Left open for user review without further taps.

## Attribution aspect-ratio correction

User approved the main full-screen scene but reported the Biblical Heritage logo/attribution stretching. The renderer now treats the original bottom attribution strip separately: same unchanged source image, scaled uniformly at its original ratio. Main scene continues to fill the remaining space. ADL split begins at source y=1390; Heritage & Hope at y=1360, both below their Explore artwork buttons. About/Utilities align with the undistorted attribution, and Explore hit geometry follows the main image region. Twenty ministry tests pass, including attribution source ratio, complete viewport coverage and three action callbacks; scoped analysis has no issues. Separate preview rebuilt, ADB install returned Success, reopened with saved ADL branding, and screenshot visually confirms the undistorted attribution. Evidence `/tmp/studybible-bug-fixes-20261020/ministry-logo-aspect.png`. Normal StudyBible was not replaced.

## Short Heritage & Hope code

User requested HH for simpler entry. Added HH as an alias; existing HERITAGE AND HOPE, HERITAGE & HOPE and earlier BIBLICAL HOPE aliases remain valid. Normalization accepts lowercase and surrounding spaces. Twelve enrollment tests pass, including explicit HH/hh cases. Existing saved ministry IDs, setup completion, trial timestamp and access status are unchanged. Separate preview update build/install pending at this entry.

User asked to stop repeating tests/relaunches for the HH code change. HH is saved in source configuration (not a mutable code database). The HH preview package finished building but has not been installed. User also required partner About to match the main Bible app: extracted the existing unchanged main About dialog to a shared function used by production EntryScreen and the preview. This shared About change is source-only, not yet packaged or installed. No further test, build, install or relaunch was run after that steering; formatting only. Last installed preview includes the accepted undistorted attribution and longer Heritage & Hope codes.

## Community links saved for the next update

Bible Readings 1914 is a shared Community Link across default and ministry brands. Android targets Google Play `com.biblicalheritage.brhc`; iOS targets the verified Apple listing `id6757504303`. Unsupported platforms do not get an incorrect mobile-store button. Each ministry profile also has an initially empty communityLinks list for future ministry-supplied labels and HTTPS URLs. These additions are source-only; no additional test, build, install or relaunch was performed after the user requested avoiding repeated testing.

## Permanent free tester access — single-use requirement

User requires each selected tester to get the complete permanent unlock free, with a unique access code redeemable only once. Five issued codes must permit at most five grants, not a reusable universal tester password. Ministry branding codes (ADL/HH) remain separate from access rights. Prefer store-issued one-time-use codes for the non-consumable permanent unlock: Google Play one-time-product promo codes and Apple non-consumable one-time-use offer codes. The store validates redemption and subsequent access is restored through the redeeming store account; restoring an existing grant is not a new code redemption. Separate store-specific codes are required under this approach. Do not add a local TESTER code or a local used-code list as protection. An unused bearer code can still be claimed by the first recipient, so private distribution is necessary if intended-recipient identity matters. Products/offers and purchase/restore integration must exist first; no tester codes have been generated or granted.

Sources checked 20 October 2026:
- https://support.google.com/googleplay/android-developer/answer/6321495?hl=en
- https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases

Tester-access clarification: user considered named store testers, then authorized the most secure practical way to prevent sharing. Keep permanent free-access grants separate from TestFlight / Google license-testing permissions. Recommendation remains store-issued unique single-use full-unlock codes, privately distributed, with store-account restoration. Ten codes means at most ten redemption grants; do not promise to prevent access via shared store-account credentials. Check the unlock product's Apple Family Sharing setting before configuring grants (once enabled for a product it cannot be disabled); do not enable shareable tester entitlements. Google Play Family Library does not share in-app purchases. No store tester list, product setting, or code has been changed.

User requested a batch of 50 single-use free tester grants and a delivered code list. Labels may be Tester 1 through Tester 50, but actual redemption codes should remain store-generated, not predictable sequential bearer codes. Google Play Console is accessible and shows the existing StudyBible production listing; Apple App Store Connect requires sign-in. No code batch or full-unlock product has been created. Store setup paused when the user redirected attention to the old installed Mac build (119).

## Desktop distribution discussion

User prefers Mac App Store licensing for the Apple desktop version and raised Windows access as the harder case. Proposed an optional Windows companion license based on verified full-access phone ownership, including approved tester/early-user grants, rather than the presence of a free/trial phone installation. This would require purchase verification and a durable desktop activation record; it is not implemented and no final desktop device-count/offline-refresh policy is decided. Apple universal purchase is a possible supported route for related iOS/Mac app versions, subject to the existing App Store Connect record configuration. No third-party payment-service account or checkout was created. Mac build 139 is being prepared separately to replace the locally installed build 119, preserving user data; no installation has occurred yet.

## Installed Mac update

The running installed Mac app was `/Applications/Biblical Heritage.app`, build 119, not a project debug copy. Prepared release configuration with Flutter build number 139, then built successfully with Xcode 27 using a command-only macOS 12 deployment override for this local machine. Bundle identity and local ad-hoc signing verified. Closed the old app cleanly, retained it at `/Applications/Biblical Heritage.before-update-20261020-140706-build119.app`, and cloned user/eLibrary database files and sidecars to `build/update-backups/20261020-140706`. Installed candidate atomically at the original app path and verified its signature. Reopened actual installed build 139; native window title and About both show 139. About visibly includes the AI narration disclosure and pronunciation credits.

Read-only comparison of all 38 user-database tables against the pre-update snapshot found 37 unchanged, including saved user content and settings; only app_migrations changed. No new tables appeared. Content comparison hashes are stored privately in `build/update-backups/20261020-140706/user-record-preservation.json`. This confirms saved user records were preserved; it is not a claim that desktop audio or every reading path was retested. No exhaustive test suite was run. The build is a local beta, not a notarized public download or App Store submission.

## Windows activation refinement

User proposes that a phone with a verified paid upgrade display a limited-use Windows activation code, entered into Windows to unlock it. Latest clarification restricts eligibility to a real paid standard/ministry-discount unlock, not merely installing the free phone app. Any exceptions for free early-user/tester grants remain to be decided for Windows; do not assume them from the earlier proposal. One/two allowed activations must be enforced through a shared authoritative redemption record; a local counter or predictable code is insufficient. Phone UI can request/show the code without exposing this mechanism to the user. No activation code service, Windows unlock, store full-access product, or tester-code batch has been created.
