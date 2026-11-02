# Apple payment verification — 2.0.5 build149

October21,2026. This is an evidence record, not submission approval.

## Verified in isolated native StoreKit testing

The interactive PaymentHarness uses the production iOS purchase bridge extracted
without entitlement-policy changes. Before testing, the extracted class matched
the production source exactly. Xcode Run supplied the local StoreKit catalogue.
All purchase/restore sheets explicitly identified Environment:Xcode; no live
Apple Account payment or physical-device data was involved.

- A previously redeemed local trial granted access with paid=false.
- Restoring that trial preserved its exact original expiration.
- The permanent-unlock purchase returned purchased, paid=true, allowed=true.
- Restore Purchases retained permanent access.
- Refunding the permanent unlock removed paid access while preserving the active trial.
- Revoking both local entitlements denied access.
- A simulated trial dated October1 denied access on October21.
- Restoring the expired trial retained the original expiration and denied access.
- Canceling an unlock returned cancelled and did not grant access.

Evidence: `/tmp/studybible-payment-harness/manual-payment-proof.txt` contains
the Xcode console with the real Flutter-channel results. Screenshots:
`/tmp/studybible-payment-refund-trial-active.png`,
`/tmp/studybible-payment-expired-trial-restored.png`, and
`/tmp/studybible-payment-expired-after-cancel.png`.

The earlier automated StoreKit catalogue tests still fail with configuration
Code3 on the installed runtimes. They are not passing tests.

## Watch startup correction

Billing-enabled iOS builds start native Watch access closed. Native StoreKit
verification begins before Dart purchase initialization, and its callback and
expiry timer control playback access. Reader state cannot overwrite that access
decision. Billing-off development builds preserve their existing free behavior.

The Xcode build generates `StudyBibleBilling.plist` from the same Dart billing
define, exporting only that boolean. Missing/invalid configuration fails closed.
The package guard verifies this file and accepts `--apple-billing on/off`.

Three build-configuration tests and two native Watch policy tests pass.
Native test evidence: `/tmp/studybible-payment-harness/watch-gate.log` and
`WatchGateResults.xcresult`. No physical Watch playback acceptance is claimed.

## Distribution candidate

Local archive and App Store IPA export completed with billing enabled, version
2.0.5/build149. Both archive and the unpacked exported IPA passed device-platform,
framework signature, companion-version, and native billing checks. The exported
app is signed by Apple Distribution: Dean Bowen. Temporary unpacked verification
copy removed after checking; archive, IPA and logs retained.

IPA SHA256: `23650ce3e4fcbc0dfe889b48eb0db7d44a814dcc5455dfec2c22672a20b38911`.

Archive/export log: `/tmp/studybible-appstore149-archive.log`.
App Store upload started separately; inspect
`/tmp/studybible-appstore149-upload.log` and App Store Connect before claiming
delivery or processing success. Upload is not review submission or release.
Manual release remains selected in the saved draft.

Flutter reports the existing default launch-image placeholder. It did not stop
archive/export; this is not a claim that launch artwork was visually verified.

## Still required

- Full-app UI and Apple server sandbox checks using the uploaded candidate.
- Actual trial/unlock screen screenshots for each IAP review entry.
- Family-shared transaction and revocation verification.
- Pending/Ask to Buy transaction verification beyond mocked Dart checks.
- Native expiry timer firing while playback is active, including Watch behavior.
- Confirm export-compliance responses from the app's actual encryption use;
  France remains excluded as requested. Do not certify Apple-only encryption.
- Attach both new non-consumables to the app-version review submission.

No installed app, user database, library or study data was replaced in this work.
No public website, donation product or tester-message changes were made.
