// Opt-in, isolated rehearsal for the restored 1914 CIS EPUB.  It creates a
// fresh Library Root under tool/Verification and never reads or writes a live
// StudyBible2 database.  The existing application cover is copied byte-for-
// byte into this rehearsal root after canonical activation.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_acquisition_batch_runner.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_bulk_import_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_folder_inventory_service.dart';

const _candidateEpub =
    'tool/Verification/cis_1914_restoration/output/'
    'The_Cross_and_Its_Shadow_1914_illustrated_candidate_v5.epub';
const _existingCover = 'assets/library_covers/CIS.png';
const _candidateRoot =
    'tool/Verification/cis_1914_restoration/output/'
    'StudyBible2_CIS_1914_rehearsal_library_root_v5';

Future<void> _installPathProviderMock(String runtimePath) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => runtimePath);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('creates a separate canonical CIS 1914 database rehearsal', () async {
    if (Platform.environment['RUN_CIS_1914_DB_CANDIDATE'] != '1') return;

    final source = File(p.absolute(Platform.environment['CIS_PREVIEW_EPUB'] ?? _candidateEpub));
    final cover = File(p.absolute(_existingCover));
    final root = Directory(p.absolute(Platform.environment['CIS_PREVIEW_ROOT'] ?? _candidateRoot));
    final allowedRoot = p.absolute('tool/Verification/cis_1914_restoration/output');
    expect(p.isWithin(allowedRoot, root.path), isTrue, reason: 'isolated output root only');
    expect(await source.exists(), isTrue, reason: 'build the EPUB first');
    expect(await cover.exists(), isTrue, reason: 'existing CIS cover missing');
    if (Platform.environment['CIS_PREVIEW_RESUME'] != '1') {
      expect(await root.exists(), isFalse,
        reason: 'refusing to overwrite an existing database rehearsal');
    }

    final runtime = Directory(p.join(root.path, '.runtime'));
    await runtime.create(recursive: true);
    await _installPathProviderMock(runtime.path);
    LibraryRootService.instance.invalidateCachedSelection();
    await LibraryRootService.instance.setLibraryRoot(path: root.path);

    try {
      final sourceFolder = source.parent;
      final inventory = await PioneerEpubFolderInventoryService.instance.survey(
        sourceFolder,
      );
      final candidate = inventory.entries.where(
        (entry) => p.basename(entry.absolutePath) == p.basename(source.path),
      );
      expect(candidate, hasLength(1));
      final single = PioneerEpubFolderInventory(
        folderPath: inventory.folderPath,
        scannedAt: inventory.scannedAt,
        entries: candidate.toList(growable: false),
        skippedNonEpubCount: 0,
      );

      final preparation = await PioneerEpubBulkImportService.instance.prepare(
        inventory: single,
      );
      expect(preparation.preparationFailures, isEmpty);
      expect(preparation.targets, hasLength(1));
      final activation = await LibraryAcquisitionBatchRunner.instance.activate(
        preparation.targets,
      );
      expect(activation.readyCount, 1);

      final itemId = preparation.targets.single.libraryItemId;
      final db = await ELibraryDatabase.instance.database;
      final blocks = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM library_document_blocks '
        'WHERE library_item_id = ?',
        <Object?>[itemId],
      );
      final images = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM library_document_blocks '
        "WHERE library_item_id = ? AND lower(block_type) = 'image'",
        <Object?>[itemId],
      );
      final navigation = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM library_document_navigation '
        'WHERE library_item_id = ?',
        <Object?>[itemId],
      );
      expect((blocks.single['c'] as int), greaterThan(0));
      final expectedImages = int.parse(Platform.environment['CIS_PREVIEW_IMAGES'] ?? '18');
      expect((images.single['c'] as int), greaterThanOrEqualTo(expectedImages));
      expect((navigation.single['c'] as int), greaterThanOrEqualTo(62));

      final copiedCover = File(p.join(root.path, 'covers', 'CIS.png'));
      await copiedCover.parent.create(recursive: true);
      await cover.copy(copiedCover.path);
      expect(await copiedCover.length(), await cover.length());
      await db.update(
        'library_items',
        <String, Object?>{'cover_path': 'covers/CIS.png'},
        where: 'id = ?',
        whereArgs: <Object?>[itemId],
      );

      final report = <String, Object?>{
        'edition': 'The Cross and Its Shadow, Stephen N. Haskell, 1914',
        'item_id': itemId,
        'canonical_blocks': blocks.single['c'],
        'canonical_image_blocks': images.single['c'],
        'navigation_nodes': navigation.single['c'],
        'epub_relative_path': (await db.query(
          'library_items',
          columns: const <String>['relative_path'],
          where: 'id = ?',
          whereArgs: <Object?>[itemId],
        )).single['relative_path'],
        'cover_path': 'covers/CIS.png',
        'cover_source': _existingCover,
        'live_library_modified': false,
      };
      await File(p.join(root.path, 'CIS_1914_REHEARSAL_REPORT.json')).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        flush: true,
      );
    } finally {
      await UserDatabase.instance.close();
      await ELibraryDatabase.instance.close();
      LibraryRootService.instance.invalidateCachedSelection();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
    }
  }, timeout: Timeout.none);
}
