import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/app/study_bible_app.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:studybible2/core/theme/theme_preferences.dart';

import 'support/fake_audioplayers_platform.dart';
import 'package:studybible2/core/audio/synthesis_thermal_gate.dart';

Future<void> _pumpUntilEntryScreen(WidgetTester tester) async {
  await _pumpUntilText(tester, 'Biblical Heritage #StudyBible');
}

Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(find.text(text), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  installFakeAudioplayers();

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    await UserDatabase.instance.close();
    await ELibraryDatabase.instance.close();
    supportDir = await Directory.systemTemp.createTemp('widget_support_');
    documentsDir = await Directory.systemTemp.createTemp('widget_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp('widget_library_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getApplicationSupportDirectory' => supportDir.path,
            'getApplicationDocumentsDirectory' => documentsDir.path,
            'getTemporaryDirectory' => supportDir.path,
            'getLibraryDirectory' => supportDir.path,
            _ => supportDir.path,
          };
        });
    LibraryRootService.instance.invalidateCachedSelection();
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    final mode = await ThemePreferences.instance.loadThemeMode();
    await AppSettingsService.instance.applyThemePreset(mode);
    await AppSettingsService.instance.loadVisualSettings(mode);
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  testWidgets(
    'temperature notice is non-modal, does not repeat, and clears on resume',
    (tester) async {
      final thermal = SynthesisThermalGate.instance;
      thermal.waitingForTemperature.value = false;
      await tester.pumpWidget(const StudyBibleApp());
      await _pumpUntilEntryScreen(tester);
      thermal.waitingForTemperature.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(
          'Paused to let your phone cool down. Audio generation will resume when it’s safe.',
        ),
        findsOneWidget,
      );
      thermal.waitingForTemperature.value = true;
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      // The notification does not take over navigation or block controls.
      await tester.tap(find.text('aA'));
      await tester.pumpAndSettle();
      expect(find.text('Night'), findsWidgets);
      await tester.tap(find.text('Night').last);
      await tester.pumpAndSettle();
      thermal.waitingForTemperature.value = false;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Paused to let your phone cool down.'),
        findsNothing,
      );
      expect(
        find.text('The phone has cooled. Audio creation can resume.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
