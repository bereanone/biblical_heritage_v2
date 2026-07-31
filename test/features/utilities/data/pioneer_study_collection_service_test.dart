import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_study_collection_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';
import 'package:studybible2/features/utilities/data/pioneer_text_import_service.dart';

PioneerImportWorkResult _importedEpubResult(StudyCollectionBook item) {
  final work = PioneerSourceWork(
    id: item.workId,
    authorId: 'test_author',
    authorName: item.author,
    title: item.title,
    abbreviation: 'TEST',
    group: 'Pioneer Authors',
    subgroup: 'EPUB',
    availability: PioneerSourceAvailability.available,
    verified: true,
    catalogImportable: true,
    sourceType: 'epub',
    sourceUrl: null,
    sourceLabel: 'test',
    notes: null,
  );
  return PioneerImportWorkResult(
    work: work,
    status: PioneerImportWorkStatus.imported,
    stage: 'complete',
    sourceMethod: PioneerImportSourceMethod.directUrl,
    reason: 'Imported.',
    libraryItemId: work.stableLibraryItemId,
    sourceType: 'epub',
    insertedLibraryItems: 1,
    insertedNavigationItems: 1,
    insertedTextBlocks: 1,
    skippedExisting: false,
    refCodeHandlingSummary: '',
    detail: null,
    exceptionType: null,
    httpStatusCode: null,
    contentType: 'application/epub+zip',
    downloadedByteCount: null,
    parsedSectionCount: 1,
    parsedParagraphCount: 1,
    requiresManualVerification: false,
    manualVerificationHint: null,
    epubAvailable: true,
    epubValidated: true,
  );
}

