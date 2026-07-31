// Explicit, opt-in production execution harness. A normal test run is a
// no-op for both tests below. Detection is read-only (intended to be run
// against a checksum-verified backup copy of eLibrary.db, never the live
// file). Repair writes to whatever PIONEER_DB_PATH points at, so it must
// only ever be pointed at the live database with the app fully closed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/features/library/data/canonical_activation.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/data/library_xml_html_entities.dart';

const String _pioneerSourceType = 'pioneer_epub_import';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detect Pioneer entity and heading defects', () async {
    if (Platform.environment['RUN_PIONEER_ENTITY_HEADING_DETECT'] != '1') {
      return;
    }
    final dbPath = (Platform.environment['PIONEER_DB_PATH'] ?? '').trim();
    final outputDir = (Platform.environment['PIONEER_AUDIT_OUTPUT_DIR'] ?? '')
        .trim();
    if (dbPath.isEmpty || outputDir.isEmpty) {
      fail('PIONEER_DB_PATH and PIONEER_AUDIT_OUTPUT_DIR are required.');
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(dbPath, readOnly: true);
    try {
      final metadataRows = await db.query(
        'library_items',
        columns: const <String>['id', 'title', 'author'],
        where: 'source_type = ? AND deleted_at IS NULL',
        whereArgs: <Object?>[_pioneerSourceType],
      );
      final metadataAffected = <Map<String, Object?>>[];
      for (final row in metadataRows) {
        final title = row['title']?.toString();
        final author = row['author']?.toString();
        final decodedTitle = title == null
            ? null
            : decodeXmlHtmlEntities(title);
        final decodedAuthor = author == null
            ? null
            : decodeXmlHtmlEntities(author);
        if (decodedTitle != title || decodedAuthor != author) {
          metadataAffected.add(<String, Object?>{
            'library_item_id': row['id'],
            'title': title,
            'author': author,
            'decoded_title': decodedTitle,
            'decoded_author': decodedAuthor,
          });
        }
      }

      final headingRows = await db.rawQuery(
        '''
        SELECT b.library_item_id, i.title, b.plain_text
        FROM library_document_blocks b
        JOIN library_items i ON i.id = b.library_item_id
        WHERE i.source_type = ? AND i.deleted_at IS NULL
          AND b.block_type = 'heading'
      ''',
        <Object?>[_pioneerSourceType],
      );
      final barePageNumber = RegExp(r'^\d{1,4}$');
      final headingCountByItem = <String, int>{};
      final titleByItem = <String, String?>{};
      for (final row in headingRows) {
        final text = (row['plain_text']?.toString() ?? '').trim();
        if (!barePageNumber.hasMatch(text)) continue;
        final itemId = row['library_item_id']!.toString();
        headingCountByItem[itemId] = (headingCountByItem[itemId] ?? 0) + 1;
        titleByItem[itemId] = row['title']?.toString();
      }
      final headingAffected = headingCountByItem.entries
          .map(
            (entry) => <String, Object?>{
              'library_item_id': entry.key,
              'title': titleByItem[entry.key],
              'affected_heading_count': entry.value,
            },
          )
          .toList(growable: false);

      final summary = <String, Object?>{
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'source_db_path': dbPath,
        'metadata_affected_count': metadataAffected.length,
        'heading_affected_count': headingAffected.length,
        'expected_metadata_count': 13,
        'expected_heading_count': 263,
      };
      stdout.writeln('[pioneer-defect-detect] $summary');

      final report = <String, Object?>{
        'summary': summary,
        'metadata_affected': metadataAffected,
        'heading_affected': headingAffected,
      };
      final outFile = File(
        p.join(outputDir, 'pioneer_epub_entity_and_heading_defects.json'),
      );
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );

      final metadataDeviation =
          (metadataAffected.length - 13).abs() / (13 == 0 ? 1 : 13);
      final headingDeviation =
          (headingAffected.length - 263).abs() / (263 == 0 ? 1 : 263);
      if (metadataDeviation > 0.2 || headingDeviation > 0.2) {
        fail(
          'Detected counts deviate from the expected 13/263 by more than '
          '20% (metadata=${metadataAffected.length}, '
          'heading=${headingAffected.length}) — stopping for human review.',
        );
      }
    } finally {
      await db.close();
    }
  });

  test(
    'repair Pioneer entity and heading defects',
    () async {
      if (Platform.environment['RUN_PIONEER_ENTITY_HEADING_REPAIR'] != '1') {
        return;
      }
      final dbPath = (Platform.environment['PIONEER_DB_PATH'] ?? '').trim();
      final auditJsonPath =
          (Platform.environment['PIONEER_AUDIT_JSON_PATH'] ?? '').trim();
      final rootPath = (Platform.environment['PIONEER_LIBRARY_ROOT'] ?? '')
          .trim();
      final reportPath =
          (Platform.environment['PIONEER_REPAIR_REPORT_PATH'] ?? '').trim();
      if (dbPath.isEmpty ||
          auditJsonPath.isEmpty ||
          rootPath.isEmpty ||
          reportPath.isEmpty) {
        fail(
          'PIONEER_DB_PATH, PIONEER_AUDIT_JSON_PATH, PIONEER_LIBRARY_ROOT, '
          'and PIONEER_REPAIR_REPORT_PATH are required.',
        );
      }

      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final audit =
          jsonDecode(await File(auditJsonPath).readAsString())
              as Map<String, Object?>;
      final metadataAffected = (audit['metadata_affected'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final headingAffected = (audit['heading_affected'] as List<Object?>)
          .cast<Map<String, Object?>>();

      final db = await openDatabase(dbPath);
      try {
        final repository = LibraryDocumentRepository(db);
        final metadataResults = <Map<String, Object?>>[];
        for (final entry in metadataAffected) {
          final itemId = entry['library_item_id']!.toString();
          final currentRows = await db.query(
            'library_items',
            columns: const <String>['title', 'author'],
            where: 'id = ?',
            whereArgs: <Object?>[itemId],
            limit: 1,
          );
          if (currentRows.isEmpty) {
            metadataResults.add(<String, Object?>{
              'library_item_id': itemId,
              'status': 'skipped_missing_row',
            });
            continue;
          }
          final currentTitle = currentRows.first['title']?.toString();
          final currentAuthor = currentRows.first['author']?.toString();
          final decodedTitle = currentTitle == null
              ? null
              : decodeXmlHtmlEntities(currentTitle);
          final decodedAuthor = currentAuthor == null
              ? null
              : decodeXmlHtmlEntities(currentAuthor);
          final titleChanged =
              decodedTitle != null && decodedTitle != currentTitle;
          final authorChanged =
              decodedAuthor != null && decodedAuthor != currentAuthor;
          if (!titleChanged && !authorChanged) {
            metadataResults.add(<String, Object?>{
              'library_item_id': itemId,
              'status': 'already_current',
            });
            continue;
          }
          await repository.updateCatalogMetadata(
            itemId,
            title: titleChanged ? decodedTitle : null,
            author: authorChanged ? decodedAuthor : null,
          );
          metadataResults.add(<String, Object?>{
            'library_item_id': itemId,
            'status': 'updated',
            'before_title': currentTitle,
            'after_title': titleChanged ? decodedTitle : currentTitle,
            'before_author': currentAuthor,
            'after_author': authorChanged ? decodedAuthor : currentAuthor,
          });
        }
        stdout.writeln(
          '[pioneer-defect-repair] metadata: '
          '${metadataResults.where((r) => r['status'] == 'updated').length} '
          'updated of ${metadataAffected.length}',
        );

        final headingResults = <Map<String, Object?>>[];
        for (final entry in headingAffected) {
          final itemId = entry['library_item_id']!.toString();
          final itemRows = await db.query(
            'library_items',
            columns: const <String>['relative_path', 'file_format'],
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: <Object?>[itemId],
            limit: 1,
          );
          if (itemRows.isEmpty) {
            headingResults.add(<String, Object?>{
              'library_item_id': itemId,
              'status': 'skipped_missing_row',
            });
            continue;
          }
          final row = itemRows.first;
          if ((row['file_format']?.toString() ?? '').trim().toLowerCase() !=
              'epub') {
            headingResults.add(<String, Object?>{
              'library_item_id': itemId,
              'status': 'skipped_not_epub',
            });
            continue;
          }
          final relativePath = row['relative_path']?.toString().trim() ?? '';
          if (relativePath.isEmpty) {
            headingResults.add(<String, Object?>{
              'library_item_id': itemId,
              'status': 'skipped_missing_relative_path',
            });
            continue;
          }
          final source = File(p.join(p.normalize(rootPath), relativePath));
          if (!await source.exists()) {
            headingResults.add(<String, Object?>{
              'library_item_id': itemId,
              'status': 'skipped_missing_file',
              'path': source.path,
            });
            continue;
          }
          final beforeCount = await repository.blockCount(itemId);
          final outcome = await CanonicalActivation.activate(
            db: db,
            libraryItemId: itemId,
            source: source,
            force: true,
          );
          final afterCount = await repository.blockCount(itemId);
          headingResults.add(<String, Object?>{
            'library_item_id': itemId,
            'status': outcome.isReady ? 'regenerated' : 'rejected',
            'phase': outcome.phase.name,
            'before_block_count': beforeCount,
            'after_block_count': afterCount,
          });
        }
        stdout.writeln(
          '[pioneer-defect-repair] headings: '
          '${headingResults.where((r) => r['status'] == 'regenerated').length} '
          'regenerated of ${headingAffected.length}',
        );

        final report = <String, Object?>{
          'completed_at': DateTime.now().toUtc().toIso8601String(),
          'metadata_results': metadataResults,
          'heading_results': headingResults,
        };
        final outFile = File(reportPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
      } finally {
        await db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
