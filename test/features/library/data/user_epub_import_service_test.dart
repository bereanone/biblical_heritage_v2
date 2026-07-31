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
