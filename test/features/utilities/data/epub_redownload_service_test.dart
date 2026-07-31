import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/epub_redownload_service.dart';

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
  late Directory rootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('redownload_support_');
    documentsDir = await Directory.systemTemp.createTemp(
      'redownload_documents_',
    );
    rootDir = await Directory.systemTemp.createTemp('redownload_root_');
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: rootDir.path);
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
    for (final dir in <Directory>[supportDir, documentsDir, rootDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  test('reports itemNotFound for an unknown library item id', () async {
    final result = await EpubRedownloadService.instance.ensureEpubAvailable(
      libraryItemId: 'does-not-exist',
    );
    expect(result.outcome, EpubRedownloadOutcome.itemNotFound);
  });

  test('reports alreadyAvailable when the EPUB was never removed', () async {
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': 'present-item',
      'title': 'Still Here',
      'file_name': 'here.epub',
      'relative_path': 'ePubs/EGW/EGW_Books/here.epub',
      'file_format': 'epub',
      'collection_name': 'EGW Books',
      'epub_storage_state': 'present',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });

    final result = await EpubRedownloadService.instance.ensureEpubAvailable(
      libraryItemId: 'present-item',
    );
    expect(result.outcome, EpubRedownloadOutcome.alreadyAvailable);
  });

  test(
    'reports downloadFailed without any network call for an unrecognized collection',
    () async {
      final db = await ELibraryDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('library_items', <String, Object?>{
        'id': 'weird-collection-item',
        'title': 'Mystery Book',
        'file_name': 'mystery.epub',
        'relative_path': 'ePubs/EGW/EGW_Books/mystery.epub',
        'file_format': 'epub',
        'collection_name': 'Not A Real Collection',
        'epub_storage_state': 'removed_after_index',
        'epub_removed_at': now,
        'created_at': now,
        'updated_at': now,
        'device_id': 'test-device',
      });

      final result = await EpubRedownloadService.instance.ensureEpubAvailable(
        libraryItemId: 'weird-collection-item',
      );
      expect(result.outcome, EpubRedownloadOutcome.downloadFailed);
    },
  );
}
