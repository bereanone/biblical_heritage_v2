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

Future<void> _pumpUntilEntryScreen(WidgetTester tester) async {
  await _pumpUntilText(tester, 'Biblical Heritage StudyBible 2.0');
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

Future<void> _pumpUntilBibleExplorerReady(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (find.byTooltip('History').evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(find.byTooltip('History'), findsWidgets);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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

  testWidgets('shows the entry screen first', (tester) async {
    await tester.pumpWidget(const StudyBibleApp());
    await _pumpUntilEntryScreen(tester);

    expect(find.text('Biblical Heritage StudyBible 2.0'), findsOneWidget);
    expect(find.text('#StudyBible2'), findsOneWidget);
    expect(find.text('Bible Explorer'), findsOneWidget);
  });

  testWidgets('can switch to night theme from the theme button', (
    tester,
  ) async {
    await tester.pumpWidget(const StudyBibleApp());
    await _pumpUntilEntryScreen(tester);

    await tester.tap(find.text('aA'));
    await tester.pumpAndSettle();

    expect(find.text('Night'), findsWidgets);

    await tester.tap(find.text('Night').last);
    await tester.pumpAndSettle();

    expect(find.text('Night'), findsNothing);
  });

  testWidgets('bible explorer button opens the new small explorer screen', (
    tester,
  ) async {
    await tester.pumpWidget(const StudyBibleApp());
    await _pumpUntilEntryScreen(tester);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pump();
    await tester.tap(find.text('Bible Explorer'));
    await _pumpUntilBibleExplorerReady(tester);

    expect(find.textContaining('Genesis'), findsWidgets);
    expect(find.byTooltip('History'), findsWidgets);
    expect(find.byTooltip('Commentary'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
