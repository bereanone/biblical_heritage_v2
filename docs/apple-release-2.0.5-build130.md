# Apple validation builds — 2.0.5 build 130

Prepared October 18, 2026. The subsequent [iPhone build131 update](iphone-release-2.0.5-build131.md) adds and verifies automatic iPhone content provisioning; the results below describe build130. These are local validation artifacts, not an App Store, TestFlight, or notarized Mac release.

## Packages

Both files are in `dist/apple-2.0.5-build130/` (excluded from Git):

- `Biblical-Heritage-Mac-2.0.5-build130-arm64.zip` — 2,962,620,082 bytes; SHA-256 `dcebcf7b8cbb26c3dc50e92004c2c1cef6cc30ec75b4a507e643f40b9c645555`.
- `Biblical-Heritage-iPhone-2.0.5-build130-development.ipa` — 2,961,740,393 bytes; SHA-256 `710b1cb5ea1f10086093d8cfcc512c0ac93a65dd401b93a3a86772fe0d08d79f`.

The Mac ZIP contains the Apple Silicon app, requires macOS 12 or later, and is ad-hoc signed. Deep signature verification passed; notarization was not performed. The app remains available at `build/macos/DemoValidationArm64/Build/Products/Release/Biblical Heritage.app`.

The iPhone IPA is development-signed for registered devices and requires iOS 15 or later. The archive is `build/ios/archive/Runner.xcarchive`. Runner, Watch app, and Watch widget all report 2.0.5 build 130. The archive and IPA export succeeded, and deep signature verification passed. Flutter reported the existing default launch-image placeholder as a nonblocking warning.

## Device and content evidence

The connected iPhone was updated in place, without uninstalling or resetting it. A separate installed-app query confirmed build 130. Launch was denied because the phone was locked; visible iPhone behavior and audible playback remain morning checks. The simulator was not used: the existing native narration framework has a device arm64 slice only, and a physical device was available.

The Mac toolbar cleanup was visibly accepted during the preceding user walkthrough. The packaged Mac app includes the shared compact list rows and picker font limit. No live Mac catalogs or study databases were replaced.

Automatic managed-book/audio provisioning currently remains Android-specific. These Apple builds preserve the existing Apple library workflow; a fresh Apple install has not been proven to download the six recording packages automatically. Do not advertise Android's complete-download installation proof as Apple proof.

## Regression checks

- Full final suite: **1,695 passed, 3 skipped, 2 failed**. The two author-search tests for Jones and Waggoner in `multi_author_contributor_test.dart` also fail on isolated previous revision `255bee4` (18 pass / 2 fail). Current content search requires a body-text match, while those tests expect author metadata alone to return a paragraph. They remain visible failures, not waived or silently changed.
- Active app/tests/integration analysis: **zero errors**, 2 unused-import warnings and 115 informational lints. Repository-wide analysis also includes historical snapshots in `tool/Verification`; it is not clean.
- Corrected stale UI expectations for Folder / All Books / Copy entry, lexical dialog geometry, rich export's asynchronous database read, per-verse spoken lead-ins, and default tilt direction. Updated word-panel golden was visually reviewed.
- The deterministic SSP development harness now sets its positive-pitch direction explicitly; it does not change the production reader. The private-fixture SL27 diagnostic is retained in `test/manual/` rather than automatically run without its unavailable fixture.
- Local qwen3-coder-next review found no concrete native-bridge defect; compilation independently checked the native code. No cloud review agents were used.
- Source/test whitespace check passed. One existing trailing space in the hash-verified Seer of Patmos source payload is preserved for source fidelity. Release runtime source is unchanged by the final test-only/dev-harness cleanup after packaging.

## Morning check

1. Unlock the iPhone and open Biblical Heritage. Confirm build 130, existing notes and lists, and the removed toolbar shortcuts.
2. Check enlarged text in the book picker, compact library List rows, folder labels, and Top Shelf's Shelf/List switch.
3. Open an existing library book and confirm the expected cover, Contents destination and audio controls. Listen to a short sample, stop it, and switch books to check that playback does not overlap.
4. Open the Mac app above and check the same shared UI changes and existing data. Mac ZIP is for local testing; public distribution still needs signing/notarization.

Android build 130, its verified shared download, README and recording packages were left unchanged by this Apple pass. Operational notes and the Word draft remain local.
