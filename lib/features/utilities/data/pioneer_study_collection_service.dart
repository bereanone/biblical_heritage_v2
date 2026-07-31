import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/elibrary_database.dart';
import 'epub_storage_policy_service.dart';
import 'pioneer_book_package_import_service.dart';
import 'pioneer_capture_folder_metadata.dart';
import 'pioneer_source_catalog.dart';
import 'pioneer_text_import_service.dart';

enum StudyCollectionBookStatus { newBook, update, current, needsAttention }

enum StudyCollectionItemType { studybook, epub, pdf }

class StudyCollectionBook {
  const StudyCollectionBook({
    required this.workId,
    required this.title,
    required this.author,
    required this.path,
    required this.sha256,
    required this.packageId,
    required this.contentHash,
    this.itemType = StudyCollectionItemType.studybook,
    this.coverPath,
    this.displayOrder = 0,
    this.categories = const <String>[],
    this.status = StudyCollectionBookStatus.newBook,
  });
  final String workId;
  final String title;
  final String author;
  final String path;
  final String sha256;
  final String packageId;
  final String contentHash;
  final StudyCollectionItemType itemType;
  final String? coverPath;
  final int displayOrder;
  final List<String> categories;
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
        itemType: itemType,
        coverPath: coverPath,
        displayOrder: displayOrder,
        categories: categories,
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
  List<StudyCollectionBook> get items => books;
}

class StudyCollectionImportBatchResult {
  const StudyCollectionImportBatchResult({
    required this.studybookResults,
    required this.epubResults,
    required this.pdfWorkIds,
  });
  final List<PioneerBookPackageImportResult> studybookResults;
  final List<PioneerImportWorkResult> epubResults;
  final List<String> pdfWorkIds;
  int get importedCount =>
      studybookResults.length +
      epubResults.where((result) => result.isImported).length;
}

class PioneerStudyCollectionService {
  const PioneerStudyCollectionService({
    this.managedImportRootPath,
    this.hasReadyLocalItem,
    this.studybookImporter,
    this.epubImporter,
    this.pdfImporter,
    this.managedEpubRootPath,
  });