void main() {
  test('reads and verifies embedded collection inventory', () async {
    final temp = await Directory.systemTemp.createTemp('studycollection_');
    addTearDown(() => temp.delete(recursive: true));
    final book = utf8.encode('PK fixture');
    final inventory = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'collectionId': 'Pioneers',
        'books': [
          {
            'workId': 'CIS',
            'title': 'The Consecrated Way',
            'author': 'A. T. Jones',
            'path': 'books/CIS.studybook',
            'sha256': sha256.convert(book).toString(),
          },
        ],
      }),
    );
    final archive = Archive()
      ..addFile(ArchiveFile('books/CIS.studybook', book.length, book))
      ..addFile(ArchiveFile('inventory.json', inventory.length, inventory));
    final file = File('${temp.path}/Pioneers.studycollection')
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    final result = await const PioneerStudyCollectionService().inspect(
      file.path,
    );
    expect(result.collectionId, 'Pioneers');
    expect(result.books.single.workId, 'CIS');
  });

  test(
    'extracted package is not current until its library item is ready',
    () async {
      final root = await Directory.systemTemp.createTemp('collection_local_');
      addTearDown(() => root.delete(recursive: true));
      final folder = Directory('${root.path}/WOR')..createSync();
      File('${folder.path}/manifest.json').writeAsStringSync(
        jsonEncode({
          'schemaVersion': 2,
          'workId': 'WOR',
          'packageId': 'captureclipper:WOR',
          'contentHash': 'current-hash',
          'createdAt': '2026-07-01T00:00:00Z',
          'updatedAt': '2026-07-01T00:00:00Z',
          'title': 'Waggoner on Romans',
          'author': 'E. J. Waggoner',
          'shortCode': 'WOR',
          'htmlFile': 'capture.html',
        }),
      );
      const book = StudyCollectionBook(
        workId: 'WOR',
        title: 'Waggoner on Romans',
        author: 'E. J. Waggoner',
        path: 'books/WOR.studybook',
        sha256: 'package-hash',
        packageId: 'captureclipper:WOR',
        contentHash: 'current-hash',
      );
      final service = PioneerStudyCollectionService(
        managedImportRootPath: () async => root.path,
        hasReadyLocalItem: (_) async => false,
      );

      final result = await service.compareWithLocal(
        const StudyCollectionInventory(collectionId: 'Pioneers', books: [book]),
      );

      expect(result.books.single.status, StudyCollectionBookStatus.newBook);
    },
  );

  test('schema 2 preserves typed EPUB metadata and display order', () async {
    final temp = await Directory.systemTemp.createTemp('studycollection_v2_');
    addTearDown(() => temp.delete(recursive: true));
    final epub = utf8.encode('PK epub fixture');
    final cover = utf8.encode('png fixture');
    final inventory = utf8.encode(
      jsonEncode({
        'schemaVersion': 2,
        'collectionId': 'PioneerEPUBs',
        'items': [
          {
            'type': 'epub',
            'source_work_id': 'sanctification',
            'title': 'Sanctification',
            'author': 'Daniel T. Bordeau',
            'path': 'items/sanctification.epub',
            'sha256': sha256.convert(epub).toString(),
            'cover': 'covers/sanctification.png',
            'displayOrder': 2,
            'categories': ['Pioneer Authors', 'Holiness'],
          },
        ],
      }),
    );
    final archive = Archive()
      ..addFile(ArchiveFile('items/sanctification.epub', epub.length, epub))
      ..addFile(ArchiveFile('covers/sanctification.png', cover.length, cover))
      ..addFile(ArchiveFile('inventory.json', inventory.length, inventory));
    final file = File('${temp.path}/PioneerEPUBs.studycollection')
      ..writeAsBytesSync(ZipEncoder().encode(archive));

    final result = await const PioneerStudyCollectionService().inspect(
      file.path,
    );

    final item = result.items.single;
    expect(item.itemType, StudyCollectionItemType.epub);
    expect(item.workId, 'sanctification');
    expect(item.coverPath, 'covers/sanctification.png');
    expect(item.displayOrder, 2);
    expect(item.categories, ['Pioneer Authors', 'Holiness']);
  });

  test(
    'schema 2 dispatches EPUB and PDF items to injected pipelines',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'studycollection_dispatch_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final epub = utf8.encode('PK epub fixture');
      final pdf = utf8.encode('%PDF fixture');
      final inventory = utf8.encode(
        jsonEncode({
          'schemaVersion': 2,
          'collectionId': 'Mixed',
          'items': [
            {
              'type': 'epub',
              'sourceWorkId': 'epub_work',
              'title': 'EPUB Work',
              'author': 'Author One',
              'path': 'items/epub_work.epub',
              'sha256': sha256.convert(epub).toString(),
            },
            {
              'type': 'pdf',
              'sourceWorkId': 'pdf_work',
              'title': 'PDF Work',
              'author': 'Author Two',
              'path': 'items/pdf_work.pdf',
              'sha256': sha256.convert(pdf).toString(),
            },
          ],
        }),
      );
      final archive = Archive()
        ..addFile(ArchiveFile('items/epub_work.epub', epub.length, epub))
        ..addFile(ArchiveFile('items/pdf_work.pdf', pdf.length, pdf))
        ..addFile(ArchiveFile('inventory.json', inventory.length, inventory));
      final file = File('${temp.path}/Mixed.studycollection')
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      final calls = <String>[];
      final managed = Directory('${temp.path}/managed')..createSync();
      final service = PioneerStudyCollectionService(
        managedEpubRootPath: () async => managed.path,
        epubImporter: (path, item) async {
          calls.add('epub:${item.workId}:${File(path).existsSync()}');
          return _importedEpubResult(item);
        },
        pdfImporter: (path, item) async {
          calls.add('pdf:${item.workId}:${File(path).existsSync()}');
        },
      );

      final result = await service.importSelectedItems(file.path, {
        'epub_work',
        'pdf_work',
      });

      expect(calls, ['epub:epub_work:true', 'pdf:pdf_work:true']);
      expect(result.epubResults.single.isImported, isTrue);
      expect(result.pdfWorkIds, ['pdf_work']);
    },
  );
}
