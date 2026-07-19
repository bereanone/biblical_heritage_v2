import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp('tilt_prefs_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return supportDirectory.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await supportDirectory.delete(recursive: true);
  });

  test('defaults and ranges are stable', () {
    const defaults = ReaderTiltPreferences.defaults;
    expect(defaults.reverseVerticalDirection, isFalse);
    expect(defaults.neutralZoneFraction, closeTo(0.05, 0.0001));
    expect(defaults.speedMultiplier, 1);
    expect(defaults.horizontalChapterTiltEnabled, isFalse);
    expect(defaults.reverseHorizontalDirection, isFalse);
    expect(defaults.horizontalSensitivity, 0.5);
    expect(defaults.horizontalChapterTiltAvailabilityMigrated, isFalse);
    expect(defaults.statusBannerMode, ReaderTiltStatusBannerMode.autoHide);
  });

  test('JSON round trip preserves every preference', () {
    const original = ReaderTiltPreferences(
      reverseVerticalDirection: true,
      neutralZoneFraction: 0.08,
      speedMultiplier: 1.7,
      horizontalChapterTiltEnabled: true,
      reverseHorizontalDirection: true,
      horizontalSensitivity: 0.8,
      horizontalChapterTiltAvailabilityMigrated: true,
      statusBannerMode: ReaderTiltStatusBannerMode.alwaysHidden,
    );
    final restored = ReaderTiltPreferences.fromJson(original.toJson());
    expect(restored.reverseVerticalDirection, isTrue);
    expect(restored.neutralZoneFraction, 0.08);
    expect(restored.speedMultiplier, 1.7);
    expect(restored.horizontalChapterTiltEnabled, isTrue);
    expect(restored.reverseHorizontalDirection, isTrue);
    expect(restored.horizontalSensitivity, 0.8);
    expect(restored.horizontalChapterTiltAvailabilityMigrated, isTrue);
    expect(restored.statusBannerMode, ReaderTiltStatusBannerMode.alwaysHidden);
  });

  test('preferences persist across store reopen', () async {
    const store = ReaderTiltPreferencesStore();
    const saved = ReaderTiltPreferences(
      reverseVerticalDirection: true,
      neutralZoneFraction: 0.09,
      speedMultiplier: 1.5,
      horizontalChapterTiltEnabled: true,
      reverseHorizontalDirection: true,
      horizontalSensitivity: 0.25,
      statusBannerMode: ReaderTiltStatusBannerMode.alwaysVisible,
    );
    await store.save(saved);
    final reopened = await const ReaderTiltPreferencesStore().load();
    expect(reopened.toJson(), saved.toJson());
  });
}
