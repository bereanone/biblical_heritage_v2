// ignore_for_file: avoid_print

// Rehearses a canonicalization upgrade against a scratch database only.
// Set V15_REHEARSAL_DB, V15_REHEARSAL_ROOT, and V15_REHEARSAL_REPORT, then
// run flutter test tool/v14_canonical_rehearsal/run_v14_canonical_rehearsal.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'canonicalization scratch rehearsal',
    () async {
      final dbPath = Platform.environment['V15_REHEARSAL_DB'];
      final rootPath = Platform.environment['V15_REHEARSAL_ROOT'];
      final reportPath = Platform.environment['V15_REHEARSAL_REPORT'];
      final limit = int.tryParse(
        Platform.environment['V15_REHEARSAL_LIMIT'] ?? '',
      );
      final onlyIds = (Platform.environment['V15_REHEARSAL_IDS'] ?? '')
          .split(',')
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      if (dbPath == null || rootPath == null || reportPath == null) {
        fail(
          'Set V15_REHEARSAL_DB, V15_REHEARSAL_ROOT, and V15_REHEARSAL_REPORT.',
        );
      }
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await openDatabase(dbPath);
      final repository = LibraryDocumentRepository(db);
      final candidates = await db.rawQuery(
        '''
SELECT i.id, i.title, i.source_type, i.relative_path,
       c.canonicalizer_version,
       (SELECT COUNT(*) FROM library_document_blocks b
        WHERE b.library_item_id = i.id) AS blocks_before
FROM library_document_conversion c
JOIN library_items i ON i.id = c.library_item_id
WHERE c.status = 'complete'
  AND i.deleted_at IS NULL
  AND c.canonicalizer_version < ?
ORDER BY i.title COLLATE NOCASE, i.id
''',
        <Object?>[LibraryDocumentCanonicalizer.version],
      );
      final results = <Map<String, Object?>>[];
      var recanonicalized = 0;
      var missingSource = 0;
      var failed = 0;
      final selected = onlyIds.isEmpty
          ? candidates
          : candidates.where((row) => onlyIds.contains(row['id'])).toList();
      for (final row in selected.take(limit ?? selected.length)) {
        final id = row['id']!.toString();
        final relativePath = row['relative_path']?.toString().trim() ?? '';
        final source = File(p.join(rootPath, relativePath));
        final result = <String, Object?>{
          'id': id,
          'title': row['title'],
          'source_type': row['source_type'],
          'relative_path': relativePath,
          'canonicalizer_version_before': row['canonicalizer_version'],
          'blocks_before': row['blocks_before'],
          'fused_boundaries_before': await _fusedBoundaryCount(db, id),
          'source_path': source.path,
        };
        if (relativePath.isEmpty || !await source.exists()) {
          missingSource++;
          result['status'] = 'skipped_missing_source';
          results.add(result);
          continue;
        }
        try {
          final output = await const LibraryDocumentCanonicalizer()
              .canonicalize(
                db: db,
                libraryItemId: id,
                source: source,
                force: true,
              );
          final conversion = await db.query(
            'library_document_conversion',
            columns: const <String>['canonicalizer_version', 'status'],
            where: 'library_item_id = ?',
            whereArgs: <Object?>[id],
            limit: 1,
          );
          result.addAll(<String, Object?>{
            'status': output.activated
                ? 'recanonicalized'
                : 'validation_failed',
            'blocks_after': await repository.blockCount(id),
            'fused_boundaries_after': await _fusedBoundaryCount(db, id),
            'canonicalizer_version_after':
                conversion.single['canonicalizer_version'],
            'conversion_status_after': conversion.single['status'],
            if (output.validationFailureReason != null)
              'validation_failure_reason': output.validationFailureReason,
          });
          if (output.activated) {
            recanonicalized++;
          } else {
            failed++;
          }
        } catch (error) {
          failed++;
          result.addAll(<String, Object?>{
            'status': 'error',
            'error': error.toString(),
          });
        }
        results.add(result);
      }
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      final report = <String, Object?>{
        'canonicalizer_version_target': LibraryDocumentCanonicalizer.version,
        'candidate_count': candidates.length,
        'selected_candidate_count': selected.length,
        'recanonicalized': recanonicalized,
        'missing_source': missingSource,
        'failed': failed,
        'integrity_check': integrity.single.values.single,
        'results': results,
      };
      await File(reportPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      print(
        'canonicalization rehearsal: ${candidates.length} candidates at batch start; '
        '$recanonicalized recanonicalized, $missingSource missing source, '
        '$failed failed. Report: $reportPath',
      );
      await db.close();
      expect(failed, 0);
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<int> _fusedBoundaryCount(Database db, String libraryItemId) async {
  final rows = await db.query(
    'library_document_blocks',
    columns: const <String>['formatted_content'],
    where: 'library_item_id = ?',
    whereArgs: <Object?>[libraryItemId],
  );
  var count = 0;
  for (final row in rows) {
    final formatted = row['formatted_content']?.toString();
    if (formatted == null || formatted.isEmpty) continue;
    final decoded = jsonDecode(formatted) as Map<String, dynamic>;
    final nodes = decoded['nodes'] as List<dynamic>? ?? const <dynamic>[];
    String? previousText;
    for (final node in nodes) {
      if (node is! Map || node['type'] != 'text') {
        previousText = null;
        continue;
      }
      final text = node['text']?.toString() ?? '';
      if (previousText != null &&
          previousText.isNotEmpty &&
          text.isNotEmpty &&
          RegExp(r'[A-Za-z0-9]$').hasMatch(previousText) &&
          RegExp(r'^[A-Za-z0-9]').hasMatch(text)) {
        count++;
      }
      previousText = text;
    }
  }
  return count;
}
