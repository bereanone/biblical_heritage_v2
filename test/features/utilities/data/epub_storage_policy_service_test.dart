import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/elibrary_folder_policy.dart';
import 'package:studybible2/features/utilities/data/epub_storage_policy_service.dart';

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
  test('collection EPUB staging folder is positively app-managed', () {
    expect(
      ELibraryFolderPolicy.isManagedEgwFolderPath(
        '/Application Support/ImportedPioneerEpubs/sanctification.epub',
      ),
      isTrue,
    );
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final service = EpubStoragePolicyService.instance;

  group('decide (pure decision matrix)', () {
    test('mobile + removeAfterIndexing + managed + validated removes', () {
      final decision = service.decide(
        platform: EpubStoragePlatform.mobile,
        preference: EpubRetentionPreference.removeAfterIndexing,
        isPositivelyAppManaged: true,
        validationPassed: true,
      );
      expect(decision.shouldRemoveEpub, isTrue);
    });

    test('desktop default (keep) retains even when managed and validated', () {
      final decision = service.decide(
        platform: EpubStoragePlatform.desktop,
        preference: EpubRetentionPreference.keep,
        isPositivelyAppManaged: true,
        validationPassed: true,
      );
      expect(decision.shouldRemoveEpub, isFalse);
    });

    test('desktop with removal preference enabled removes', () {
      final decision = service.decide(
        platform: EpubStoragePlatform.desktop,
        preference: EpubRetentionPreference.removeAfterIndexing,
        isPositivelyAppManaged: true,
        validationPassed: true,
      );
      expect(decision.shouldRemoveEpub, isTrue);
    });

    test('mobile retention preference (keep) is honored', () {
      final decision = service.decide(
        platform: EpubStoragePlatform.mobile,
        preference: EpubRetentionPreference.keep,
        isPositivelyAppManaged: true,
        validationPassed: true,
      );
      expect(decision.shouldRemoveEpub, isFalse);
    });

    test(
      'external/uncertain provenance is never removed regardless of preference',
      () {
        final decision = service.decide(
          platform: EpubStoragePlatform.mobile,
          preference: EpubRetentionPreference.removeAfterIndexing,
          isPositivelyAppManaged: false,
          validationPassed: true,
        );
        expect(decision.shouldRemoveEpub, isFalse);
      },
    );

    test(
      'failed/unvalidated import is never removed regardless of preference',
      () {
        final decision = service.decide(
          platform: EpubStoragePlatform.mobile,
          preference: EpubRetentionPreference.removeAfterIndexing,
          isPositivelyAppManaged: true,
          validationPassed: false,
        );
        expect(decision.shouldRemoveEpub, isFalse);
      },
    );
  });

  group('applyPolicyAfterValidatedImport (file + DB integration)', () {
    late Directory supportDir;
    late Directory documentsDir;
    late Directory libraryRootDir;

    setUp(() async {
      supportDir = await Directory.systemTemp.createTemp(
        'epub_policy_support_',
      );
      documentsDir = await Directory.systemTemp.createTemp(
        'epub_policy_documents_',
      );
      libraryRootDir = await Directory.systemTemp.createTemp(
        'epub_policy_root_',
      );
      LibraryRootService.instance.invalidateCachedSelection();
      await _installPathProviderMocks(
        supportDir: supportDir,
        documentsDir: documentsDir,
      );
      await LibraryRootService.instance.setLibraryRoot(
        path: libraryRootDir.path,
      );
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
      for (final dir in <Directory>[supportDir, documentsDir, libraryRootDir]) {
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    });

    Future<void> seedLibraryItem(String id) async {
      final db = await ELibraryDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('library_items', <String, Object?>{
        'id': id,
        'title': 'Test Book',
        'file_name': p.basename(id),
        'relative_path': id,
        'created_at': now,
        'updated_at': now,
        'device_id': 'test-device',
      });
    }

    test(
      'removes a managed EPUB under a save-space mobile preference and records removal',
      () async {
        await service.saveMobileEpubRetentionPreference(
          EpubRetentionPreference.removeAfterIndexing,
        );
        final relativePath = p.join('ePubs', 'EGW', 'EGW_Books', 'book.epub');
        final epubFile = File(p.join(libraryRootDir.path, relativePath));
        epubFile.parent.createSync(recursive: true);
        epubFile.writeAsStringSync('epub bytes');
        await seedLibraryItem('ITEM1');

        final decision = await service.applyPolicyAfterValidatedImport(
          libraryItemId: 'ITEM1',
          epubFile: epubFile,
          rootPath: libraryRootDir.path,
          platformOverride: EpubStoragePlatform.mobile,
        );

        expect(decision.shouldRemoveEpub, isTrue);
        expect(epubFile.existsSync(), isFalse);
        final db = await ELibraryDatabase.instance.database;
        final rows = await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: <Object?>['ITEM1'],
        );
        expect(rows.single['epub_storage_state'], 'removed_after_index');
        expect(rows.single['epub_removed_at'], isNotNull);
      },
    );

    test(
      'never removes an EPUB outside any managed folder even with a remove preference',
      () async {
        await service.saveMobileEpubRetentionPreference(
          EpubRetentionPreference.removeAfterIndexing,
        );
        final epubFile = File(
          p.join(libraryRootDir.path, 'UserImports', 'external.epub'),
        );
        epubFile.parent.createSync(recursive: true);
        epubFile.writeAsStringSync('epub bytes');
        await seedLibraryItem('ITEM2');

        final decision = await service.applyPolicyAfterValidatedImport(
          libraryItemId: 'ITEM2',
          epubFile: epubFile,
          rootPath: libraryRootDir.path,
        );

        expect(decision.shouldRemoveEpub, isFalse);
        expect(epubFile.existsSync(), isTrue);
        final db = await ELibraryDatabase.instance.database;
        final rows = await db.query(
          'library_items',
          where: 'id = ?',
          whereArgs: <Object?>['ITEM2'],
        );
        expect(rows.single['epub_storage_state'], 'present');
      },
    );
  });
}
