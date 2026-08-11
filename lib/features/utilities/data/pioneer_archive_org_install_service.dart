import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_database.dart';
import '../../library/data/canonical_activation.dart';
import '../../library/data/library_document_repository.dart';
import 'elibrary_folder_policy.dart';
import 'epub_download_validator.dart';

/// Per-title Pioneer EPUB downloader — the replacement for the retired
/// all-in-one `pioneer.zip` install. Rather than fetching one third-party
/// archive, this pulls individually verified EPUB files from the Internet
/// Archive's "Adventist Pioneer Authors" collection, one work at a time,
/// through the same download → validate → register → activate pipeline the
/// EGW Writings downloader uses ([ELibraryDownloadService]).
///
/// Only authors with real, confirmed EPUB files on archive.org are listed in
/// the bundled manifest (`tool/pioneer_epub_download_manifest.json`,
/// generated from archive.org's own metadata API — see
/// docs/pioneer_acquisition_plan.md for why the other ~90% of the Pioneer
/// Authors catalog has no direct EPUB anywhere and stays on the
/// CaptureClipper path instead of being force-fit into this downloader).
class PioneerArchiveOrgInstallService {
  PioneerArchiveOrgInstallService({
    HttpClient Function()? clientFactory,
    Future<Database> Function()? databaseOpener,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _databaseOpener =
           databaseOpener ?? (() async => ELibraryDatabase.instance.database);

  static final PioneerArchiveOrgInstallService instance =
      PioneerArchiveOrgInstallService();

  static const String manifestAssetKey =
      'tool/pioneer_epub_download_manifest.json';
  static const _allowedHosts = <String>{'archive.org'};

  final HttpClient Function() _clientFactory;
  final Future<Database> Function() _databaseOpener;
  bool _cancelled = false;

  static bool isTrustedDownloadUri(Uri uri) =>
      uri.scheme == 'https' && _allowedHosts.contains(uri.host.toLowerCase());

  void cancel() => _cancelled = true;

  /// Total number of individually verified works available across every
  /// author in the manifest — used by the UI in place of a single archive
  /// byte size (there is no one file to size any more).
  Future<int> inspect() async {
    final authors = await _loadManifest();
    return authors.fold<int>(0, (sum, author) => sum + author.works.length);
  }

  Future<PioneerArchiveOrgInstallResult> install({
    void Function(PioneerArchiveOrgInstallProgress progress)? onProgress,
  }) async {
    _cancelled = false;
    final authors = await _loadManifest();
    final totalWorks = authors.fold<int>(
      0,
      (sum, author) => sum + author.works.length,
    );
    if (totalWorks == 0) {
      return const PioneerArchiveOrgInstallResult(
        installed: 0,
        alreadyInLibrary: 0,
        unavailable: 0,
        failed: 0,
      );
    }

    await LibraryRootService.instance.requireLibraryAuthorization(write: true);
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    if (rootPath == null || rootPath.isEmpty) {
      throw StateError('Library storage is not available.');
    }
    final destinationDir = Directory(
      p.join(rootPath, ELibraryFolderPolicy.pioneerImportedEpubsRelativeFolder),
    );
    await destinationDir.create(recursive: true);

    final db = await _databaseOpener();
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final client = _clientFactory()..autoUncompress = true;
    client.userAgent = 'StudyBible2 Pioneer Library Downloader';

    var installed = 0;
    var alreadyInLibrary = 0;
    var unavailable = 0;
    var failed = 0;
    var processed = 0;

    try {
      for (final author in authors) {
        for (final work in author.works) {
          if (_cancelled) throw const PioneerArchiveOrgInstallCancelled();
          processed += 1;
          onProgress?.call(
            PioneerArchiveOrgInstallProgress(
              phase: PioneerArchiveOrgInstallPhase.downloading,
              current: processed,
              total: totalWorks,
              title: work.title,
            ),
          );

          final libraryItemId = canonicalLibraryItemId(
            author: author.author,
            canonicalCode: work.canonicalCode,
          );
          if (await LibraryDocumentRepository(db).isComplete(libraryItemId)) {
            alreadyInLibrary += 1;
            onProgress?.call(
              PioneerArchiveOrgInstallProgress(
                phase: PioneerArchiveOrgInstallPhase.skippedExisting,
                current: processed,
                total: totalWorks,
                title: work.title,
              ),
            );
            continue;
          }

          final uri = Uri.parse(
            'https://archive.org/download/${author.identifier}/'
            '${Uri.encodeComponent(work.fileName)}',
          );
          if (!isTrustedDownloadUri(uri)) {
            failed += 1;
            continue;
          }

          try {
            final bytes = await _download(client, uri);
            if (bytes == null) {
              unavailable += 1;
              onProgress?.call(
                PioneerArchiveOrgInstallProgress(
                  phase: PioneerArchiveOrgInstallPhase.unavailable,
                  current: processed,
                  total: totalWorks,
                  title: work.title,
                ),
              );
              continue;
            }
            // Internet Archive's per-work derivatives sometimes retain the
            // parent author-collection OPF title. Identity is therefore
            // established by the trusted manifest identifier + exact source
            // filename + canonical code/aliases; the EPUB validator remains
            // responsible for structure and readable-spine validation.
            final validation = EpubDownloadValidator.validate(bytes);
            if (!validation.isValid) {
              if (validation.looksLikePlaceholder) {
                unavailable += 1;
              } else {
                failed += 1;
              }
              onProgress?.call(
                PioneerArchiveOrgInstallProgress(
                  phase: validation.looksLikePlaceholder
                      ? PioneerArchiveOrgInstallPhase.unavailable
                      : PioneerArchiveOrgInstallPhase.failed,
                  current: processed,
                  total: totalWorks,
                  title: work.title,
                ),
              );
              continue;
            }

            final outcome = await _stageActivateAndPromote(
              db: db,
              deviceId: deviceId,
              destinationDir: destinationDir,
              author: author,
              work: work,
              bytes: bytes,
              sourceUri: uri,
            );
            if (!outcome.isReady) {
              failed += 1;
              onProgress?.call(
                PioneerArchiveOrgInstallProgress(
                  phase: PioneerArchiveOrgInstallPhase.failed,
                  current: processed,
                  total: totalWorks,
                  title: work.title,
                ),
              );
              continue;
            }
            installed += 1;
            onProgress?.call(
              PioneerArchiveOrgInstallProgress(
                phase: PioneerArchiveOrgInstallPhase.downloaded,
                current: processed,
                total: totalWorks,
                title: work.title,
              ),
            );
          } on PioneerArchiveOrgInstallCancelled {
            rethrow;
          } catch (_) {
            failed += 1;
            onProgress?.call(
              PioneerArchiveOrgInstallProgress(
                phase: PioneerArchiveOrgInstallPhase.failed,
                current: processed,
                total: totalWorks,
                title: work.title,
              ),
            );
          }
        }
      }
    } finally {
      client.close(force: true);
    }

    return PioneerArchiveOrgInstallResult(
      installed: installed,
      alreadyInLibrary: alreadyInLibrary,
      unavailable: unavailable,
      failed: failed,
    );
  }

  static String normalizeTitleForDedup(String title) {
    return title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<Uint8List?> _download(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 5;
    final response = await request.close();
    if (response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode} for $uri');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (_cancelled) throw const PioneerArchiveOrgInstallCancelled();
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static String canonicalLibraryItemId({
    required String author,
    required String canonicalCode,
  }) =>
      'pioneer_${_stableKeyStatic(author)}_${_stableKeyStatic(canonicalCode)}';

  Future<LibraryAcquisitionOutcome> _stageActivateAndPromote({
    required Database db,
    required String deviceId,
    required Directory destinationDir,
    required _PioneerArchiveOrgAuthor author,
    required _PioneerArchiveOrgWork work,
    required Uint8List bytes,
    required Uri sourceUri,
  }) async {
    final libraryItemId = canonicalLibraryItemId(
      author: author.author,
      canonicalCode: work.canonicalCode,
    );
    final sanitizedBase = work.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .trim();
    final fileName =
        '${sanitizedBase.isEmpty ? work.code : sanitizedBase}.epub';
    final destination = File(p.join(destinationDir.path, fileName));
    final staging = File(
      p.join(
        destinationDir.path,
        '.$fileName.${DateTime.now().microsecondsSinceEpoch}.downloading',
      ),
    );
    await staging.writeAsBytes(bytes, flush: true);
    final finalRelativePath = p.join(
      ELibraryFolderPolicy.pioneerImportedEpubsRelativeFolder,
      fileName,
    );
    final stagingRelativePath = p.join(
      ELibraryFolderPolicy.pioneerImportedEpubsRelativeFolder,
      p.basename(staging.path),
    );

    final now = DateTime.now().toUtc().toIso8601String();
    final existingRows = await db.query(
      'library_items',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    final payload = <String, Object?>{
      'title': work.title,
      'author': author.author,
      'file_name': fileName,
      'relative_path': stagingRelativePath,
      'file_size': bytes.length,
      'mime_type': 'application/epub+zip',
      'file_format': 'epub',
      'folder_type': 'pioneer_epub_import',
      'library_role': 'pioneer_epub_import',
      'collection_name': 'Pioneer Authors',
      'source_type': 'pioneer_archive_org_download',
      'source_site': 'archive.org',
      'source_url': sourceUri.toString(),
      'updated_at': now,
      'deleted_at': null,
    };
    final createdProvisionalRow = existingRows.isEmpty;
    if (createdProvisionalRow) {
      await db.insert('library_items', <String, Object?>{
        'id': libraryItemId,
        ...payload,
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
    }
    try {
      final outcome = await CanonicalActivation.activate(
        db: db,
        libraryItemId: libraryItemId,
        source: staging,
        force: true,
      );
      if (!outcome.isReady) {
        if (createdProvisionalRow) {
          await db.delete(
            'library_items',
            where: 'id = ?',
            whereArgs: <Object?>[libraryItemId],
          );
        }
        return outcome;
      }
      if (_cancelled) throw const PioneerArchiveOrgInstallCancelled();
      if (await destination.exists()) {
        await destination.delete();
      }
      await staging.rename(destination.path);
      await db.update(
        'library_items',
        <String, Object?>{
          ...payload,
          'relative_path': finalRelativePath,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[libraryItemId],
      );
      return outcome;
    } catch (_) {
      if (createdProvisionalRow) {
        await db.delete(
          'library_items',
          where: 'id = ?',
          whereArgs: <Object?>[libraryItemId],
        );
      }
      rethrow;
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  }

  static String _stableKeyStatic(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<List<_PioneerArchiveOrgAuthor>> _loadManifest() async {
    final raw = await rootBundle.loadString(manifestAssetKey);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw StateError('Invalid Pioneer EPUB download manifest.');
    }
    final rawAuthors = decoded['authors'];
    if (rawAuthors is! List) return const <_PioneerArchiveOrgAuthor>[];
    final authors = <_PioneerArchiveOrgAuthor>[];
    for (final entry in rawAuthors) {
      if (entry is! Map) continue;
      final map = entry.map((key, value) => MapEntry(key.toString(), value));
      final identifier = map['identifier']?.toString().trim() ?? '';
      final authorName = map['author']?.toString().trim() ?? '';
      if (identifier.isEmpty || authorName.isEmpty) continue;
      final rawWorks = map['works'];
      final works = <_PioneerArchiveOrgWork>[];
      if (rawWorks is List) {
        for (final workEntry in rawWorks) {
          if (workEntry is! Map) continue;
          final workMap = workEntry.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final code = workMap['code']?.toString().trim() ?? '';
          final canonicalCode =
              workMap['canonical_code']?.toString().trim() ?? code;
          final title = workMap['title']?.toString().trim() ?? '';
          final fileName = workMap['file_name']?.toString().trim() ?? '';
          if (code.isEmpty || title.isEmpty || fileName.isEmpty) continue;
          works.add(
            _PioneerArchiveOrgWork(
              code: code,
              canonicalCode: canonicalCode,
              title: title,
              fileName: fileName,
            ),
          );
        }
      }
      if (works.isEmpty) continue;
      authors.add(
        _PioneerArchiveOrgAuthor(
          identifier: identifier,
          author: authorName,
          works: List<_PioneerArchiveOrgWork>.unmodifiable(works),
        ),
      );
    }
    return List<_PioneerArchiveOrgAuthor>.unmodifiable(authors);
  }
}

class _PioneerArchiveOrgAuthor {
  const _PioneerArchiveOrgAuthor({
    required this.identifier,
    required this.author,
    required this.works,
  });

  final String identifier;
  final String author;
  final List<_PioneerArchiveOrgWork> works;
}

class _PioneerArchiveOrgWork {
  const _PioneerArchiveOrgWork({
    required this.code,
    required this.canonicalCode,
    required this.title,
    required this.fileName,
  });

  final String code;
  final String canonicalCode;
  final String title;
  final String fileName;
}

enum PioneerArchiveOrgInstallPhase {
  downloading,
  downloaded,
  skippedExisting,
  unavailable,
  failed,
  activating,
}

class PioneerArchiveOrgInstallProgress {
  const PioneerArchiveOrgInstallProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.title,
  });

  final PioneerArchiveOrgInstallPhase phase;
  final int current;
  final int total;
  final String title;
}

class PioneerArchiveOrgInstallResult {
  const PioneerArchiveOrgInstallResult({
    required this.installed,
    required this.alreadyInLibrary,
    required this.unavailable,
    required this.failed,
  });

  final int installed;
  final int alreadyInLibrary;
  final int unavailable;
  final int failed;
}

class PioneerArchiveOrgInstallCancelled implements Exception {
  const PioneerArchiveOrgInstallCancelled();
}
