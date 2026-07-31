import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/canonical_activation.dart';
import 'package:studybible2/features/library/data/library_acquisition_orchestrator.dart';

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

/// Synthetic CaptureClipper-style folder: a `metadata.json` plus a plain
/// captured HTML file. No real book content — filler prose only.
Future<Directory> _createCaptureFolder({
  required Directory parent,
  required String folderName,
  required String title,
  required String workId,
}) async {
  final folder = Directory(p.join(parent.path, folderName));
  await folder.create(recursive: true);
  await File(p.join(folder.path, 'metadata.json')).writeAsString('''
{
  "title": "$title",
  "abbreviation": "$workId",
  "work_id": "$workId",
  "source_type": "pioneer_captured_html",
  "source_site": "user_capture",
  "source_url": "https://example.invalid/$workId"
}
''');
  await File(p.join(folder.path, 'capture.html')).writeAsString('''
<!doctype html>
<html>
  <head><title>$title</title></head>
  <body>
    <h1>$title</h1>
    <p>Synthetic chapter one filler paragraph for orchestration testing.</p>
  </body>
</html>
''');
  return folder;
}

Uint8List _epubBytes(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const String _containerXml = '''
<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

Uint8List _wellFormedEpubBytes() {
  const opf = '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Synthetic Individual Import</dc:title>
  </metadata>
  <manifest>
    <item id="chap0" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chap0"/>
  </spine>
</package>
''';
  return _epubBytes(<String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
    'OEBPS/content.opf': opf.codeUnits,
    'OEBPS/ch1.xhtml':
        '<h2>Chapter 1</h2><p>Synthetic individual EPUB body text.</p>'
            .codeUnits,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  late Directory scratchDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('acq_orch_support_');
    documentsDir = await Directory.systemTemp.createTemp('acq_orch_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp('acq_orch_root_');
    scratchDir = await Directory.systemTemp.createTemp('acq_orch_scratch_');
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
    for (final dir in [supportDir, documentsDir, libraryRootDir, scratchDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  test('prepareCaptureFolder explicitly activates the canonical generation; '
      'the reader is never opened', () async {
    final folder = await _createCaptureFolder(
      parent: scratchDir,
      folderName: 'ONEBOOK',
      title: 'Synthetic Capture One',
      workId: 'onebook',
    );

    final outcomes = await LibraryAcquisitionOrchestrator.instance
        .prepareCaptureFolder(folderPath: folder.path);

    expect(outcomes, hasLength(1));
    expect(outcomes.single.phase, LibraryAcquisitionPhase.ready);
    expect(outcomes.single.hasReadableCanonicalGeneration, isTrue);

    // Confirm activation happened for real (blocks exist in the
    // canonical schema) without the canonical reader ever being invoked.
    final db = await ELibraryDatabase.instance.database;
    final conversion = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[outcomes.single.libraryItemId],
    );
    expect(conversion.single['status'], 'complete');
    final blocks = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[outcomes.single.libraryItemId],
    );
    expect(blocks, isNotEmpty);
  });

  test('importing a folder with two capture books activates exactly two items '
      'with no recursive routing loop', () async {
    await _createCaptureFolder(
      parent: scratchDir,
      folderName: 'BOOKA',
      title: 'Synthetic Capture A',
      workId: 'booka',
    );
    await _createCaptureFolder(
      parent: scratchDir,
      folderName: 'BOOKB',
      title: 'Synthetic Capture B',
      workId: 'bookb',
    );

    final outcomes = await LibraryAcquisitionOrchestrator.instance
        .prepareCaptureFolder(folderPath: scratchDir.path);

    expect(outcomes, hasLength(2));
    expect(
      outcomes.every((o) => o.phase == LibraryAcquisitionPhase.ready),
      isTrue,
    );
    expect(
      outcomes.map((o) => o.libraryItemId).toSet(),
      hasLength(2),
      reason: 'each capture must be activated exactly once',
    );
  });

  test('prepareExistingEpub activates an individually-imported EPUB and never '
      'removes a source outside any app-managed folder', () async {
    const itemId = 'individual-epub';
    const relativePath = 'individual.epub';
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': itemId,
      'title': 'Synthetic Individual Import',
      'file_name': relativePath,
      'relative_path': relativePath,
      'file_format': 'epub',
      'source_type': 'user_import',
      'epub_storage_state': 'present',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    final file = File(p.join(libraryRootDir.path, relativePath));
    await file.writeAsBytes(_wellFormedEpubBytes(), flush: true);

    final outcome = await LibraryAcquisitionOrchestrator.instance
        .prepareExistingEpub(libraryItemId: itemId, relativePath: relativePath);

    expect(outcome.phase, LibraryAcquisitionPhase.ready);
    expect(outcome.storagePolicyRemovedManagedCopyOnly, isFalse);
    expect(
      await file.exists(),
      isTrue,
      reason: 'a non-app-managed EPUB must never be removed',
    );
  });

  test('rebuildCanonicalCopy re-canonicalizes a single item from its resolved '
      'source file without applying the storage policy', () async {
    const itemId = 'rebuild-me';
    const relativePath = 'rebuild.epub';
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': itemId,
      'title': 'Synthetic Rebuild Target',
      'file_name': relativePath,
      'relative_path': relativePath,
      'file_format': 'epub',
      'source_type': 'official_download',
      'epub_storage_state': 'present',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    final file = File(p.join(libraryRootDir.path, relativePath));
    await file.writeAsBytes(_wellFormedEpubBytes(), flush: true);

    final outcome = await LibraryAcquisitionOrchestrator.instance
        .rebuildCanonicalCopy(libraryItemId: itemId);

    expect(outcome.phase, LibraryAcquisitionPhase.ready);
    expect(await file.exists(), isTrue);
  });
}
