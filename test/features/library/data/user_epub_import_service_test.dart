import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_acquisition_orchestrator.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/data/user_epub_import_service.dart';
import 'package:studybible2/features/library/presentation/library_acquisition_status_text.dart';

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

Uint8List _wellFormedEpubBytes() {
  const opf = '''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>My Own Synthetic Book</dc:title>
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
        '<h2>Chapter 1</h2><p>Synthetic filler text for a user-added book.</p>'
            .codeUnits,
  });
}

Uint8List _notAnEpubAtAll() =>
    Uint8List.fromList('this is not a zip'.codeUnits);

const _sl27FixturePath =
    '/Users/deanbowen/Library/CloudStorage/OneDrive-Personal/CloudFiles/Books/SL27.epub';

/// Mirrors the Capture Clipper pattern used by SL27: a nav entry targets a
/// standalone anchor immediately before its semantic heading, not the
/// heading element's own id.
Uint8List _anchoredNavigationEpubBytes() {
  const opf = '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Anchored book</dc:title></metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="nav"/><itemref idref="content"/></spine>
</package>''';
  const nav = '''<html xmlns:epub="http://www.idpf.org/2007/ops"><body>
<nav epub:type="toc"><ol>
  <li><a href="content.xhtml#first">First real section</a></li>
  <li><a href="content.xhtml#second">Second real section</a></li>
  <li><a href="content.xhtml#missing">Dead link</a></li>
</ol></nav></body></html>''';
  const content = '''<html><body>
<a id="first"></a><h1 id="heading-one">First real section</h1><p>One.</p>
<p class="byline"><strong>By A. Writer</strong></p>
<a id="second"></a><h2 id="heading-two">Second real section</h2><p>Two.</p>
</body></html>''';
  return _epubBytes(<String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
    'OEBPS/content.opf': opf.codeUnits,
    'OEBPS/nav.xhtml': nav.codeUnits,
    'OEBPS/content.xhtml': content.codeUnits,
  });
}

