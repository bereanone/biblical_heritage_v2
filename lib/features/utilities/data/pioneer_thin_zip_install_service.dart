import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/elibrary_database.dart';
import '../../library/data/library_acquisition_batch_runner.dart';
import 'pioneer_archive_org_install_service.dart';
import 'pioneer_epub_bulk_import_service.dart';
import 'pioneer_epub_folder_inventory_service.dart';
import 'pioneer_zip_extract_service.dart';

/// Downloads and imports the "thin" supplemental Pioneer EPUB collection —
/// the ~332 public-domain works that the per-title
/// [PioneerArchiveOrgInstallService] downloader cannot verify a direct EPUB
/// for anywhere online, and that aren't among the app's bundled
/// self-captured titles (`assets/scans/`). This is a small, purpose-built
/// zip the app team hosts itself (see the release notes on the asset), not a
/// mirror of any third-party site.
///
/// Reuses the same extract → survey → prepare → activate pipeline as the
/// manual "Import Pioneer ZIP" flow ([PioneerZipExtractService],
/// [PioneerEpubFolderInventoryService], [PioneerEpubBulkImportService],
/// [LibraryAcquisitionBatchRunner]), with one addition: entries whose title
/// already matches something in the library (from the bundled captures or
/// the archive.org downloader) are skipped before import, the same
/// normalized-title dedup [PioneerArchiveOrgInstallService] uses.
class PioneerThinZipInstallService {
  PioneerThinZipInstallService({
    HttpClient Function()? clientFactory,
    Future<Database> Function()? databaseOpener,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _databaseOpener =
           databaseOpener ?? (() async => ELibraryDatabase.instance.database);

  static final PioneerThinZipInstallService instance =
      PioneerThinZipInstallService();

  /// Staging location — see project notes; move to a permanent release
  /// asset before shipping and update this constant to match.
  static final Uri thinZipUri = Uri.parse(
    'https://github.com/bereanone/biblical_heritage_v2/releases/download/'
    'pioneer-thin-v1/pioneerthin.zip',
  );
  static const _allowedHosts = <String>{
    'github.com',
    'objects.githubusercontent.com',
  };

  final HttpClient Function() _clientFactory;
  final Future<Database> Function() _databaseOpener;
  bool _cancelled = false;

  static bool isTrustedDownloadUri(Uri uri) =>
      uri.scheme == 'https' && _allowedHosts.contains(uri.host.toLowerCase());

  void cancel() => _cancelled = true;

  Future<PioneerThinZipInstallResult> install({
    void Function(PioneerThinZipInstallProgress progress)? onProgress,
  }) async {
    _cancelled = false;
    onProgress?.call(
      const PioneerThinZipInstallProgress(
        phase: PioneerThinZipInstallPhase.downloading,
      ),
    );
    final root = (await LibraryRootService.instance.accessibleLibraryRootPath())
        ?.trim();
    if (root == null || root.isEmpty) {
      throw StateError('Library storage is not available.');
    }
    final temporary = Directory(p.join(root, 'Temporary', 'PioneerThinZip'));
    await temporary.create(recursive: true);
    final zipFile = File(p.join(temporary.path, 'pioneerthin.zip'));

    await _download(zipFile);
    _throwIfCancelled();

    onProgress?.call(
      const PioneerThinZipInstallProgress(
        phase: PioneerThinZipInstallPhase.extracting,
      ),
    );
    final extractedPath = await PioneerZipExtractService.instance
        .extractToWorkingFolder(zipFile.path);
    _throwIfCancelled();

    onProgress?.call(
      const PioneerThinZipInstallProgress(
        phase: PioneerThinZipInstallPhase.scanning,
      ),
    );
    final inventory = await PioneerEpubFolderInventoryService.instance.survey(
      Directory(extractedPath),
    );
    _throwIfCancelled();

    final db = await _databaseOpener();
    final existingTitles = await _loadExistingNormalizedTitles(db);
    final filteredEntries = inventory.entries
        .where((entry) {
          final title = entry.title?.trim() ?? '';
          if (title.isEmpty) return true;
          return !existingTitles.contains(
            PioneerArchiveOrgInstallService.normalizeTitleForDedup(title),
          );
        })
        .toList(growable: false);
    final skippedAsDuplicate =
        inventory.entries.length - filteredEntries.length;
    final filteredInventory = PioneerEpubFolderInventory(
      folderPath: inventory.folderPath,
      scannedAt: inventory.scannedAt,
      entries: filteredEntries,
      skippedNonEpubCount: inventory.skippedNonEpubCount,
    );

    onProgress?.call(
      const PioneerThinZipInstallProgress(
        phase: PioneerThinZipInstallPhase.importing,
      ),
    );
    final preparation = await PioneerEpubBulkImportService.instance.prepare(
      inventory: filteredInventory,
      shouldContinue: () => !_cancelled,
    );
    _throwIfCancelled();

    onProgress?.call(
      const PioneerThinZipInstallProgress(
        phase: PioneerThinZipInstallPhase.activating,
      ),
    );
    final activation = await LibraryAcquisitionBatchRunner.instance.activate(
      preparation.targets,
      shouldContinue: () => !_cancelled,
    );

    return PioneerThinZipInstallResult(
      installed: activation.readyCount,
      alreadyInLibrary: preparation.skippedUnchangedCount + skippedAsDuplicate,
      failed:
          inventory.invalidCount +
          preparation.preparationFailures.length +
          activation.unavailableOutcomes.length,
    );
  }

  Future<void> _download(File destination) async {
    final client = _clientFactory();
    try {
      final request = await client.getUrl(thinZipUri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close();
      final finalUri = response.redirects.isEmpty
          ? thinZipUri
          : response.redirects.last.location;
      if (!isTrustedDownloadUri(finalUri) &&
          !isTrustedDownloadUri(thinZipUri)) {
        throw const FormatException(
          'The download redirected to an untrusted server.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Pioneer supplemental library download failed '
          '(${response.statusCode}).',
        );
      }
      final sink = destination.openWrite();
      try {
        await for (final chunk in response) {
          _throwIfCancelled();
          sink.add(chunk);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      final bytes = await destination.length();
      if (bytes < 4) {
        throw const FormatException(
          'The Pioneer supplemental library download is incomplete.',
        );
      }
      final handle = await destination.open();
      try {
        final signature = await handle.read(4);
        if (signature.length < 4 ||
            signature[0] != 0x50 ||
            signature[1] != 0x4b) {
          throw const FormatException(
            'The downloaded file is not a ZIP archive.',
          );
        }
      } finally {
        await handle.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<Set<String>> _loadExistingNormalizedTitles(Database db) async {
    final rows = await db.rawQuery('''
      SELECT title FROM library_items
      WHERE deleted_at IS NULL AND COALESCE(title, '') != ''
    ''');
    return rows
        .map(
          (row) => PioneerArchiveOrgInstallService.normalizeTitleForDedup(
            row['title']?.toString() ?? '',
          ),
        )
        .where((title) => title.isNotEmpty)
        .toSet();
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const PioneerThinZipInstallCancelled();
  }
}

enum PioneerThinZipInstallPhase {
  downloading,
  extracting,
  scanning,
  importing,
  activating,
}

class PioneerThinZipInstallProgress {
  const PioneerThinZipInstallProgress({required this.phase});

  final PioneerThinZipInstallPhase phase;
}

class PioneerThinZipInstallResult {
  const PioneerThinZipInstallResult({
    required this.installed,
    required this.alreadyInLibrary,
    required this.failed,
  });

  final int installed;
  final int alreadyInLibrary;
  final int failed;
}

class PioneerThinZipInstallCancelled implements Exception {
  const PioneerThinZipInstallCancelled();
}
