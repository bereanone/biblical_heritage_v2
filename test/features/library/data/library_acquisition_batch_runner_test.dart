import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/canonical_activation.dart';
import 'package:studybible2/features/library/data/library_acquisition_batch_runner.dart';

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

Uint8List _wellFormedEpubBytes(String title) {
  final opf =
      '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
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
        '<h2>Chapter 1</h2><p>Synthetic filler paragraph text.</p>'.codeUnits,
  });
}

Uint8List _placeholderStubBytes() {
  return _epubBytes(<String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
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
    supportDir = await Directory.systemTemp.createTemp('batch_runner_support_');
    documentsDir = await Directory.systemTemp.createTemp('batch_runner_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp(
      'batch_runner_root_',
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

  Future<void> seedOfficialDownloadItem({
    required String id,
    required String relativePath,
    required String title,
  }) async {
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': id,
      'title': title,
      'file_name': p.basename(relativePath),
      'relative_path': relativePath,
      'file_format': 'epub',
      'source_type': 'official_download',
      'index_status': 'metadata_only',
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
  }

  test(
    '6/7. activate() runs every pending item through the shared orchestration '
    'primitive, continues past a failure, and produces a friendly summary',
    () async {
      await seedOfficialDownloadItem(
        id: 'good-book',
        relativePath: 'good.epub',
        title: 'A Good Book',
      );
      await seedOfficialDownloadItem(
        id: 'bad-book',
        relativePath: 'bad.epub',
        title: 'A Placeholder Book',
      );
      await File(
        p.join(libraryRootDir.path, 'good.epub'),
      ).writeAsBytes(_wellFormedEpubBytes('A Good Book'), flush: true);
      await File(
        p.join(libraryRootDir.path, 'bad.epub'),
      ).writeAsBytes(_placeholderStubBytes(), flush: true);

      final targets = await LibraryAcquisitionBatchRunner.instance
          .loadPendingOfficialDownloadItems();
      expect(targets, hasLength(2));

      final progressUpdates = <LibraryAcquisitionBatchProgress>[];
      final result = await LibraryAcquisitionBatchRunner.instance.activate(
        targets,
        onProgress: progressUpdates.add,
      );

      expect(result.outcomes, hasLength(2));
      expect(result.readyCount, 1);
      expect(result.unavailableOutcomes, hasLength(1));
      expect(progressUpdates, isNotEmpty);
      // Both items were attempted even though one failed — a failure never
      // stops the rest of the batch.
      expect(result.outcomes.map((o) => o.libraryItemId).toSet(), {
        'good-book',
        'bad-book',
      });
    },
  );

  test('14. an item with an already-current canonical generation is excluded '
      'from the pending list (reused, not reactivated)', () async {
    await seedOfficialDownloadItem(
      id: 'already-ready',
      relativePath: 'ready.epub',
      title: 'Already Ready',
    );
    final file = File(p.join(libraryRootDir.path, 'ready.epub'));
    await file.writeAsBytes(_wellFormedEpubBytes('Already Ready'), flush: true);
    final db = await ELibraryDatabase.instance.database;
    final firstOutcome = await CanonicalActivation.activate(
      db: db,
      libraryItemId: 'already-ready',
      source: file,
    );
    expect(firstOutcome.phase, LibraryAcquisitionPhase.ready);

    final targets = await LibraryAcquisitionBatchRunner.instance
        .loadPendingOfficialDownloadItems();

    expect(targets, isEmpty);
  });

  test('failedTargets only includes items that did not end up ready', () async {
    await seedOfficialDownloadItem(
      id: 'ok-book',
      relativePath: 'ok.epub',
      title: 'OK Book',
    );
    await seedOfficialDownloadItem(
      id: 'fail-book',
      relativePath: 'fail.epub',
      title: 'Failing Book',
    );
    await File(
      p.join(libraryRootDir.path, 'ok.epub'),
    ).writeAsBytes(_wellFormedEpubBytes('OK Book'), flush: true);
    await File(
      p.join(libraryRootDir.path, 'fail.epub'),
    ).writeAsBytes(_placeholderStubBytes(), flush: true);

    final targets = await LibraryAcquisitionBatchRunner.instance
        .loadPendingOfficialDownloadItems();
    final result = await LibraryAcquisitionBatchRunner.instance.activate(
      targets,
    );

    expect(result.failedTargets.map((t) => t.libraryItemId), ['fail-book']);
  });
}
