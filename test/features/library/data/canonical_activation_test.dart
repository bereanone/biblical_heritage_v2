import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/canonical_activation.dart';

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

Uint8List _wellFormedEpubBytes({
  required Map<String, String> chapters,
  String title = 'Synthetic Test Book',
}) {
  final manifestItems = StringBuffer();
  final spineItems = StringBuffer();
  var index = 0;
  for (final href in chapters.keys) {
    final id = 'chap$index';
    manifestItems.writeln(
      '<item id="$id" href="$href" media-type="application/xhtml+xml"/>',
    );
    spineItems.writeln('<itemref idref="$id"/>');
    index++;
  }
  final opf =
      '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
  </metadata>
  <manifest>
    $manifestItems
  </manifest>
  <spine>
    $spineItems
  </spine>
</package>
''';
  final files = <String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
    'OEBPS/content.opf': opf.codeUnits,
  };
  chapters.forEach((href, html) {
    files['OEBPS/$href'] = html.codeUnits;
  });
  return _epubBytes(files);
}

/// A structurally-incomplete package shaped like EGW's media CDN teaser
/// response: container.xml points at an OPF that doesn't exist in the
/// archive. Synthetic only; no real book content.
Uint8List _placeholderStubBytes() {
  return _epubBytes(<String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory rootDir;
  late Directory supportDir;
  late Directory documentsDir;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    rootDir = await Directory.systemTemp.createTemp('canonical_activation_');
    supportDir = await Directory.systemTemp.createTemp(
      'canonical_activation_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'canonical_activation_docs_',
    );
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    db = await openDatabase(p.join(rootDir.path, 'test.db'));
    await ELibrarySchema.ensure(db);
  });

  tearDown(() async {
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await UserDatabase.instance.close();
    for (final dir in [rootDir, supportDir, documentsDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  Future<void> seedLibraryItem(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': id,
      'title': 'Synthetic Test Book',
      'file_name': '$id.epub',
      'relative_path': '$id.epub',
      'file_format': 'epub',
      'source_type': 'official_download',
      'epub_storage_state': 'present',
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
  }

  Future<List<Map<String, Object?>>> blocksFor(String itemId) => db.query(
    'library_document_blocks',
    where: 'library_item_id = ?',
    whereArgs: <Object?>[itemId],
  );

  test('a fresh valid EPUB activates and reports ready', () async {
    const itemId = 'FRESH';
    await seedLibraryItem(itemId);
    final file = File(p.join(rootDir.path, '$itemId.epub'));
    await file.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'ch1.xhtml': '<h2>Chapter 1</h2><p>Synthetic paragraph text.</p>',
        },
      ),
      flush: true,
    );

    final outcome = await CanonicalActivation.activate(
      db: db,
      libraryItemId: itemId,
      source: file,
    );

    expect(outcome.phase, LibraryAcquisitionPhase.ready);
    expect(outcome.isReady, isTrue);
    expect(outcome.hasReadableCanonicalGeneration, isTrue);
    expect(outcome.sourceFilePresent, isTrue);
    expect(outcome.retryable, isFalse);
    expect(await blocksFor(itemId), isNotEmpty);
  });

  test(
    'an unchanged source is skipped deterministically on a second call',
    () async {
      const itemId = 'UNCHANGED';
      await seedLibraryItem(itemId);
      final file = File(p.join(rootDir.path, '$itemId.epub'));
      await file.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: <String, String>{
            'ch1.xhtml': '<h2>Chapter 1</h2><p>Synthetic paragraph text.</p>',
          },
        ),
        flush: true,
      );

      final first = await CanonicalActivation.activate(
        db: db,
        libraryItemId: itemId,
        source: file,
      );
      final blocksAfterFirst = await blocksFor(itemId);

      final second = await CanonicalActivation.activate(
        db: db,
        libraryItemId: itemId,
        source: file,
      );
      final blocksAfterSecond = await blocksFor(itemId);

      expect(first.phase, LibraryAcquisitionPhase.ready);
      expect(second.phase, LibraryAcquisitionPhase.ready);
      expect(second.technicalDetail, contains('skipped'));
      expect(
        blocksAfterSecond.map((row) => row['content_hash']),
        blocksAfterFirst.map((row) => row['content_hash']),
        reason: 'unchanged source must not trigger a rebuild',
      );
    },
  );

  test(
    'a placeholder package with no prior generation returns sourceUnavailable '
    'and is not exposed as readable',
    () async {
      const itemId = 'PLACEHOLDER';
      await seedLibraryItem(itemId);
      final file = File(p.join(rootDir.path, '$itemId.epub'));
      await file.writeAsBytes(_placeholderStubBytes(), flush: true);

      final outcome = await CanonicalActivation.activate(
        db: db,
        libraryItemId: itemId,
        source: file,
      );

      expect(outcome.phase, LibraryAcquisitionPhase.sourceUnavailable);
      expect(outcome.isReady, isFalse);
      expect(outcome.hasReadableCanonicalGeneration, isFalse);
      expect(outcome.retryable, isFalse);
      expect(await blocksFor(itemId), isEmpty);
    },
  );

  test(
    'a corrupted replacement does not replace a prior valid generation',
    () async {
      const itemId = 'RETAINED';
      await seedLibraryItem(itemId);
      final file = File(p.join(rootDir.path, '$itemId.epub'));
      await file.writeAsBytes(
        _wellFormedEpubBytes(
          chapters: <String, String>{
            'ch1.xhtml': '<h2>Chapter 1</h2><p>Synthetic paragraph text.</p>',
          },
        ),
        flush: true,
      );
      final firstOutcome = await CanonicalActivation.activate(
        db: db,
        libraryItemId: itemId,
        source: file,
      );
      expect(firstOutcome.phase, LibraryAcquisitionPhase.ready);
      final blocksBeforeCorruption = await blocksFor(itemId);
      expect(blocksBeforeCorruption, isNotEmpty);

      await file.writeAsBytes(_placeholderStubBytes(), flush: true);
      final outcome = await CanonicalActivation.activate(
        db: db,
        libraryItemId: itemId,
        source: file,
      );

      expect(
        outcome.phase,
        LibraryAcquisitionPhase.retainedFromPriorGeneration,
      );
      expect(outcome.hasReadableCanonicalGeneration, isTrue);
      expect(await blocksFor(itemId), blocksBeforeCorruption);
    },
  );

  test('an exception reading a missing source preserves the prior generation '
      'and returns failedImport', () async {
    const itemId = 'EXCEPTION';
    await seedLibraryItem(itemId);
    final file = File(p.join(rootDir.path, '$itemId.epub'));
    await file.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'ch1.xhtml': '<h2>Chapter 1</h2><p>Synthetic paragraph text.</p>',
        },
      ),
      flush: true,
    );
    final firstOutcome = await CanonicalActivation.activate(
      db: db,
      libraryItemId: itemId,
      source: file,
    );
    expect(firstOutcome.phase, LibraryAcquisitionPhase.ready);
    final blocksBefore = await blocksFor(itemId);

    // Delete the file out from under a would-be rebuild attempt so
    // source.readAsBytes() throws before the canonicalizer's own
    // try/catch even begins (that guard starts after the read).
    await file.delete();

    final outcome = await CanonicalActivation.activate(
      db: db,
      libraryItemId: itemId,
      source: file,
    );

    expect(outcome.phase, LibraryAcquisitionPhase.failedImport);
    expect(outcome.retryable, isTrue);
    expect(outcome.hasReadableCanonicalGeneration, isTrue);
    expect(outcome.technicalDetail, isNotNull);
    expect(
      await blocksFor(itemId),
      blocksBefore,
      reason: 'a failed rebuild attempt must preserve the prior generation',
    );
  });

  test('applying the storage policy never removes a source outside any '
      'app-managed folder', () async {
    const itemId = 'NOT_MANAGED';
    await seedLibraryItem(itemId);
    final unmanagedDir = Directory(p.join(rootDir.path, 'CloudFiles'));
    await unmanagedDir.create(recursive: true);
    final file = File(p.join(unmanagedDir.path, '$itemId.epub'));
    await file.writeAsBytes(
      _wellFormedEpubBytes(
        chapters: <String, String>{
          'ch1.xhtml': '<h2>Chapter 1</h2><p>Synthetic paragraph text.</p>',
        },
      ),
      flush: true,
    );

    final outcome = await CanonicalActivation.activate(
      db: db,
      libraryItemId: itemId,
      source: file,
      applyStoragePolicy: true,
      rootPath: rootDir.path,
    );

    expect(outcome.phase, LibraryAcquisitionPhase.ready);
    expect(outcome.storagePolicyRemovedManagedCopyOnly, isFalse);
    expect(
      await file.exists(),
      isTrue,
      reason: 'CloudFiles-style sources must never be removed',
    );
  });
}
