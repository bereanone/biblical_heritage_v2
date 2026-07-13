import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/elibrary_database.dart';
import 'pioneer_book_package_import_service.dart';
import 'pioneer_capture_folder_metadata.dart';

enum StudyCollectionBookStatus { newBook, update, current, needsAttention }

class StudyCollectionBook {
  const StudyCollectionBook({
    required this.workId,
    required this.title,
    required this.author,
    required this.path,
    required this.sha256,
    required this.packageId,
    required this.contentHash,
    this.status = StudyCollectionBookStatus.newBook,
  });
  final String workId;
  final String title;
  final String author;
  final String path;
  final String sha256;
  final String packageId;
  final String contentHash;
  final StudyCollectionBookStatus status;

  StudyCollectionBook withStatus(StudyCollectionBookStatus value) =>
      StudyCollectionBook(
        workId: workId,
        title: title,
        author: author,
        path: path,
        sha256: sha256,
        packageId: packageId,
        contentHash: contentHash,
        status: value,
      );
}

class StudyCollectionInventory {
  const StudyCollectionInventory({
    required this.collectionId,
    required this.books,
  });
  final String collectionId;
  final List<StudyCollectionBook> books;
}

class PioneerStudyCollectionService {
  const PioneerStudyCollectionService({
    this.managedImportRootPath,
    this.hasReadyLocalItem,
  });

  final Future<String> Function()? managedImportRootPath;
  final Future<bool> Function(StudyCollectionBook book)? hasReadyLocalItem;

  Future<StudyCollectionInventory> inspect(String sourcePath) async {
    if (p.extension(sourcePath).toLowerCase() != '.studycollection') {
      throw const FormatException('Select a .studycollection file.');
    }
    final archive = ZipDecoder().decodeBytes(
      await File(sourcePath).readAsBytes(),
      verify: true,
    );
    if (archive.length > 1000) {
      throw const FormatException('Collection has too many entries.');
    }
    final names = <String>{};
    var expanded = 0;
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (entry.isSymbolicLink ||
          p.posix.isAbsolute(name) ||
          p.windows.isAbsolute(name) ||
          name.split('/').contains('..') ||
          !names.add(name)) {
        throw const FormatException('Collection contains an unsafe entry.');
      }
      expanded += entry.size;
      if (expanded > 1024 * 1024 * 1024) {
        throw const FormatException('Collection expanded size is too large.');
      }
    }
    final inventoryEntries = archive
        .where((entry) => entry.name == 'inventory.json')
        .toList();
    if (inventoryEntries.length != 1) {
      throw const FormatException(
        'Collection must contain one root inventory.json.',
      );
    }
    final decoded = jsonDecode(
      utf8.decode(inventoryEntries.single.readBytes()!),
    );
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['books'] is! List) {
      throw const FormatException('Collection inventory is invalid.');
    }
    final books = <StudyCollectionBook>[];
    final workIds = <String>{};
    for (final raw in decoded['books'] as List) {
      if (raw is! Map) {
        throw const FormatException('Collection book entry is invalid.');
      }
      final workId = raw['workId']?.toString() ?? '';
      final path = raw['path']?.toString() ?? '';
      final expectedHash = raw['sha256']?.toString() ?? '';
      if (!RegExp(r'^[A-Z][A-Z0-9_-]{1,63}$').hasMatch(workId) ||
          !workIds.add(workId) ||
          path != 'books/$workId.studybook') {
        throw const FormatException(
          'Collection inventory identity is invalid.',
        );
      }
      final matches = archive.where((entry) => entry.name == path).toList();
      if (matches.length != 1 ||
          sha256.convert(matches.single.readBytes()!).toString() !=
              expectedHash) {
        throw FormatException(
          '$workId does not match the collection inventory.',
        );
      }
      books.add(
        StudyCollectionBook(
          workId: workId,
          title: raw['title']?.toString() ?? workId,
          author: raw['author']?.toString() ?? '',
          path: path,
          sha256: expectedHash,
          packageId: raw['packageId']?.toString() ?? '',
          contentHash: raw['contentHash']?.toString() ?? '',
        ),
      );
    }
    return StudyCollectionInventory(
      collectionId:
          decoded['collectionId']?.toString() ??
          p.basenameWithoutExtension(sourcePath),
      books: List.unmodifiable(books),
    );
  }

  Future<StudyCollectionInventory> compareWithLocal(
    StudyCollectionInventory inventory,
  ) async {
    final root =
        await (managedImportRootPath?.call() ??
            PioneerBookPackageImportService.instance.managedImportRootPath());
    final compared = <StudyCollectionBook>[];
    for (final book in inventory.books) {
      final folder = Directory(p.join(root, book.workId));
      if (!await folder.exists()) {
        compared.add(book.withStatus(StudyCollectionBookStatus.newBook));
        continue;
      }
      final local = PioneerCaptureFolderMetadata.fromFolder(folder);
      final ready =
          await (hasReadyLocalItem?.call(book) ?? _hasReadyLocalItem(book));
      if (!ready) {
        compared.add(book.withStatus(StudyCollectionBookStatus.newBook));
        continue;
      }
      final status =
          (local.packageId?.isNotEmpty ?? false) &&
              local.packageId != book.packageId
          ? StudyCollectionBookStatus.needsAttention
          : local.packageId == book.packageId &&
                local.contentHash == book.contentHash
          ? StudyCollectionBookStatus.current
          : StudyCollectionBookStatus.update;
      compared.add(book.withStatus(status));
    }
    return StudyCollectionInventory(
      collectionId: inventory.collectionId,
      books: List.unmodifiable(compared),
    );
  }

  Future<bool> _hasReadyLocalItem(StudyCollectionBook book) async {
    final db = await ELibraryDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT 1
      FROM library_items
      WHERE source_work_id = ?
        AND source_package_id = ?
        AND index_status IN ('indexed', 'indexed_empty')
        AND deleted_at IS NULL
        AND is_missing = 0
      LIMIT 1
      ''',
      <Object?>[book.workId, book.packageId],
    );
    return rows.isNotEmpty;
  }

  Future<List<PioneerBookPackageImportResult>> importSelected(
    String sourcePath,
    Iterable<String> selectedWorkIds,
  ) async {
    final inventory = await inspect(sourcePath);
    final selected = selectedWorkIds.toSet();
    final allowed = inventory.books
        .where((book) => selected.contains(book.workId))
        .toList();
    final archive = ZipDecoder().decodeBytes(
      await File(sourcePath).readAsBytes(),
      verify: true,
    );
    final temp = await Directory.systemTemp.createTemp('studycollection-');
    try {
      final results = <PioneerBookPackageImportResult>[];
      for (final book in allowed) {
        final entry = archive.singleWhere(
          (candidate) => candidate.name == book.path,
        );
        final file = File(p.join(temp.path, '${book.workId}.studybook'));
        await file.writeAsBytes(entry.readBytes()!, flush: true);
        results.add(
          await PioneerBookPackageImportService.instance.importPackage(
            file.path,
          ),
        );
      }
      return results;
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
