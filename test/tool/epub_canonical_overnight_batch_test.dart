// Overnight unattended batch driver: canonicalizes every managed EGW EPUB
// found under a target Library Root into the canonical database-backed
// reader model, and writes a timestamped audit report.
//
// This does nothing under a normal `flutter test` run. It only executes
// when explicitly invoked with RUN_OVERNIGHT_EPUB_BATCH=1, e.g.:
//
//   RUN_OVERNIGHT_EPUB_BATCH=1 \
//   OVERNIGHT_EPUB_BATCH_ROOT=/Users/deanbowen/Development/eLibrary \
//   flutter test test/tool/epub_canonical_overnight_batch_test.dart --timeout=none
//
// Runs one independent transactional unit per book (via
// LibraryDocumentCanonicalizer.canonicalize) and persists the report after
// every book, so the batch is safely resumable and a rerun skips books
// already indexed with an unchanged source fingerprint.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_author_resolver.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/data/library_epub_metadata.dart';
import 'package:studybible2/features/library/data/library_item_identity.dart';
import 'package:studybible2/features/utilities/data/elibrary_folder_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overnight EGW EPUB canonical batch index', () async {
    if (Platform.environment['RUN_OVERNIGHT_EPUB_BATCH'] != '1') {
      return;
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final rootPath = p.normalize(
      (Platform.environment['OVERNIGHT_EPUB_BATCH_ROOT'] ??
              '/Users/deanbowen/Development/eLibrary')
          .trim(),
    );
    final dbPath =
        (Platform.environment['OVERNIGHT_EPUB_BATCH_DB'] ?? '').trim().isEmpty
        ? p.join(rootPath, 'Databases', 'eLibrary.db')
        : p.normalize(Platform.environment['OVERNIGHT_EPUB_BATCH_DB']!.trim());
    final reportRoot =
        (Platform.environment['OVERNIGHT_EPUB_BATCH_REPORT_DIR'] ?? '')
            .trim()
            .isEmpty
        ? Directory.current.path
        : p.normalize(
            Platform.environment['OVERNIGHT_EPUB_BATCH_REPORT_DIR']!.trim(),
          );

    await Directory(p.dirname(dbPath)).create(recursive: true);
    final overallStart = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();

    stdout.writeln('[overnight-batch] root=$rootPath db=$dbPath');
    final db = await openDatabase(dbPath);
    await ELibrarySchema.ensure(db);
    final repository = LibraryDocumentRepository(db);
    const canonicalizer = LibraryDocumentCanonicalizer();

    // --- Pre-run snapshot -------------------------------------------------
    final dbSizeBefore = await File(dbPath).exists()
        ? await File(dbPath).length()
        : 0;
    final catalogCountBefore = _firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM library_items'),
    );
    final alreadyIndexedBefore = _firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM library_document_conversion WHERE status = 'complete' AND canonicalizer_version = ?",
        <Object?>[LibraryDocumentCanonicalizer.version],
      ),
    );

    // --- Discover eligible EPUBs -------------------------------------------
    final candidates = <_Candidate>[];
    for (final folder in ELibraryFolderPolicy.allManagedEgwFolderDefinitions) {
      final directory = Directory(p.join(rootPath, folder.relativeFolder));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (p.extension(entity.path).toLowerCase() != '.epub') continue;
        if (ELibraryFolderPolicy.isQuarantinePath(entity.path)) continue;
        final relativePath = p.relative(entity.path, from: rootPath);
        candidates.add(
          _Candidate(file: entity, relativePath: relativePath, folder: folder),
        );
      }
    }
    candidates.sort((a, b) => a.relativePath.compareTo(b.relativePath));

    stdout.writeln(
      '[overnight-batch] discovered ${candidates.length} eligible managed EPUB(s)',
    );

    final now = DateTime.now().toUtc();
    final timestamp = _timestamp(now);
    final mdPath = p.join(
      reportRoot,
      'EPUB_CANONICAL_BATCH_REPORT_$timestamp.md',
    );
    final jsonPath = p.join(
      reportRoot,
      'EPUB_CANONICAL_BATCH_REPORT_$timestamp.json',
    );

    final books = <Map<String, Object?>>[];
    var successes = 0;
    var skips = 0;
    var failures = 0;
    var needsReview = 0;
    final durationsMs = <int>[];
    _Candidate? fastest;
    _Candidate? slowest;
    var fastestMs = 1 << 30;
    var slowestMs = -1;

    var sequence = 0;
    for (final candidate in candidates) {
      sequence += 1;
      final bookStopwatch = Stopwatch()..start();
      final bookStart = DateTime.now().toUtc();

      final itemId = canonicalLibraryItemId(
        folderType: candidate.folder.folderType,
        relativePath: candidate.relativePath,
      );
      final epubMetadata = await readLibraryEpubMetadata(candidate.file);
      final metadataTitle = epubMetadata?.title?.trim() ?? '';
      final title = metadataTitle.isNotEmpty
          ? metadataTitle
          : _titleFromFileName(candidate.file.path);
      final author =
          resolveLibraryAuthor(
            author: epubMetadata?.creator,
            collectionName: candidate.folder.collectionName,
            sourceSite: 'egwwritings.org',
            relativePath: candidate.relativePath,
          ) ??
          'Ellen G. White';
      final sourceWorkId = ELibraryFolderPolicy.detectedAbbreviation(
        p.basename(candidate.file.path),
      );
      final stat = await candidate.file.stat();
      final wasAlreadyComplete = await repository.isCurrentComplete(
        itemId,
        canonicalizerVersion: LibraryDocumentCanonicalizer.version,
      );

      await db.insert('library_items', <String, Object?>{
        'id': itemId,
        'title': title,
        'author': author,
        'file_name': p.basename(candidate.file.path),
        'relative_path': candidate.relativePath,
        'file_size': stat.size,
        'modified_at': stat.modified.toUtc().toIso8601String(),
        'mime_type': 'application/epub+zip',
        'file_format': 'epub',
        'folder_type': candidate.folder.folderType,
        'library_role': candidate.folder.folderType,
        'collection_name': candidate.folder.collectionName,
        'source_site': 'egwwritings.org',
        'source_type': 'official_download',
        if (sourceWorkId.isNotEmpty) 'source_work_id': sourceWorkId,
        'index_status': 'metadata_only',
        'is_missing': 0,
        'created_at': bookStart.toIso8601String(),
        'updated_at': bookStart.toIso8601String(),
        'device_id': 'overnight-batch',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.update(
        'library_items',
        <String, Object?>{'updated_at': bookStart.toIso8601String()},
        where: 'id = ?',
        whereArgs: <Object?>[itemId],
      );

      final entry = <String, Object?>{
        'sequence': sequence,
        'id': itemId,
        'title': title,
        'author': author,
        'source_work_id': sourceWorkId,
        'relative_path': candidate.relativePath,
        'collection': candidate.folder.collectionName,
        'folder_type': candidate.folder.folderType,
        'epub_size_bytes': stat.size,
        'start_timestamp': bookStart.toIso8601String(),
      };

      try {
        final result = await canonicalizer.canonicalize(
          db: db,
          libraryItemId: itemId,
          source: candidate.file,
        );
        bookStopwatch.stop();
        final elapsedMs = bookStopwatch.elapsedMilliseconds;
        final finish = DateTime.now().toUtc();

        entry['finish_timestamp'] = finish.toIso8601String();
        entry['elapsed_ms'] = elapsedMs;
        entry['source_fingerprint_sha256'] = result.sourceHash;
        entry['skipped_unchanged'] = result.skipped;
        entry['block_count'] = result.blockCount;
        entry['epub_retained'] = true;

        final isComplete = await repository.isCurrentComplete(
          itemId,
          canonicalizerVersion: LibraryDocumentCanonicalizer.version,
        );

        if (result.skipped && wasAlreadyComplete) {
          skips += 1;
          entry['final_index_status'] = 'skipped_already_current';
          entry['validation_result'] = 'n/a (unchanged fingerprint)';
          entry['activation_result'] = 'n/a (unchanged fingerprint)';
          entry['prior_generation_preserved'] = true;
        } else if (result.activated && isComplete) {
          successes += 1;
          durationsMs.add(elapsedMs);
          if (elapsedMs < fastestMs) {
            fastestMs = elapsedMs;
            fastest = candidate;
          }
          if (elapsedMs > slowestMs) {
            slowestMs = elapsedMs;
            slowest = candidate;
          }
          final stats = await _collectBookStats(db, itemId, candidate.file);
          entry.addAll(stats);
          entry['final_index_status'] = 'activated';
          entry['validation_result'] = 'passed';
          entry['activation_result'] = 'activated';
          entry['prior_generation_preserved'] = false;
          entry['warning_list'] = <String>[];
          entry['failure_reason'] = null;
        } else {
          failures += 1;
          needsReview += 1;
          entry['final_index_status'] = 'validation_failed';
          entry['validation_result'] = 'failed';
          entry['activation_result'] = 'not_activated';
          entry['failure_reason'] = result.validationFailureReason;
          entry['prior_generation_preserved'] = wasAlreadyComplete;
          entry['warning_list'] = <String>[
            if (result.validationFailureReason != null)
              result.validationFailureReason!,
          ];
        }
      } catch (error, stackTrace) {
        bookStopwatch.stop();
        failures += 1;
        needsReview += 1;
        final finish = DateTime.now().toUtc();
        entry['finish_timestamp'] = finish.toIso8601String();
        entry['elapsed_ms'] = bookStopwatch.elapsedMilliseconds;
        entry['final_index_status'] = 'error';
        entry['validation_result'] = 'error';
        entry['activation_result'] = 'not_activated';
        entry['failure_reason'] = error.toString();
        entry['warning_list'] = <String>[
          stackTrace.toString().split('\n').first,
        ];
        entry['prior_generation_preserved'] = wasAlreadyComplete;
        entry['epub_retained'] = candidate.file.existsSync();
        stdout.writeln(
          '[overnight-batch] ERROR indexing ${candidate.relativePath}: $error',
        );
      }

      books.add(entry);

      if (sequence % 5 == 0 || sequence == candidates.length) {
        final elapsedOverall = stopwatch.elapsed;
        stdout.writeln(
          '[overnight-batch] $sequence/${candidates.length} '
          '(ok=$successes skip=$skips fail=$failures) '
          'elapsed=${elapsedOverall.inMinutes}m${elapsedOverall.inSeconds % 60}s '
          'last="${candidate.relativePath}"',
        );
      }

      // Persist progress after every book so the report survives interruption.
      await _writeJsonReport(
        jsonPath: jsonPath,
        rootPath: rootPath,
        dbPath: dbPath,
        overallStart: overallStart,
        inProgress: true,
        books: books,
        totalCandidates: candidates.length,
        successes: successes,
        skips: skips,
        failures: failures,
        needsReview: needsReview,
        catalogCountBefore: catalogCountBefore,
        alreadyIndexedBefore: alreadyIndexedBefore,
        dbSizeBefore: dbSizeBefore,
      );
    }

    stopwatch.stop();
    final overallFinish = DateTime.now().toUtc();

    // --- Post-batch validation ---------------------------------------------
    final integrityRows = await db.rawQuery('PRAGMA integrity_check');
    final integrityResult = integrityRows.isNotEmpty
        ? (integrityRows.first.values.first?.toString() ?? 'unknown')
        : 'unknown';
    final danglingStaging = _firstInt(
      await db.rawQuery(
        "SELECT COUNT(*) FROM library_document_conversion_staging WHERE status NOT IN ('failed')",
      ),
    );
    final duplicateIds = _firstInt(
      await db.rawQuery(
        'SELECT COUNT(*) FROM (SELECT id, COUNT(*) c FROM library_items GROUP BY id HAVING c > 1)',
      ),
    );
    final catalogCountAfter = _firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM library_items'),
    );
    final dbSizeAfter = await File(dbPath).exists()
        ? await File(dbPath).length()
        : 0;
    final assetSizeAfter = await _totalAssetSize(rootPath);

    await db.close();

    final summary = <String, Object?>{
      'overall_start': overallStart.toIso8601String(),
      'overall_finish': overallFinish.toIso8601String(),
      'elapsed_seconds': stopwatch.elapsed.inSeconds,
      'root_path': rootPath,
      'db_path': dbPath,
      'total_managed_epub_records_found': candidates.length,
      'total_local_epub_files_found': candidates.length,
      'total_eligible_books': candidates.length,
      'successful_indexes': successes,
      'already_current_skips': skips,
      'needs_review_books': needsReview,
      'failed_books': failures,
      'average_successful_ms': durationsMs.isEmpty
          ? null
          : durationsMs.reduce((a, b) => a + b) / durationsMs.length,
      'fastest_book': fastest == null
          ? null
          : <String, Object?>{
              'relative_path': fastest.relativePath,
              'elapsed_ms': fastestMs,
            },
      'slowest_book': slowest == null
          ? null
          : <String, Object?>{
              'relative_path': slowest.relativePath,
              'elapsed_ms': slowestMs,
            },
      'catalog_count_before': catalogCountBefore,
      'catalog_count_after': catalogCountAfter,
      'already_indexed_before': alreadyIndexedBefore,
      'db_size_before_bytes': dbSizeBefore,
      'db_size_after_bytes': dbSizeAfter,
      'db_growth_bytes': dbSizeAfter - dbSizeBefore,
      'extracted_asset_size_after_bytes': assetSizeAfter,
      'integrity_check_result': integrityResult,
      'dangling_active_staging_rows': danglingStaging,
      'duplicate_library_item_ids': duplicateIds,
    };

    await _writeJsonReport(
      jsonPath: jsonPath,
      rootPath: rootPath,
      dbPath: dbPath,
      overallStart: overallStart,
      inProgress: false,
      books: books,
      totalCandidates: candidates.length,
      successes: successes,
      skips: skips,
      failures: failures,
      needsReview: needsReview,
      catalogCountBefore: catalogCountBefore,
      alreadyIndexedBefore: alreadyIndexedBefore,
      dbSizeBefore: dbSizeBefore,
      finalSummary: summary,
    );

    await File(mdPath).writeAsString(
      _renderMarkdownReport(summary: summary, books: books),
      flush: true,
    );

    stdout.writeln('[overnight-batch] complete.');
    stdout.writeln('[overnight-batch] report_md=$mdPath');
    stdout.writeln('[overnight-batch] report_json=$jsonPath');
    stdout.writeln(
      '[overnight-batch] successes=$successes skips=$skips failures=$failures '
      'needsReview=$needsReview total=${candidates.length}',
    );
  }, timeout: Timeout.none);
}

