import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/presentation/download_ellen_white_library_screen.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('dl_egw_support_');
    documentsDir = await Directory.systemTemp.createTemp('dl_egw_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp('dl_egw_root_');
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
    '5. "Choose Books to Download" reaches the existing eLibrary Setup '
    'selection screen',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DownloadEllenWhiteLibraryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose Books to Download'), findsOneWidget);
      await tester.tap(find.text('Choose Books to Download'));
      // ELibrarySetupScreen (existing, unmodified) keeps some async
      // loading state busy indefinitely outside a real app context, so a
      // full pumpAndSettle here would hang; a few bounded pumps are enough
      // to prove navigation reached it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // The existing, unmodified official-download selection screen.
      expect(find.text('eLibrary Setup'), findsWidgets);
    },
  );

  testWidgets('does not expose a manual "Index Now" step to the user', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DownloadEllenWhiteLibraryScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Index Now'), findsNothing);
  });
}
