import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    await UserDatabase.instance.close();
    dir = await Directory.systemTemp.createTemp('retired_settings_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => dir.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await UserDatabase.instance.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('removes only the retired announce-note row', () async {
    final settings = AppSettingsService.instance;
    await settings.saveRawSetting(
      AppTagPlaybackSettingsStore.retiredAnnounceNoteKey,
      '1',
    );
    await settings.saveRawSetting(
      AppTagPlaybackSettingsStore.speakNotesKey,
      '0',
    );

    await AppTagPlaybackSettingsStore.removeRetiredKeys();

    expect(
      await settings.loadRawSetting(
        AppTagPlaybackSettingsStore.retiredAnnounceNoteKey,
      ),
      isNull,
    );
    expect(
      await settings.loadRawSetting(AppTagPlaybackSettingsStore.speakNotesKey),
      '0',
    );
  });

  test('is harmless when the row is already gone or deletion fails', () async {
    await AppTagPlaybackSettingsStore.removeRetiredKeys();
    await AppTagPlaybackSettingsStore.removeRetiredKeys((_) async {
      throw StateError('database unavailable');
    });
  });
}