class _Candidate {
  _Candidate({
    required this.file,
    required this.relativePath,
    required this.folder,
  });
  final File file;
  final String relativePath;
  final ELibraryManagedFolderDefinition folder;
}

int _firstInt(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? 0 : (rows.first.values.first as num?)?.toInt() ?? 0;

String _timestamp(DateTime value) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}_'
      '${two(value.hour)}-${two(value.minute)}-${two(value.second)}';
}

String _titleFromFileName(String path) {
  var stem = p.basenameWithoutExtension(path);
  stem = stem.replaceFirst(RegExp(r'^en_'), '');
  stem = stem.replaceAll('_', ' ').trim();
  return stem.isEmpty ? p.basenameWithoutExtension(path) : stem;
}

Future<Map<String, Object?>> _collectBookStats(
  Database db,
  String libraryItemId,
  File sourceFile,
) async {
  final sectionCount = _firstInt(
    await db.rawQuery(
      'SELECT COUNT(*) FROM library_document_sections WHERE library_item_id = ?',
      <Object?>[libraryItemId],
    ),
  );
  final blockRows = await db.query(
    'library_document_blocks',
    where: 'library_item_id = ?',
    whereArgs: <Object?>[libraryItemId],
    orderBy: 'display_order ASC',
  );
  var headingCount = 0;
  var paragraphCount = 0;
  var imageCount = 0;
  var frontMatterCount = 0;
  var mainContentCount = 0;
  Map<String, Object?>? firstMainContentBlock;
  for (final row in blockRows) {
    final type = row['block_type']?.toString() ?? '';
    if (type == 'heading') headingCount += 1;
    if (type == 'paragraph') paragraphCount += 1;
    if (type == 'image') imageCount += 1;
    final formatted = LibraryFormattedContent.fromJson(
      row['formatted_content']?.toString(),
    );
    final isFrontMatter =
        formatted.metadata['heading_role']?.toString() == 'front_matter';
    if (isFrontMatter) {
      frontMatterCount += 1;
      continue;
    }
    final hasText = (row['plain_text']?.toString() ?? '').trim().isNotEmpty;
    if (hasText || type == 'image') {
      mainContentCount += 1;
      firstMainContentBlock ??= row;
    }
  }
  final assetDir = Directory(
    p.join(sourceFile.parent.path, '_canonical_assets', libraryItemId),
  );
  var assetCount = 0;
  var assetSize = 0;
  if (await assetDir.exists()) {
    await for (final entity in assetDir.list(recursive: true)) {
      if (entity is File) {
        assetCount += 1;
        assetSize += await entity.length();
      }
    }
  }
  return <String, Object?>{
    'section_count': sectionCount,
    'block_count_total': blockRows.length,
    'heading_count': headingCount,
    'paragraph_count': paragraphCount,
    'image_reference_count': imageCount,
    'toc_node_count': headingCount,
    'front_matter_block_count': frontMatterCount,
    'main_content_block_count': mainContentCount,
    'extracted_asset_count': assetCount,
    'extracted_asset_size_bytes': assetSize,
    'first_main_content_preview': firstMainContentBlock == null
        ? null
        : (firstMainContentBlock['plain_text']?.toString() ?? '')
              .trim()
              .replaceAll(RegExp(r'\s+'), ' ')
              .let((text) => text.length > 100 ? text.substring(0, 100) : text),
  };
}

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

