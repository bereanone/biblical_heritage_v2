import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_folder_inventory_service.dart';

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
  required String title,
  String author = 'A. Pioneer Author',
  bool includeCover = false,
  String bodyText = 'Synthetic filler paragraph text for a Pioneer book.',
}) {
  final opf =
      '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>$title</dc:title>
    <dc:creator>$author</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="chap0" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    ${includeCover ? '<item id="cover-image" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>' : ''}
  </manifest>
  <spine>
    <itemref idref="chap0"/>
  </spine>
</package>
''';
  final files = <String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
    'OEBPS/content.opf': opf.codeUnits,
    'OEBPS/ch1.xhtml': '<h2>Chapter 1</h2><p>$bodyText</p>'.codeUnits,
  };
  if (includeCover) {
    files['OEBPS/cover.jpg'] = List<int>.filled(16, 0);
  }
  return _epubBytes(files);
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
  late Directory sourceFolder;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('pioneer_inv_support_');
    documentsDir = await Directory.systemTemp.createTemp('pioneer_inv_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp('pioneer_inv_root_');
    sourceFolder = await Directory.systemTemp.createTemp('pioneer_inv_source_');
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
    for (final dir in [
      supportDir,
      documentsDir,
      libraryRootDir,
      sourceFolder,
    ]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  test('2/3. only .epub candidates are inventoried; zip/json/hidden files are '
      'ignored', () async {
    await File(
      p.join(sourceFolder.path, 'Book One.epub'),
    ).writeAsBytes(_wellFormedEpubBytes(title: 'Book One'), flush: true);
    await File(p.join(sourceFolder.path, 'notes.json')).writeAsString('{}');
    await File(
      p.join(sourceFolder.path, 'archive.zip'),
    ).writeAsBytes([1, 2, 3]);
    await File(p.join(sourceFolder.path, '.DS_Store')).writeAsBytes([0]);

    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );

    expect(inventory.totalFound, 1);
    expect(inventory.skippedNonEpubCount, 3);
  });

  test('Pioneer OPF display metadata is decoded and deduplicated', () async {
    await File(p.join(sourceFolder.path, 'Daily.epub')).writeAsBytes(
      _wellFormedEpubBytes(
        title: '&quot;The Daily&quot;&#13;&quot;The Daily&quot;&#13;The Daily',
        author: 'E. J; Waggoner',
      ),
      flush: true,
    );

    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );

    expect(inventory.entries.single.title, 'The Daily');
    expect(inventory.entries.single.author, 'E. J. Waggoner');
  });

  test('4. source EPUBs are opened read-only and never modified', () async {
    final file = File(p.join(sourceFolder.path, 'Untouched.epub'));
    final bytes = _wellFormedEpubBytes(title: 'Untouched Book');
    await file.writeAsBytes(bytes, flush: true);
    final statBefore = await file.stat();

    await PioneerEpubFolderInventoryService.instance.survey(sourceFolder);

    final statAfter = await file.stat();
    expect(await file.readAsBytes(), bytes);
    expect(statAfter.modified, statBefore.modified);
  });

  test('5. structurally invalid EPUBs are reported but not treated as '
      'importable', () async {
    await File(
      p.join(sourceFolder.path, 'Placeholder.epub'),
    ).writeAsBytes(_placeholderStubBytes(), flush: true);

    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );

    expect(inventory.totalFound, 1);
    expect(inventory.validCount, 0);
    expect(inventory.invalidCount, 1);
    expect(inventory.needsImportCount, 0);
    expect(inventory.entries.single.rejectionReason, isNotNull);
  });

  test('8/10. stable identity is deterministic across separate survey runs '
      'and distinct works with similar titles remain distinct', () async {
    await File(p.join(sourceFolder.path, 'gc1.epub')).writeAsBytes(
      _wellFormedEpubBytes(title: 'The Great Controversy'),
      flush: true,
    );
    await File(p.join(sourceFolder.path, 'gc2.epub')).writeAsBytes(
      _wellFormedEpubBytes(
        title: 'The Great Controversy Between Christ and Satan',
      ),
      flush: true,
    );

    final first = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );
    final second = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );

    final firstIds = first.entries.map((e) => e.libraryItemId).toSet();
    final secondIds = second.entries.map((e) => e.libraryItemId).toSet();
    expect(firstIds, secondIds, reason: 'identity must be deterministic');
    expect(
      firstIds.length,
      2,
      reason: 'two differently-titled works must not collapse into one id',
    );
  });

  test('probable duplicate/alternate-edition candidates are surfaced, not '
      'silently merged', () async {
    await File(p.join(sourceFolder.path, 'edition_a.epub')).writeAsBytes(
      _wellFormedEpubBytes(title: 'Steps to Christ', author: 'Ellen White'),
      flush: true,
    );
    await File(p.join(sourceFolder.path, 'edition_b.epub')).writeAsBytes(
      _wellFormedEpubBytes(
        title: 'Steps To Christ',
        author: 'Ellen  White',
        bodyText: 'A slightly different scan of the same classic work.',
      ),
      flush: true,
    );

    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );

    expect(inventory.probableDuplicateGroups, hasLength(1));
    expect(inventory.probableDuplicateGroups.values.single, hasLength(2));
    // Still two distinct library item identities — never auto-merged.
    expect(inventory.entries.map((e) => e.libraryItemId).toSet(), hasLength(2));
  });

  test('19. missing covers are counted without blocking import', () async {
    await File(p.join(sourceFolder.path, 'no_cover.epub')).writeAsBytes(
      _wellFormedEpubBytes(title: 'No Cover Book', includeCover: false),
      flush: true,
    );
    await File(p.join(sourceFolder.path, 'has_cover.epub')).writeAsBytes(
      _wellFormedEpubBytes(title: 'Has Cover Book', includeCover: true),
      flush: true,
    );

    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      sourceFolder,
    );

    expect(inventory.validCount, 2);
    expect(inventory.missingCoverCount, 1);
    expect(inventory.needsImportCount, 2);
  });
}
