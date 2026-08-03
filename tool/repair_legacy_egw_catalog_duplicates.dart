import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/utilities/data/elibrary_catalog_duplicate_repair_service.dart';

Future<void> main(List<String> arguments) async {
  final summaryOnly = arguments.contains('--summary');
  final paths = arguments.where((value) => value != '--summary').toList();
  if (paths.length != 1 || paths.single.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/repair_legacy_egw_catalog_duplicates.dart <eLibrary.db>',
    );
    exitCode = 64;
    return;
  }
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(paths.single);
  try {
    final report = await ELibraryCatalogDuplicateRepairService.instance.repair(
      db: db,
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'duplicate_logical_books_found': report.duplicateLogicalBooksFound,
        'legacy_catalog_rows_retired': report.legacyCatalogRowsRetired,
        'user_state_rows_migrated': report.userStateRowsMigrated,
        'generated_index_rows_removed': report.indexRowsRemoved,
        'commentary_research_link_rows_removed': report.linkRowsRemoved,
        'ambiguous_duplicates': report.ambiguousDuplicates,
        if (!summaryOnly)
          'pairs': report.pairs
              .map(
                (pair) => <String, String>{
                  'canonical_id': pair.canonicalId,
                  'canonical_path': pair.canonicalPath,
                  'legacy_id': pair.legacyId,
                  'legacy_path': pair.legacyPath,
                },
              )
              .toList(growable: false),
      }),
    );
  } finally {
    await db.close();
  }
}
