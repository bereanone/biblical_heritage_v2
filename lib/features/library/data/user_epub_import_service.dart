import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_database.dart';
import '../../utilities/data/elibrary_folder_policy.dart';
import '../../utilities/data/epub_download_validator.dart';
import 'library_epub_metadata.dart';
import 'library_source_type.dart';
import 'library_item_identity.dart';
import 'optional_book_companions.dart';

class UserEpubImportResult {
  const UserEpubImportResult({
    required this.libraryItemId,
    required this.relativePath,
    required this.title,
    required this.creator,
    required this.sourceSha256,
  });

  final String libraryItemId;
  final String relativePath;
  final String title;
  final String? creator;
  final String sourceSha256;
}

class UserEpubInspection {
  const UserEpubInspection({
    required this.sourcePath,
    required this.title,
    required this.creator,
    required this.sourceSha256,
    required this.spineItemCount,
  });

  final String sourcePath;
  final String title;
  final String? creator;
  final String sourceSha256;
  final int spineItemCount;
}

/// Copies a user-selected individual EPUB into the dedicated
/// [ELibraryFolderPolicy.userImportedEpubsRelativeFolder] folder and
/// creates/updates its `library_items` row, mirroring the same identity
/// scheme [LibraryCatalogService.refreshManagedItemsFromDisk] uses for
/// managed EGW files (same table, no schema change). The source file
/// picked by the user is never moved or altered — only read and copied.
class UserEpubImportService {
  UserEpubImportService._();

  static final UserEpubImportService instance = UserEpubImportService._();

  /// Reads and validates a local EPUB before the user confirms its metadata.
  /// This does not copy the file or write a library row.
  Future<UserEpubInspection> inspect(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('The selected file is no longer available.');
    }
    final sourceBytes = await sourceFile.readAsBytes();
    if (!librarySourceIsEpub(sourceBytes, path: sourceFile.path)) {
      throw const FormatException('Choose an EPUB file.');
    }
    final validation = EpubDownloadValidator.validate(sourceBytes);
    if (!validation.isValid) {
      throw FormatException(
        validation.detail ?? 'The selected file is not a readable EPUB.',
      );
    }
    final metadata = await readLibraryEpubMetadata(sourceFile);
    final rawBaseName = p.basenameWithoutExtension(sourcePath).trim();
    final title = metadata?.title?.trim().isNotEmpty == true
        ? metadata!.title!.trim()
        : validation.opfTitle?.trim().isNotEmpty == true
        ? validation.opfTitle!.trim()
        : rawBaseName.isEmpty
        ? 'Untitled Book'
        : rawBaseName;
    return UserEpubInspection(
      sourcePath: sourceFile.path,
      title: title,
      creator: metadata?.creator?.trim().isNotEmpty == true
          ? metadata!.creator!.trim()
          : null,
      sourceSha256: sha256.convert(sourceBytes).toString(),
      spineItemCount: validation.spineItemCount,
    );
  }

  Future<UserEpubImportResult> copyIntoLibrary(
    String sourcePath, {
    UserEpubInspection? confirmedInspection,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('The selected file no longer exists at $sourcePath.');
    }
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    if (rootPath == null || rootPath.isEmpty) {
      throw StateError('Library Root Folder is not selected.');
    }

    final destinationDir = Directory(
      p.join(rootPath, ELibraryFolderPolicy.userImportedEpubsRelativeFolder),
    );
    await destinationDir.create(recursive: true);

    final inspection = await inspect(sourcePath);
    if (confirmedInspection != null &&
        (confirmedInspection.sourcePath != inspection.sourcePath ||
            confirmedInspection.sourceSha256 != inspection.sourceSha256)) {
      throw StateError(
        'The selected EPUB changed after it was checked. Choose it again.',
      );
    }
    final shortHash = inspection.sourceSha256.substring(0, 10);
    final rawBaseName = p.basenameWithoutExtension(sourcePath).trim();
    final sanitizedBase = rawBaseName
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .trim();
    final displayTitle = inspection.title;
    final fileName =
        '${sanitizedBase.isEmpty ? 'book' : sanitizedBase}_$shortHash.epub';
    final destination = File(p.join(destinationDir.path, fileName));
    if (!await destination.exists()) {
      await sourceFile.copy(destination.path);
    }

    final relativePath = p.join(
      ELibraryFolderPolicy.userImportedEpubsRelativeFolder,
      fileName,
    );
    final libraryItemId = canonicalLibraryItemId(
      folderType: 'user_import',
      relativePath: relativePath,
    );

    final db = await ELibraryDatabase.instance.database;
    final stat = await destination.stat();
    final now = DateTime.now().toUtc().toIso8601String();
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final existingRows = await db.query(
      'library_items',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    final sharedPayload = <String, Object?>{
      'title': displayTitle,
      'author': inspection.creator,
      'file_name': fileName,
      'relative_path': relativePath,
      'file_hash': '${stat.size}:${stat.modified.millisecondsSinceEpoch}',
      'file_size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
      'mime_type': 'application/epub+zip',
      'file_format': 'epub',
      'folder_type': 'user_import',
      'library_role': 'user_import',
      'collection_name': 'My Books',
      'source_type': 'user_import',
      'source_work_id': 'user_epub_sha256_${inspection.sourceSha256}',
      'updated_at': now,
      'deleted_at': null,
    };
    if (existingRows.isEmpty) {
      await db.insert('library_items', <String, Object?>{
        'id': libraryItemId,
        ...sharedPayload,
        'source_site': null,
        'source_url': null,
        'cover_path': null,
        'date_added': now,
        'last_opened': null,
        'index_status': 'metadata_only',
        'index_error': null,
        'epub_href': null,
        'epub_cfi': null,
        'anchor_id': null,
        'spine_index': null,
        'paragraph_index': null,
        'is_missing': 0,
        'created_at': now,
        'device_id': deviceId,
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });
    } else {
      await db.update(
        'library_items',
        sharedPayload,
        where: 'id = ?',
        whereArgs: <Object?>[libraryItemId],
      );
    }

    await OptionalBookCompanions.apply(
      db: db,
      itemId: libraryItemId,
      sourceHash: inspection.sourceSha256,
    );
    return UserEpubImportResult(
      libraryItemId: libraryItemId,
      relativePath: relativePath,
      title: displayTitle,
      creator: inspection.creator,
      sourceSha256: inspection.sourceSha256,
    );
  }
}
