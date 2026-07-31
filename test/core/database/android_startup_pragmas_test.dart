import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDirectory;
  late Directory documentsDirectory;
  late Directory libraryRoot;

  setUp(() async {
    await UserDatabase.instance.close();
    await ELibraryDatabase.instance.close();
    supportDirectory = await Directory.systemTemp.createTemp(
      'android_startup_pragmas_support_',
    );
    documentsDirectory = await Directory.systemTemp.createTemp(
      'android_startup_pragmas_documents_',
    );
    libraryRoot = await Directory.systemTemp.createTemp(
      'android_startup_pragmas_library_',
    );

    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          return switch (call.method) {
            'getApplicationSupportDirectory' => supportDirectory.path,
            'getApplicationDocumentsDirectory' => documentsDirectory.path,
            'getTemporaryDirectory' => supportDirectory.path,
            'getLibraryDirectory' => supportDirectory.path,
            _ => supportDirectory.path,
          };
        });

    LibraryRootService.instance.invalidateCachedSelection();
    await LibraryRootService.instance.setLibraryRoot(path: libraryRoot.path);
  });

  tearDown(() async {
    await UserDatabase.instance.close();
    await ELibraryDatabase.instance.close();
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  test('user and eLibrary databases start with WAL enabled', () async {
    final userDatabase = await UserDatabase.instance.database;
    final eLibraryDatabase = await ELibraryDatabase.instance.database;

    final userJournalMode = await userDatabase.rawQuery('PRAGMA journal_mode');
    final eLibraryJournalMode = await eLibraryDatabase.rawQuery(
      'PRAGMA journal_mode',
    );
    final userBusyTimeout = await userDatabase.rawQuery('PRAGMA busy_timeout');
    final eLibraryBusyTimeout = await eLibraryDatabase.rawQuery(
      'PRAGMA busy_timeout',
    );

    expect(userJournalMode.single.values.single, 'wal');
    expect(eLibraryJournalMode.single.values.single, 'wal');
    expect(userBusyTimeout.single.values.single, 5000);
    expect(eLibraryBusyTimeout.single.values.single, 5000);
  });
}
