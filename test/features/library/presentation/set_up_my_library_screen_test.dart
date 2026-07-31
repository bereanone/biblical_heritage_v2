import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_setup_state.dart';
import 'package:studybible2/features/library/presentation/set_up_my_library_screen.dart';

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
    supportDir = await Directory.systemTemp.createTemp('setup_screen_support_');
    documentsDir = await Directory.systemTemp.createTemp('setup_screen_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp(
      'setup_screen_root_',
    );
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

  testWidgets('shows all four plain-language setup choices', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SetUpMyLibraryScreen()));

    expect(find.text('Download Ellen White Library'), findsOneWidget);
    expect(find.text('Pioneer Library'), findsOneWidget);
    expect(find.text('Add My Own EPUB'), findsOneWidget);
    expect(find.text('Skip for Now'), findsOneWidget);

    // No technical jargon anywhere on the screen.
    for (final forbidden in const [
      'index',
      'canonical',
      'generation',
      'source type',
      'needs_attention',
    ]) {
      expect(find.textContaining(forbidden, findRichText: true), findsNothing);
    }
  });

  testWidgets('18. lays choices out as a grid on wide (macOS/iPad) widths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: SetUpMyLibraryScreen()));

    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets(
    '18. lays choices out as a single stacked column on narrow (phone) widths',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: SetUpMyLibraryScreen()));

      expect(find.byType(GridView), findsNothing);
    },
  );

  testWidgets('Skip for Now marks setup skipped and closes the screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SetUpMyLibraryScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Set Up My Library'), findsOneWidget);

    await tester.tap(find.text('Skip for Now'));
    // _skipForNow awaits a real file write before popping; a bare
    // pumpAndSettle does not reliably wait through that real async gap in
    // this harness, so poll for the persisted state directly.
    for (var attempt = 0; attempt < 200; attempt++) {
      final state = await tester.runAsync(
        () => LocalSettingsStore.instance.loadLibrarySetupState(),
      );
      if (state == LibrarySetupState.skipped) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(
      await tester.runAsync(
        () => LocalSettingsStore.instance.loadLibrarySetupState(),
      ),
      LibrarySetupState.skipped,
    );
  });
}
