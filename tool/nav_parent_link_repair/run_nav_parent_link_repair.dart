// ignore_for_file: avoid_print
//
// Repairs `library_navigation_items.parent_id` for real embedded-TOC/navMap
// entries (`nav_type = 'toc'`) that were imported with no parent link at all,
// regardless of how deeply nested they actually are.
//
// Root cause (fixed at generation time in
// commentary_research_library_service_epub_parsing.dart's
// `_extractNavigationEntriesFromDocument`): every anchor parsed directly out
// of a book's embedded TOC document was given `parentId: null`, even though
// the very same function estimates a nesting `depth` for each one by
// counting unclosed `<ol>` tags. The Contents UI builds its tree strictly
// from `parent_id` (see `buildLibraryNavigationTree`), so any book whose real
// TOC has genuine sub-nesting — e.g. Early Writings' "Experience and Views"
// section containing "My First Vision", "Subsequent Visions", etc. — always
// rendered completely flat, no matter how deep `depth` said it should be.
//
// This script fixes already-imported rows in place. It does NOT re-parse any
// EPUB: for each library item, it takes just the `nav_type = 'toc'` rows
// (the only rows this bug affects — `body`/`spine` rows already have correct
// parent_id), recovers their original document order from the trailing
// numeric index baked into `id` (assigned sequentially during extraction and
// never touched by any later renumbering), then walks that ordered list with
// a depth stack — the same algorithm the fixed app code now uses at import
// time — assigning each entry's `parent_id` to the nearest preceding entry
// with a strictly smaller depth (or leaving it null if none exists).
//
// Usage:
//   dart run tool/nav_parent_link_repair/run_nav_parent_link_repair.dart \
//     <eLibrary.db path> [--apply] [--report <output.json>]
//
// Without --apply this is a dry run: it prints/writes the report but makes
// no database changes.

import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TocRow {
  _TocRow({required this.id, required this.depth, required this.orderKey});

  final String id;
  final int depth;
  final int orderKey;
}

int _orderKeyFor(String id) {
  final match = RegExp(r'_(\d+)$').firstMatch(id);
  return match == null ? 0 : int.parse(match.group(1)!);
}

Future<void> main(List<String> arguments) async {
  final positional = <String>[];
  var apply = false;
  String? reportPath;
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--apply') {
      apply = true;
    } else if (arg == '--report') {
      reportPath = arguments[++i];
    } else {
      positional.add(arg);
    }
  }

  if (positional.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/nav_parent_link_repair/run_nav_parent_link_repair.dart '
      '<eLibrary.db> [--apply] [--report <output.json>]',
    );
    exitCode = 64;
    return;
  }

  final dbPath = positional[0];

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(dbPath);

  final itemRows = await db.rawQuery('''
    SELECT DISTINCT library_item_id
    FROM library_navigation_items
    WHERE nav_type = 'toc'
  ''');
  final itemIds = itemRows
      .map((row) => row['library_item_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toList();

  final results = <Map<String, Object?>>[];
  var itemsChanged = 0;
  var rowsChanged = 0;

  await db.transaction((txn) async {
    for (final itemId in itemIds) {
      final rawRows = await txn.query(
        'library_navigation_items',
        columns: ['id', 'parent_id', 'depth', 'label'],
        where: 'library_item_id = ? AND nav_type = ?',
        whereArgs: [itemId, 'toc'],
      );

      final rows =
          rawRows
              .map(
                (row) => _TocRow(
                  id: row['id'] as String,
                  depth: (row['depth'] as int?) ?? 0,
                  orderKey: _orderKeyFor(row['id'] as String),
                ),
              )
              .toList()
            ..sort((a, b) => a.orderKey.compareTo(b.orderKey));

      final existingParentById = <String, String?>{
        for (final row in rawRows) row['id'] as String: row['parent_id'] as String?,
      };
      final labelById = <String, String>{
        for (final row in rawRows) row['id'] as String: (row['label'] as String?) ?? '',
      };

      final stack = <_TocRow>[];
      final changes = <Map<String, Object?>>[];
      for (final row in rows) {
        while (stack.isNotEmpty && stack.last.depth >= row.depth) {
          stack.removeLast();
        }
        final newParentId = stack.isEmpty ? null : stack.last.id;
        final currentParentId = existingParentById[row.id];
        if (newParentId != currentParentId) {
          changes.add({
            'id': row.id,
            'label': labelById[row.id],
            'depth': row.depth,
            'from_parent_id': currentParentId,
            'to_parent_id': newParentId,
          });
          if (apply) {
            await txn.update(
              'library_navigation_items',
              {'parent_id': newParentId},
              where: 'id = ?',
              whereArgs: [row.id],
            );
          }
        }
        stack.add(row);
      }

      if (changes.isNotEmpty) {
        itemsChanged += 1;
        rowsChanged += changes.length;
        results.add({
          'library_item_id': itemId,
          'rows_changed': changes.length,
          'changes': changes,
        });
      }
    }
  });

  final report = {
    'apply': apply,
    'items_scanned': itemIds.length,
    'items_changed': itemsChanged,
    'rows_changed': rowsChanged,
    'results': results,
  };

  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  if (reportPath != null) {
    await File(reportPath).writeAsString(encoded);
  }
  print(
    '${apply ? "APPLIED" : "DRY RUN"}: '
    '$itemsChanged/${itemIds.length} items changed, '
    '$rowsChanged rows re-parented.',
  );
  if (reportPath != null) {
    print('Report written to $reportPath');
  }

  if (apply) {
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    final result = integrity.first.values.first;
    print('PRAGMA integrity_check: $result');
  }

  await db.close();
}
