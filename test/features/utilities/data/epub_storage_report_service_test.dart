import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/epub_storage_report_service.dart';

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
    supportDir = await Directory.systemTemp.createTemp(
      'storage_report_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'storage_report_documents_',
    );
    rootDir = await Directory.systemTemp.createTemp('storage_report_root_');
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

  Future<void> seedItem({
    required String id,
    required String relativePath,
  }) async {
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': id,
      'title': 'Report Book',
      'file_name': p.basename(relativePath),
      'relative_path': relativePath,
      'file_format': 'epub',
      'collection_name': 'EGW Books',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    await db.insert('library_document_sections', <String, Object?>{
      'id': 'sec1',
      'library_item_id': id,
      'display_order': 0,
      'title': 'Section',
      'source_href': 'ch1.xhtml',
      'content_hash': 'h',
    });
    await db.insert('library_document_blocks', <String, Object?>{
      'id': 'b1',
      'library_item_id': id,
      'section_id': 'sec1',
      'display_order': 0,
      'block_type': 'paragraph',
      'plain_text': 'Twenty characters!!',
      'formatted_content': '{"version":1,"nodes":[]}',
      'content_hash': 'h1',
    });
  }

  test(
    'reports canonical/asset/epub sizes and nonzero estimated savings while the EPUB is present',
    () async {
      const relativePath = 'ePubs/EGW/EGW_Books/report.epub';
      await seedItem(id: 'ITEM_R1', relativePath: relativePath);
      final epubFile = File(p.join(rootDir.path, relativePath));
      epubFile.parent.createSync(recursive: true);
      epubFile.writeAsBytesSync(List<int>.filled(500, 1));
      final assetDir = Directory(
        p.join(epubFile.parent.path, '_canonical_assets', 'ITEM_R1'),
      );
      assetDir.createSync(recursive: true);
      File(
        p.join(assetDir.path, 'a.png'),
      ).writeAsBytesSync(List<int>.filled(30, 2));

      final report = await EpubStorageReportService.instance.reportFor(
        'ITEM_R1',
      );

      expect(report.epubPresent, isTrue);
      expect(report.epubSizeBytes, 500);
      expect(report.assetSizeBytes, 30);
      expect(report.canonicalTextSizeBytes, greaterThan(0));
      expect(report.estimatedSavingsIfEpubRemovedBytes, 500);
      expect(
        report.totalOfflineSizeBytes,
        report.canonicalTextSizeBytes + 30 + 500,
      );
    },
  );

  test(
    'reports zero epub size and zero estimated savings once the EPUB has been removed',
    () async {
      const relativePath = 'ePubs/EGW/EGW_Books/removed.epub';
      await seedItem(id: 'ITEM_R2', relativePath: relativePath);
      // Deliberately do not create the EPUB file on disk.

      final report = await EpubStorageReportService.instance.reportFor(
        'ITEM_R2',
      );

      expect(report.epubPresent, isFalse);
      expect(report.epubSizeBytes, 0);
      expect(report.estimatedSavingsIfEpubRemovedBytes, 0);
    },
  );
}
