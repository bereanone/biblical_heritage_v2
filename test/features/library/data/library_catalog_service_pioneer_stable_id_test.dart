import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_item_identity.dart';

/// Covers the Pioneer identity-preservation half of the ID-migration repair:
/// `LibraryCatalogService._repairManagedItemIds` (catalog hydration's
/// path-based ID rewrite) must never touch a `pioneer_epub_import` row, even
/// though its relative path lives under a folder that
/// `isManagedEgwRelativePath` otherwise treats as rewritable. This is what
/// stops the historical defect (419 Pioneer generations orphaned by
/// hydration silently renaming visible IDs) from recurring.
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

const _containerXml = '''
<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

const _opfXml = '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata>
    <dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Pioneer Work</dc:title>
  </metadata>
  <manifest>
    <item id="content1" href="content1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="content1"/>
  </spine>
</package>
''';

const _healthyContentXhtml = '''
<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter One</title></head>
<body>
<h1>Chapter One</h1>
<p>A genuinely readable Pioneer chapter with enough real narrative text.</p>
<p>A second paragraph so the structural validator sees real body content.</p>
</body>
</html>
''';

File _writeHealthyEpub(File file) {
  final archive = Archive();
  final entries = <String, String>{
    'META-INF/container.xml': _containerXml,
    'OEBPS/content.opf': _opfXml,
    'OEBPS/content1.xhtml': _healthyContentXhtml,
  };
  entries.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(ZipEncoder().encode(archive));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'pioneer_stable_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'pioneer_stable_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'pioneer_stable_root_',
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
    if (supportDir.existsSync()) await supportDir.delete(recursive: true);
    if (documentsDir.existsSync()) await documentsDir.delete(recursive: true);
    if (libraryRootDir.existsSync()) {
      await libraryRootDir.delete(recursive: true);
    }
  });

  Future<void> seedPioneerRow({
    required String id,
    required String relativePath,
  }) async {
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': id,
      'title': p.basenameWithoutExtension(relativePath),
      'file_name': p.basename(relativePath),
      'relative_path': relativePath,
      'file_format': 'epub',
      'folder_type': 'pioneer_epub_import',
      'library_role': 'pioneer_epub_import',
      'collection_name': 'Pioneer Library',
      'source_type': 'pioneer_epub_import',
      'index_status': 'indexed',
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('library_document_conversion', <String, Object?>{
      'library_item_id': id,
      'canonicalizer_version': 1,
      'source_hash': 'seed-hash',
      'status': 'complete',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>?> fetchItem(String id) async {
    final db = await ELibraryDatabase.instance.database;
    final rows = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> conversionOwnedBy(String id) async {
    final db = await ELibraryDatabase.instance.database;
    final rows = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: [id],
    );
    return rows.isNotEmpty;
  }

  Future<int> refresh() => LibraryCatalogService.instance
      .refreshManagedItemsFromDisk(rootPathOverride: libraryRootDir.path);

  // The four production legacy IDs the migration must preserve exactly,
  // paired with a plausible relative path for each.
  const legacyIds = <String, String>{
    'library_item_research_pioneer_stephen_nelson_haskell_CIS':
        'stephen_nelson_haskell_cis.epub',
    'library_item_research_pioneer_stephen_nelson_haskell_SSP':
        'stephen_nelson_haskell_ssp.epub',
    'library_item_research_pioneer_a_t_jones_CWCP_ATJ': 'a_t_jones_cwcp.epub',
    'library_item_research_pioneer_daniel_t_bordeau_aplib_d_t_bordeau_sanctification_epub_d826c638':
        'daniel_t_bordeau_sanctification.epub',
  };

  for (final entry in legacyIds.entries) {
    test(
      '13/14: refresh never rewrites the legacy Pioneer ID ${entry.key}',
      () async {
        final relativePath = p.join('ImportedPioneerEpubs', entry.value);
        _writeHealthyEpub(File(p.join(libraryRootDir.path, relativePath)));
        await seedPioneerRow(id: entry.key, relativePath: relativePath);

        // Sanity check: this path is normally eligible for path-based
        // rewriting under the plain EGW folder policy, so the skip below is
        // actually being exercised and not a vacuous pass.
        final wouldBeCanonicalId = canonicalLibraryItemId(
          folderType: 'pioneer_epub_import',
          relativePath: relativePath,
        );
        expect(wouldBeCanonicalId, isNot(entry.key));

        await refresh();

        final row = await fetchItem(entry.key);
        expect(
          row,
          isNotNull,
          reason: 'the legacy visible ID must still be addressable',
        );
        expect(
          await fetchItem(wouldBeCanonicalId),
          isNull,
          reason: 'hydration must not have rewritten to a path-based ID',
        );
        expect(
          await conversionOwnedBy(entry.key),
          isTrue,
          reason:
              '15: canonical conversion must remain immediately current '
              'under the stable ID with no rebuild/re-ownership needed',
        );
      },
    );
  }

  test('14: a non-Pioneer managed EGW item at an equivalent path IS still '
      'repaired to its path-based canonical ID (control case)', () async {
    final relativePath = p.join(
      'ePubs',
      'EGW',
      'EGW_Books',
      'great_controversy.epub',
    );
    _writeHealthyEpub(File(p.join(libraryRootDir.path, relativePath)));
    const legacyId = 'library_item_research_some_legacy_egw_id';
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': legacyId,
      'title': 'Great Controversy',
      'file_name': 'great_controversy.epub',
      'relative_path': relativePath,
      'file_format': 'epub',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'EGW Books',
      'source_type': 'official_download',
      'index_status': 'indexed',
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final expectedCanonicalId = canonicalLibraryItemId(
      folderType: 'research',
      relativePath: relativePath,
    );
    expect(expectedCanonicalId, isNot(legacyId));

    await refresh();

    expect(
      await fetchItem(expectedCanonicalId),
      isNotNull,
      reason:
          'non-Pioneer managed items must still be repaired to their '
          'path-based canonical ID; the skip is Pioneer-specific',
    );
  });
}
