# Android release build and plugin registration

Use the normal Flutter release command with pub enabled:

```sh
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Keep the dependency lockfile and the existing signing configuration. This command uses `pubspec.yaml` for the shared version. Coordinate the next release version before changing it; do not reset it to the current checkout's older build number.

## Why `--no-pub` can break a release after tests

In the installed Flutter 3.41.4 tool, `regeneratePlatformSpecificToolingIfApplicable` returns immediately when `shouldRunPub` is false. Thus `--no-pub` skips release plugin regeneration as well as dependency resolution.

A preceding `flutter pub get` or development/test tooling can leave `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` containing the dev-only `integration_test` plugin. The release Gradle plugin excludes dev dependencies, so compiling that stale registrant fails with:

```text
package dev.flutter.plugins.integration_test does not exist
```

Run the normal release command above, without `--no-pub`. Flutter then regenerates the registrant with release-only dependencies. A standalone `flutter pub get` followed by a release build with `--no-pub` does not perform that release-specific regeneration.

Do not hand-edit the generated registrant, move `integration_test` into runtime dependencies, or modify the shared Flutter SDK. No app Gradle change is required for this issue.

## Local validation signing

Production release signing still requires the existing release keystore configuration. For an explicitly authorized local test build only, the repository already supports:

```sh
ORG_GRADLE_PROJECT_testBedDebugSigning=true flutter build apk --release --split-per-abi --target-platform android-arm64
```

This uses the existing Android Debug certificate. It does not create production signing credentials or authorize installation/publication.

## Historical candidate assessment (October 16, 2026)

The installed Mac bundle and existing iOS build output both report **2.0.5 build 119**. The existing Android arm64 split APK reports **versionCode 2087**, corresponding to base build 87 plus Flutter's arm64 ABI offset of 2000.

The next locally unused coordinated candidate is **`2.0.5+120`**. An arm64 split release from base 120 emits **versionCode 2120**, above the observed 2087. A universal APK with versionCode 120 would not upgrade an Android install already using versionCode 2087; preserve the split-APK workflow or separately coordinate a suitable universal versionCode.

This is a recommendation, not a reservation or remote-store availability check. Confirm other workers and store submissions have not consumed the candidate before changing the shared `pubspec.yaml`. This task does not alter it. The isolated packaging-validation artifacts retain **2.0.5+81** and must not be used as upgrades.

## Device validation remains separate

A successful package build does not validate native thermal events or sustained device temperatures. Deliver only a correctly signed, newly versioned in-place update under device-test authorization; preserve app data. Check short ordinary playback, persistent audio reuse after relaunch, Stop during a temperature wait, and native pause/resume delivery without deliberately heating the phone.

## Completed coordinated build 130 (October 18, 2026)

The current shared version is **2.0.5+130**. The arm64 Android package uses versionCode2130 and was installed in place on Samsung and on an isolated fresh test device. Its shared Drive download passed an anonymous full-file hash comparison. The six included audiobook packages and optional fingerprint-matched companion retain their existing links. The Apple packages and separate validation limits are documented in [Apple build130](apple-release-2.0.5-build130.md). The older candidate assessment above is historical, not the next build recommendation.
