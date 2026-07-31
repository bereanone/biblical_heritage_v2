import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/entry/presentation/entry_screen.dart';
import 'package:studybible2/features/library/data/library_setup_invitation_service.dart';

Future<void> _installPathProviderMocks({
  required Directory supportDir,
  required Directory documentsDir,
}) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getApplicationSupportDirectory':
            return supportDir.path;
          case 'getApplicationDocumentsDirectory':
            return documentsDir.path;
          case 'getTemporaryDirectory':
            return supportDir.path;
          case 'getLibraryDirectory':
            return supportDir.path;
        }
        return supportDir.path;
      });
}

Widget _entryApp() => MaterialApp(
  home: EntryScreen(themeMode: AppThemeMode.sepia, onThemeChanged: (_) {}),
);

/// The invitation's showDialog is reached via a postFrameCallback that
/// awaits a real sqflite/file-system Future, which a bare pumpAndSettle()
/// does not reliably wait through in this harness. Mirrors the
/// runAsync+poll pattern already used by test/widget_test.dart.
Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(find.text(text), findsOneWidget);
}

Future<void> _pumpUntilTextGone(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (find.text(text).evaluate().isEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(find.text(text), findsNothing);
}

/// The invitation's markSkipped()/markCompleted() write runs fire-and-forget
/// from a postFrameCallback, so it can still be in flight for a moment
/// after the dialog has visually dismissed. Polls the real persisted state
/// rather than trusting dialog-gone timing alone.
Future<void> _pumpUntilInvitationResolved(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final resolved = await tester.runAsync(
      () => LibrarySetupInvitationService.instance.shouldShowInvitation(),
    );
    if (resolved == false) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(
    await tester.runAsync(
      () => LibrarySetupInvitationService.instance.shouldShowInvitation(),
    ),
    isFalse,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('entry_setup_support_');
    documentsDir = await Directory.systemTemp.createTemp('entry_setup_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp('entry_setup_root_');
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await UserDatabase.instance.close();
    await ELibraryDatabase.instance.close();
    for (final dir in [supportDir, documentsDir, libraryRootDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  testWidgets(
    '1. shows the Set Up My Library invitation on a fresh install, without '
    'hiding the Bible Explorer button underneath',
    (tester) async {
      await tester.pumpWidget(_entryApp());
      await _pumpUntilText(tester, 'Set Up My Library');

      expect(find.text('Bible Explorer'), findsOneWidget);
    },
  );

  testWidgets(
    '2. does not show the invitation again once setup is already completed',
    (tester) async {
      await tester.runAsync(
        () => LibrarySetupInvitationService.instance.markCompleted(),
      );

      await tester.pumpWidget(_entryApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Set Up My Library'), findsNothing);
      expect(find.text('Bible Explorer'), findsOneWidget);
    },
  );

  testWidgets(
    '4. the Bible remains usable: the invitation never hides Bible Explorer, '
    'and merely appearing does not itself persist a resolved state',
    (tester) async {
      await tester.pumpWidget(_entryApp());
      await _pumpUntilText(tester, 'Set Up My Library');

      // The dialog is an overlay, not a screen replacement — Bible
      // Explorer is still in the tree and still says what it says.
      final bibleExplorerFinder = find.text('Bible Explorer');
      expect(bibleExplorerFinder, findsOneWidget);
      expect(tester.widget<Text>(bibleExplorerFinder).data, 'Bible Explorer');

      // Merely showing the invitation must not itself persist "skipped" —
      // only an explicit choice should.
      final stillUnresolved = await tester.runAsync(
        () => LibrarySetupInvitationService.instance.shouldShowInvitation(),
      );
      expect(stillUnresolved, isTrue);
    },
  );

  testWidgets('choosing Skip for Now from the invitation persists it', (
    tester,
  ) async {
    await tester.pumpWidget(_entryApp());
    await _pumpUntilText(tester, 'Set Up My Library');

    await tester.tap(find.widgetWithText(TextButton, 'Skip for Now'));
    await _pumpUntilTextGone(tester, 'Set Up My Library');
    await _pumpUntilInvitationResolved(tester);
  });
}
