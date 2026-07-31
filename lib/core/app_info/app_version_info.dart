import 'package:package_info_plus/package_info_plus.dart';

/// Single authoritative source for the app's display version.
///
/// Reads the version/build baked into the app bundle at build time
/// (from `pubspec.yaml`'s `version:` field via `flutter build`), so the
/// visible version always matches what was actually shipped. Every release
/// must bump `pubspec.yaml`'s `version:` — nothing else needs editing.
class AppVersionInfo {
  AppVersionInfo._();

  static PackageInfo? _cached;

  static Future<PackageInfo> _load() async {
    return _cached ??= await PackageInfo.fromPlatform();
  }

  /// e.g. "2.0.5"
  static Future<String> versionName() async => (await _load()).version;

  /// e.g. "2" (the build number)
  static Future<String> buildNumber() async => (await _load()).buildNumber;

  /// e.g. "2.0.5+2"
  static Future<String> versionWithBuild() async {
    final info = await _load();
    return '${info.version}+${info.buildNumber}';
  }
}
