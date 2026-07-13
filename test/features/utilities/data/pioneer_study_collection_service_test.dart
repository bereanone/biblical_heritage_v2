import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_study_collection_service.dart';

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
}