/// A single physical spine file holding three logical chapters, addressed
/// only by an NCX navMap's internal anchors -- the real SL27/Capture
/// Clipper shape (one big captured-HTML file per book, not one per
/// chapter). Regression coverage for the bug where every chapter's
/// paragraphs inherited whichever heading the canonicalizer picked as the
/// whole file's title, so "APPENDIX A" content showed up mislabeled under
/// "INTRODUCTION".
Uint8List _singleSpineFileWithMultipleChaptersEpubBytes() {
  const opf = '''
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>SL27-shaped book</dc:title></metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="content"/></spine>
</package>''';
  const ncx = '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="np1"><navLabel><text>INTRODUCTION</text></navLabel><content src="content.xhtml#introduction"/></navPoint>
    <navPoint id="np2"><navLabel><text>ARGUMENT</text></navLabel><content src="content.xhtml#argument"/></navPoint>
    <navPoint id="np3"><navLabel><text>APPENDIX A</text></navLabel><content src="content.xhtml#appendixa"/></navPoint>
  </navMap>
</ncx>''';
  const content = '''<html><body>
<a id="introduction"></a><h1>INTRODUCTION</h1><p>Introductory remarks.</p>
<a id="argument"></a><h1>ARGUMENT</h1><p>The argument itself.</p>
<a id="appendixa"></a><h1>APPENDIX A</h1><p>Supplementary material.</p>
</body></html>''';
  return _epubBytes(<String, List<int>>{
    'mimetype': 'application/epub+zip'.codeUnits,
    'META-INF/container.xml': _containerXml.codeUnits,
    'OEBPS/content.opf': opf.codeUnits,
    'OEBPS/toc.ncx': ncx.codeUnits,
    'OEBPS/content.xhtml': content.codeUnits,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  late Directory pickedDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('user_epub_support_');
    documentsDir = await Directory.systemTemp.createTemp('user_epub_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp('user_epub_root_');
    pickedDir = await Directory.systemTemp.createTemp('user_epub_picked_');
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
    for (final dir in [supportDir, documentsDir, libraryRootDir, pickedDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  test(
    '12. a valid picked EPUB is copied, validated, and prepared without ever '
    'opening the reader',
    () async {
      final picked = File(p.join(pickedDir.path, 'My Own Book.epub'));
      await picked.writeAsBytes(_wellFormedEpubBytes(), flush: true);

      final imported = await UserEpubImportService.instance.copyIntoLibrary(
        picked.path,
      );
      expect(
        imported.relativePath.replaceAll('\\', '/'),
        startsWith('ePubs/MyBooks/'),
      );
      // The originally-picked file is untouched.
      expect(await picked.exists(), isTrue);

      final outcome = await LibraryAcquisitionOrchestrator.instance
          .prepareExistingEpub(
            libraryItemId: imported.libraryItemId,
            relativePath: imported.relativePath,
          );

      expect(outcome.isReady, isTrue);
      expect(libraryAcquisitionFriendlyText(outcome), 'Ready to read.');

      final db = await ELibraryDatabase.instance.database;
      final blocks = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: <Object?>[imported.libraryItemId],
      );
      expect(
        blocks,
        isNotEmpty,
        reason: 'canonical activation happened directly, not via the reader',
      );
    },
  );

  test(
    'EPUB nav anchors remain reachable and do not promote bylines',
    () async {
      final picked = File(p.join(pickedDir.path, 'Anchored Book.epub'));
      await picked.writeAsBytes(_anchoredNavigationEpubBytes(), flush: true);
      final imported = await UserEpubImportService.instance.copyIntoLibrary(
        picked.path,
      );
      final outcome = await LibraryAcquisitionOrchestrator.instance
          .prepareExistingEpub(
            libraryItemId: imported.libraryItemId,
            relativePath: imported.relativePath,
          );
      expect(outcome.isReady, isTrue);

      final db = await ELibraryDatabase.instance.database;
      final navigation = await db.query(
        'library_navigation_items',
        columns: const <String>['label', 'href', 'anchor_id'],
        where: 'library_item_id = ?',
        whereArgs: <Object?>[imported.libraryItemId],
        orderBy: 'sort_order',
      );
      expect(
        navigation.map((row) => row['label']),
        orderedEquals(<String>['First real section', 'Second real section']),
      );
      expect(
        navigation.map((row) => row['anchor_id']),
        orderedEquals(<String>['first', 'second']),
      );

      final headings = await db.query(
        'library_document_blocks',
        columns: const <String>['plain_text', 'source_anchor', 'source_href'],
        where: 'library_item_id = ? AND block_type = ?',
        whereArgs: <Object?>[imported.libraryItemId, 'heading'],
        orderBy: 'display_order',
      );
      expect(
        headings.map((row) => row['plain_text']),
        orderedEquals(<String>['First real section', 'Second real section']),
      );
      expect(
        headings.map((row) => row['source_anchor']),
        orderedEquals(<String>['first', 'second']),
      );
    },
  );

  test(
    'a single spine file holding multiple chapters via NCX anchors gets its '
    'own distinct section per chapter, so APPENDIX A content is never '
    'attributed to the INTRODUCTION section (SL27 regression)',
    () async {
      final picked = File(p.join(pickedDir.path, 'SL27-Shaped Book.epub'));
      await picked.writeAsBytes(
        _singleSpineFileWithMultipleChaptersEpubBytes(),
        flush: true,
      );
      final imported = await UserEpubImportService.instance.copyIntoLibrary(
        picked.path,
      );
      final outcome = await LibraryAcquisitionOrchestrator.instance
          .prepareExistingEpub(
            libraryItemId: imported.libraryItemId,
            relativePath: imported.relativePath,
          );
      expect(outcome.isReady, isTrue);

      final db = await ELibraryDatabase.instance.database;
      final headings = await db.query(
        'library_document_blocks',
        columns: const <String>['plain_text', 'source_anchor', 'section_id'],
        where: 'library_item_id = ? AND block_type = ?',
        whereArgs: <Object?>[imported.libraryItemId, 'heading'],
        orderBy: 'display_order',
      );
      expect(
        headings.map((row) => row['plain_text']),
        orderedEquals(<String>['INTRODUCTION', 'ARGUMENT', 'APPENDIX A']),
      );
      // Each chapter's own heading must not be duplicated (the original bug:
      // every chapter in the shared file inherited the same first-found
      // section title).
      expect(
        headings.where((row) => row['plain_text'] == 'INTRODUCTION').length,
        1,
      );

      final sections = await db.query(
        'library_document_sections',
        columns: const <String>['id', 'title', 'source_href'],
        where: 'library_item_id = ?',
        whereArgs: <Object?>[imported.libraryItemId],
        orderBy: 'display_order',
      );
      expect(
        sections.map((row) => row['title']),
        orderedEquals(<String>['INTRODUCTION', 'ARGUMENT', 'APPENDIX A']),
      );
      // All three chapters still physically live in the one spine file.
      expect(
        sections.map((row) => row['source_href']).toSet(),
        hasLength(1),
      );
      // Every heading's own section carries the matching title, not
      // whichever chapter happened to be scanned first in that file.
      final sectionTitleById = {
        for (final row in sections) row['id']: row['title'],
      };
      for (final heading in headings) {
        expect(
          sectionTitleById[heading['section_id']],
          heading['plain_text'],
        );
      }
    },
  );

  test(
    'SL27 preserves every Capture Clipper TOC destination and local heading',
    () async {
      final source = File(_sl27FixturePath);
      expect(await source.exists(), isTrue, reason: _sl27FixturePath);
      final imported = await UserEpubImportService.instance.copyIntoLibrary(
        source.path,
      );
      final outcome = await LibraryAcquisitionOrchestrator.instance
          .prepareExistingEpub(
            libraryItemId: imported.libraryItemId,
            relativePath: imported.relativePath,
          );
      expect(outcome.isReady, isTrue);

      final db = await ELibraryDatabase.instance.database;
      final navigation = await db.query(
        'library_navigation_items',
        columns: const <String>['label', 'anchor_id'],
        where: 'library_item_id = ?',
        whereArgs: <Object?>[imported.libraryItemId],
        orderBy: 'sort_order',
      );
      // The EPUB's 13 authored TOC destinations must all survive. Additional
      // semantic headings are allowed only when they also resolve below.
      expect(navigation.length, greaterThanOrEqualTo(13));
      final headings = await db.query(
        'library_document_blocks',
        columns: const <String>['plain_text', 'source_anchor'],
        where: 'library_item_id = ? AND block_type = ?',
        whereArgs: <Object?>[imported.libraryItemId, 'heading'],
      );
      for (final destination in navigation) {
        final label = destination['label']?.toString() ?? '';
        final anchor = destination['anchor_id']?.toString() ?? '';
        expect(anchor, isNotEmpty, reason: label);
        expect(
          headings.any(
            (heading) =>
                heading['source_anchor'] == anchor &&
                heading['plain_text'] == label,
          ),
          isTrue,
          reason: 'TOC entry "$label" must resolve to its own heading.',
        );
      }
      expect(
        headings.where((row) => row['plain_text'] == 'INTRODUCTION').length,
        1,
      );

      final canonicalDestinations = await LibraryDocumentRepository(
        db,
      ).loadCanonicalNavigationDestinations(imported.libraryItemId);
      expect(canonicalDestinations.length, navigation.length);
      for (var index = 0; index < canonicalDestinations.length; index++) {
        expect(canonicalDestinations[index].label, navigation[index]['label']);
        expect(
          canonicalDestinations[index].block.sourceAnchor,
          navigation[index]['anchor_id'],
        );
      }
    },
  );

  test(
    '13. an invalid file shows friendly failure text, not a raw error',
    () async {
      final picked = File(p.join(pickedDir.path, 'Not A Book.epub'));
      await picked.writeAsBytes(_notAnEpubAtAll(), flush: true);

      final imported = await UserEpubImportService.instance.copyIntoLibrary(
        picked.path,
      );
      final outcome = await LibraryAcquisitionOrchestrator.instance
          .prepareExistingEpub(
            libraryItemId: imported.libraryItemId,
            relativePath: imported.relativePath,
          );

      expect(outcome.isReady, isFalse);
      final friendly = libraryAcquisitionFriendlyText(outcome);
      expect(
        friendly,
        anyOf(
          'A readable edition is not currently available from the source.',
          'The selected book is not a readable EPUB.',
          'The book could not be prepared for reading. The source file was '
              'not altered.',
        ),
      );
      expect(friendly, isNot(contains('Exception')));
      expect(friendly, isNot(contains('FormatException')));
    },
  );

  test(
    'a user-imported EPUB is never placed under a managed EGW folder path',
    () async {
      final picked = File(p.join(pickedDir.path, 'Another Book.epub'));
      await picked.writeAsBytes(_wellFormedEpubBytes(), flush: true);
      final imported = await UserEpubImportService.instance.copyIntoLibrary(
        picked.path,
      );
      expect(imported.relativePath.toLowerCase(), isNot(contains('egw')));
    },
  );
}
