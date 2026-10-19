# iPhone full update — 2.0.5 build 131

October 19, 2026. Enables the managed mobile book and recording updater on iOS. One shared platform policy is used by catalog migration, audio setup and its progress UI; Android remains supported and desktop library roots remain excluded.

## Verified on the connected iPhone

- Development-signed archive/IPA built; Runner, Watch app and Watch widget all embed 2.0.5 build131. Deep signature verification passed.
- In-place installation succeeded; independent installed-app query confirms131, and native launch succeeded.
- All six managed catalog revisions and resource folders appeared. The catalog has565items with every prior item ID retained. Study tables (including seven hash tags), notes and markups are unchanged from the pre-update copy; SQLite quick_check passed.
- The app automatically installed six core recording packages plus optional Waggoner audio for the phone's existing exact source fingerprint. No recording files were manually transferred to the phone. All seven device-selected package pointers, manifest SHA256s and verification receipts match the pinned package specs (176 files total). This is installed-content verification, not human listening acceptance.
- Existing legacy audio folders, optional Lessons on Faith and imported books were preserved. No Waggoner book text was supplied.

## Checks

36 focused tests passed for platform policy, catalog preservation, actual bundled assets, verified downloads, interruption/retry and optional matching. A separate migration test against a copy of the actual iPhone catalog passed, preserving its records. Targeted analysis reported no issues. Bounded local qwen3-coder-next review found no concrete defect. Full suite was not repeated for this platform gate change; build130's two known baseline author-search failures remain documented in its release notes.

## Artifact

`dist/apple-2.0.5-build131/Biblical-Heritage-iPhone-2.0.5-build131-development.ipa`

- Bytes:2,961,775,749
- SHA256:`33c4517ca5a34f7f4b7fd44c31cebb95c6f62e5a39304611685646b7efdf3c48`
- Development-signed for registered devices; iOS15+. Not submitted to TestFlight/App Store. Existing launch-image placeholder warning remains.

Please listen to a short book sample and confirm visible controls. The installed Mac and shared Android130 packages were not replaced. Future source builds use131 consistently.