Future<int> _totalAssetSize(String rootPath) async {
  var total = 0;
  await for (final entity in Directory(
    rootPath,
  ).list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.contains('_canonical_assets')) {
      total += await entity.length();
    }
  }
  return total;
}

Future<void> _writeJsonReport({
  required String jsonPath,
  required String rootPath,
  required String dbPath,
  required DateTime overallStart,
  required bool inProgress,
  required List<Map<String, Object?>> books,
  required int totalCandidates,
  required int successes,
  required int skips,
  required int failures,
  required int needsReview,
  required int catalogCountBefore,
  required int alreadyIndexedBefore,
  required int dbSizeBefore,
  Map<String, Object?>? finalSummary,
}) async {
  final payload = <String, Object?>{
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'in_progress': inProgress,
    'root_path': rootPath,
    'db_path': dbPath,
    'overall_start': overallStart.toIso8601String(),
    'total_candidates': totalCandidates,
    'progress_counts': <String, Object?>{
      'successes': successes,
      'skips': skips,
      'failures': failures,
      'needs_review': needsReview,
      'processed': books.length,
    },
    if (finalSummary != null) 'summary': finalSummary,
    'books': books,
  };
  await File(jsonPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
    flush: true,
  );
}

String _renderMarkdownReport({
  required Map<String, Object?> summary,
  required List<Map<String, Object?>> books,
}) {
  final buffer = StringBuffer();
  buffer.writeln('# EGW EPUB Canonical Batch Report');
  buffer.writeln();
  buffer.writeln('- Start: ${summary['overall_start']}');
  buffer.writeln('- Finish: ${summary['overall_finish']}');
  buffer.writeln('- Elapsed: ${summary['elapsed_seconds']}s');
  buffer.writeln('- Root: `${summary['root_path']}`');
  buffer.writeln('- Database: `${summary['db_path']}`');
  buffer.writeln();
  buffer.writeln('## Totals');
  buffer.writeln('- Eligible books: ${summary['total_eligible_books']}');
  buffer.writeln('- Successful indexes: ${summary['successful_indexes']}');
  buffer.writeln(
    '- Already-current skips: ${summary['already_current_skips']}',
  );
  buffer.writeln('- Needs-review books: ${summary['needs_review_books']}');
  buffer.writeln('- Failed books: ${summary['failed_books']}');
  buffer.writeln(
    '- Average successful time: ${summary['average_successful_ms']} ms',
  );
  buffer.writeln('- Fastest: ${jsonEncode(summary['fastest_book'])}');
  buffer.writeln('- Slowest: ${jsonEncode(summary['slowest_book'])}');
  buffer.writeln(
    '- Catalog rows before/after: ${summary['catalog_count_before']} / ${summary['catalog_count_after']}',
  );
  buffer.writeln(
    '- DB size before/after (bytes): ${summary['db_size_before_bytes']} / ${summary['db_size_after_bytes']}',
  );
  buffer.writeln('- DB growth (bytes): ${summary['db_growth_bytes']}');
  buffer.writeln(
    '- Extracted asset size after (bytes): ${summary['extracted_asset_size_after_bytes']}',
  );
  buffer.writeln('- Integrity check: ${summary['integrity_check_result']}');
  buffer.writeln(
    '- Dangling active staging rows: ${summary['dangling_active_staging_rows']}',
  );
  buffer.writeln(
    '- Duplicate library_item ids: ${summary['duplicate_library_item_ids']}',
  );
  buffer.writeln();
  buffer.writeln('## Per-Book Results');
  buffer.writeln();
  buffer.writeln('| # | Title | Status | Elapsed (ms) | Blocks | Warnings |');
  buffer.writeln('|---|---|---|---|---|---|');
  for (final book in books) {
    buffer.writeln(
      '| ${book['sequence']} | ${book['title']} | ${book['final_index_status']} | '
      '${book['elapsed_ms']} | ${book['block_count_total'] ?? book['block_count'] ?? ''} | '
      '${(book['warning_list'] as List<Object?>?)?.join('; ') ?? ''} |',
    );
  }
  return buffer.toString();
}
