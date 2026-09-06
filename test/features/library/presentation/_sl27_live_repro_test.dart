// TEMPORARY repro harness — not part of the suite, delete after use.
//
// Seeds a fresh, minimal eLibrary.db with SL27's *exact* real rows (exported
// from the live production database) rather than copying the full 1.7GB
// live file, which was far too slow to open/migrate inside the widget-test
// harness.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';

const _logPath =
    '/private/tmp/claude-501/-Users-deanbowen-Development-StudyBible2/'
    '92698911-edaa-4c20-b060-379a005c3113/scratchpad/sl27_trace.log';

void _log(String message) {
  File(_logPath).writeAsStringSync('$message\n', mode: FileMode.append);
  debugPrint(message);
}

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

  testWidgets('SL27 live repro: trace headings while scrolling', (
    tester,
  ) async {
    File(_logPath).writeAsStringSync('');
    _log('SL27_TRACE start');

    final supportDir = await Directory.systemTemp.createTemp(
      'sl27_repro_support_',
    );
    final documentsDir = await Directory.systemTemp.createTemp(
      'sl27_repro_docs_',
    );
    final libraryRootDir = await Directory.systemTemp.createTemp(
      'sl27_repro_root_',
    );

    addTearDown(() async {
      LibraryRootService.instance.invalidateCachedSelection();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await UserDatabase.instance.close();
      await ELibraryDatabase.instance.close();
      for (final dir in [supportDir, documentsDir, libraryRootDir]) {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      }
    });

    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    _log('SL27_TRACE path provider mocks installed');

    LibraryRootService.instance.invalidateCachedSelection();
    await LibraryRootService.instance.setLibraryRoot(
      path: libraryRootDir.path,
    );
    await LocalSettingsStore.instance.ensureDeviceId();
    _log('SL27_TRACE library root set');

    // Force normal schema creation via the app's own bootstrap path (fresh,
    // empty DB — fast), then seed it with SL27's exact real rows exported
    // from the live production database.
    final db = await ELibraryDatabase.instance.database;
    _log('SL27_TRACE eLibrary.db opened/created');

    final seedSql = await File(
      '/private/tmp/claude-501/-Users-deanbowen-Development-StudyBible2/'
      '92698911-edaa-4c20-b060-379a005c3113/scratchpad/sl27_seed.sql',
    ).readAsString();
    final statements = seedSql
        .split(RegExp(r';\s*\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    await db.transaction((txn) async {
      for (final statement in statements) {
        await txn.execute(statement);
      }
    });
    _log('SL27_TRACE seed rows inserted');

    final rows = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: ['library_item_research_pioneer_at_jones_sl27'],
      limit: 1,
    );
    final sl27 = LibraryCatalogItem.fromRow(
      rows.single,
      rootPath: libraryRootDir.path,
    );
    _log('SL27_TRACE loaded catalog item: ${sl27.id} / ${sl27.title}');

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryBookReaderScreen(
          item: sl27,
          enableCanonicalReader: false,
        ),
      ),
    );
    _log('SL27_TRACE pumpWidget done');

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    _log('SL27_TRACE initial pump loop done');

    final listFinder = find.byType(ScrollablePositionedList);
    _log('SL27_TRACE scrollable list found: ${listFinder.evaluate().length}');

    for (var i = 0; i < 60; i++) {
      if (listFinder.evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 200));
        continue;
      }
      await tester.drag(listFinder, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 300));
      _log('SL27_TRACE drag step $i done');
    }

    _log('SL27_TRACE scroll loop complete');
    expect(tester.takeException(), isNull);
  });
}
