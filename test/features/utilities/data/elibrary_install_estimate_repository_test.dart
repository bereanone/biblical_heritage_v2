import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/elibrary_install_estimate_repository.dart';

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

Future<void> _seedEstimate({
  required Database db,
  required String collectionKey,
  required String format,
  required int fileCount,
  required String source,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'elibrary_install_estimates',
    <String, Object?>{
      'collection_key': collectionKey,
      'format': format,
      'file_count': fileCount,
      'total_size_bytes': 42,
      'size_known': 1,
      'last_checked_utc': now,
      'source': source,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<int> _countEstimates(
  Database db, {
  required String collectionKey,
  required String format,
}) async {
  final rows = await db.rawQuery(
    '''
    SELECT COUNT(*) AS cnt
    FROM elibrary_install_estimates
    WHERE collection_key = ? AND format = ?
    ''',
    [collectionKey, format],
  );
  return rows.isEmpty ? 0 : (rows.first['cnt'] as num?)?.toInt() ?? 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('elibrary_estimate_support_');
    documentsDir = await Directory.systemTemp.createTemp('elibrary_estimate_documents_');
    libraryRootDir = await Directory.systemTemp.createTemp('elibrary_estimate_root_');
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    await LocalSettingsStore.instance.ensureDeviceId();
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
    if (supportDir.existsSync()) {
      await supportDir.delete(recursive: true);
    }
    if (documentsDir.existsSync()) {
      await documentsDir.delete(recursive: true);
    }
    if (libraryRootDir.existsSync()) {
      await libraryRootDir.delete(recursive: true);
    }
  });

  test('falls back to user.db when eLibrary.db has no install estimates', () async {
    final userDb = await UserDatabase.instance.database;
    await ELibraryDatabase.instance.database;
    await _seedEstimate(
      db: userDb,
      collectionKey: 'egw_books',
      format: 'epub',
      fileCount: 12,
      source: 'legacy-user-db',
    );

    final result = await ELibraryInstallEstimateRepository.instance
        .loadByCollectionAndFormat();

    expect(result['egw_books'], isNotNull);
    expect(result['egw_books']!['epub'], isNotNull);
    expect(result['egw_books']!['epub']!.fileCount, 12);
    expect(result['egw_books']!['epub']!.source, 'legacy-user-db');
  });

  test('writes install estimates to eLibrary.db and prefers them on read', () async {
    final userDb = await UserDatabase.instance.database;
    final eLibraryDb = await ELibraryDatabase.instance.database;
    await _seedEstimate(
      db: userDb,
      collectionKey: 'egw_books',
      format: 'epub',
      fileCount: 12,
      source: 'legacy-user-db',
    );

    await ELibraryInstallEstimateRepository.instance.upsertCollectionCount(
      collectionKey: 'egw_books',
      format: 'epub',
      fileCount: 7,
      totalSizeBytes: 123,
      sizeKnown: true,
      source: 'scan',
    );

    expect(
      await _countEstimates(
        eLibraryDb,
        collectionKey: 'egw_books',
        format: 'epub',
      ),
      1,
    );
    expect(
      await _countEstimates(
        userDb,
        collectionKey: 'egw_books',
        format: 'epub',
      ),
      1,
    );

    final result = await ELibraryInstallEstimateRepository.instance
        .loadByCollectionAndFormat();

    expect(result['egw_books'], isNotNull);
    expect(result['egw_books']!['epub'], isNotNull);
    expect(result['egw_books']!['epub']!.fileCount, 7);
    expect(result['egw_books']!['epub']!.totalSizeBytes, 123);
    expect(result['egw_books']!['epub']!.source, 'scan');
  });
}