  final Future<String> Function()? managedImportRootPath;
  final Future<bool> Function(StudyCollectionBook book)? hasReadyLocalItem;
  final Future<PioneerBookPackageImportResult> Function(
    String path,
    StudyCollectionBook item,
  )?
  studybookImporter;
  final Future<PioneerImportWorkResult> Function(
    String path,
    StudyCollectionBook item,
  )?
  epubImporter;
  final Future<void> Function(String path, StudyCollectionBook item)?
  pdfImporter;
  final Future<String> Function()? managedEpubRootPath;

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
    if (decoded is! Map) {
      throw const FormatException('Collection inventory is invalid.');
    }
    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion != 1 && schemaVersion != 2) {
      throw const FormatException(
        'Only schema-1 and schema-2 collections are supported.',
      );
    }
    final rawItems = schemaVersion == 1 ? decoded['books'] : decoded['items'];
    if (rawItems is! List) {
      throw const FormatException('Collection inventory items are invalid.');
    }
    final books = <StudyCollectionBook>[];
    final workIds = <String>{};
    for (var index = 0; index < rawItems.length; index++) {
      final raw = rawItems[index];
      if (raw is! Map) {
        throw const FormatException('Collection item entry is invalid.');
      }
      final typeName = schemaVersion == 1
          ? 'studybook'
          : raw['type']?.toString().trim().toLowerCase() ?? '';
      final itemType = switch (typeName) {
        'studybook' => StudyCollectionItemType.studybook,
        'epub' => StudyCollectionItemType.epub,
        'pdf' => StudyCollectionItemType.pdf,
        _ => throw FormatException(
          'Collection item ${index + 1} has unsupported type "$typeName".',
        ),
      };
      final workId =
          (raw['sourceWorkId'] ?? raw['source_work_id'] ?? raw['workId'])
              ?.toString()
              .trim() ??
          '';
      final path = raw['path']?.toString() ?? '';
      final expectedHash = raw['sha256']?.toString() ?? '';
      final expectedExtension = switch (itemType) {
        StudyCollectionItemType.studybook => '.studybook',
        StudyCollectionItemType.epub => '.epub',
        StudyCollectionItemType.pdf => '.pdf',
      };
      final validLegacyPath =
          schemaVersion == 1 && path == 'books/$workId.studybook';
      final validGenericPath =
          schemaVersion == 2 &&
          path.startsWith('items/') &&
          p.posix.extension(path).toLowerCase() == expectedExtension;
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,191}$').hasMatch(workId) ||
          !workIds.add(workId.toLowerCase()) ||
          (!validLegacyPath && !validGenericPath) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash)) {
        throw const FormatException(
          'Collection inventory identity is invalid.',
        );
      }
      final matches = archive.where((entry) => entry.name == path).toList();
      if (matches.length != 1 ||
          sha256.convert(matches.single.readBytes()!).toString() !=
              expectedHash) {
        throw FormatException(
          '$workId does not match the collection inventory checksum.',
        );
      }
      final coverPath = raw['cover']?.toString().trim();
      if (coverPath?.isNotEmpty == true) {
        final coverMatches = archive
            .where((entry) => entry.name == coverPath)
            .toList();
        if (!coverPath!.startsWith('covers/') ||
            coverMatches.length != 1 ||
            !coverMatches.single.isFile) {
          throw FormatException('$workId has an invalid cover reference.');
        }
      }
      final categories = raw['categories'] is List
          ? (raw['categories'] as List)
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
          : const <String>[];
      books.add(
        StudyCollectionBook(
          workId: workId,
          title: raw['title']?.toString() ?? workId,
          author: raw['author']?.toString() ?? '',
          path: path,
          sha256: expectedHash,
          packageId: raw['packageId']?.toString() ?? '',
          contentHash: raw['contentHash']?.toString() ?? '',
          itemType: itemType,
          coverPath: coverPath?.isEmpty == true ? null : coverPath,
          displayOrder:
              int.tryParse(raw['displayOrder']?.toString() ?? '') ?? index,
          categories: List<String>.unmodifiable(categories),
        ),
      );
    }
    books.sort((left, right) {
      final order = left.displayOrder.compareTo(right.displayOrder);
      return order != 0 ? order : left.title.compareTo(right.title);
    });
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
      if (book.itemType != StudyCollectionItemType.studybook) {
        final ready =
            await (hasReadyLocalItem?.call(book) ?? _hasReadyLocalItem(book));
        compared.add(
          book.withStatus(
            ready
                ? StudyCollectionBookStatus.current
                : StudyCollectionBookStatus.newBook,
          ),
        );
        continue;
      }
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
        AND (? = '' OR source_package_id = ?)
        AND index_status IN ('indexed', 'indexed_empty')
        AND deleted_at IS NULL
        AND is_missing = 0
      LIMIT 1
      ''',
      <Object?>[book.workId, book.packageId, book.packageId],
    );
    return rows.isNotEmpty;
  }

  Future<List<PioneerBookPackageImportResult>> importSelected(
    String sourcePath,
    Iterable<String> selectedWorkIds,
  ) async {
    final batch = await importSelectedItems(sourcePath, selectedWorkIds);
    return batch.studybookResults;
  }

  Future<StudyCollectionImportBatchResult> importSelectedItems(
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
      final studybookResults = <PioneerBookPackageImportResult>[];
      final epubResults = <PioneerImportWorkResult>[];
      final pdfWorkIds = <String>[];
      for (final item in allowed) {
        final entry = archive.singleWhere(
          (candidate) => candidate.name == item.path,
        );
        final extension = switch (item.itemType) {
          StudyCollectionItemType.studybook => '.studybook',
          StudyCollectionItemType.epub => '.epub',
          StudyCollectionItemType.pdf => '.pdf',
        };
        final file = File(p.join(temp.path, '${item.workId}$extension'));
        await file.writeAsBytes(entry.readBytes()!, flush: true);
        final cover = item.coverPath;
        String? extractedCoverPath;
        if (cover != null) {
          final coverEntry = archive.singleWhere(
            (candidate) => candidate.name == cover,
          );
          final coverFile = File(p.join(temp.path, p.posix.basename(cover)));
          await coverFile.writeAsBytes(coverEntry.readBytes()!, flush: true);
          extractedCoverPath = coverFile.path;
        }
        switch (item.itemType) {
          case StudyCollectionItemType.studybook:
            studybookResults.add(
              await (studybookImporter?.call(file.path, item) ??
                  PioneerBookPackageImportService.instance.importPackage(
                    file.path,
                    expectedWorkId: item.workId,
                    expectedPackageId: item.packageId.isEmpty
                        ? null
                        : item.packageId,
                  )),
            );
            break;
          case StudyCollectionItemType.epub:
            final managedRoot =
                await (managedEpubRootPath?.call() ??
                    _defaultManagedEpubRootPath());
            final managedFile = File(
              p.join(managedRoot, '${item.workId}.epub'),
            );
            await managedFile.parent.create(recursive: true);
            await file.copy(managedFile.path);
            final importItem = extractedCoverPath == null
                ? item
                : StudyCollectionBook(
                    workId: item.workId,
                    title: item.title,
                    author: item.author,
                    path: item.path,
                    sha256: item.sha256,
                    packageId: item.packageId,
                    contentHash: item.contentHash,
                    itemType: item.itemType,
                    coverPath: extractedCoverPath,
                    displayOrder: item.displayOrder,
                    categories: item.categories,
                  );
            final result =
                await (epubImporter?.call(managedFile.path, importItem) ??
                    _importEpub(managedFile.path, importItem));
            epubResults.add(result);
            if (result.isImported && epubImporter == null) {
              await EpubStoragePolicyService.instance
                  .applyPolicyAfterValidatedImport(
                    libraryItemId: result.libraryItemId,
                    epubFile: managedFile,
                    rootPath: p.dirname(managedRoot),
                  );
            }
            break;
          case StudyCollectionItemType.pdf:
            final importer = pdfImporter;
            if (importer == null) {
              throw UnsupportedError(
                'PDF collection items are recognized, but the PDF import '
                'pipeline is not available yet.',
              );
            }
            await importer(file.path, item);
            pdfWorkIds.add(item.workId);
            break;
        }
      }
      return StudyCollectionImportBatchResult(
        studybookResults: List.unmodifiable(studybookResults),
        epubResults: List.unmodifiable(epubResults),
        pdfWorkIds: List.unmodifiable(pdfWorkIds),
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<String> _defaultManagedEpubRootPath() async {
    final root = await PioneerBookPackageImportService.instance
        .managedImportRootPath();
    return p.join(p.dirname(root), 'ImportedPioneerEpubs');
  }

  Future<PioneerImportWorkResult> _importEpub(
    String path,
    StudyCollectionBook item,
  ) {
    final categories = item.categories;
    final authorId = item.author
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final work = PioneerSourceWork(
      id: item.workId,
      authorId: authorId.isEmpty ? 'unknown' : authorId,
      authorName: item.author,
      sourceFamily: 'StudyCollection',
      title: item.title,
      abbreviation: item.workId,
      group: categories.isEmpty ? 'Pioneer Authors' : categories.first,
      subgroup: categories.length < 2 ? 'EPUB' : categories[1],
      availability: PioneerSourceAvailability.available,
      verified: true,
      catalogImportable: true,
      sourceType: 'epub',
      sourceUrl: File(path).uri.toString(),
      cachedCoverPath: item.coverPath,
      sourceLabel: 'StudyCollection',
      notes: null,
    );
    return PioneerTextImportService.instance.importLocalEpubFile(
      work: work,
      filePath: path,
      overwriteExisting: true,
    );
  }
}
