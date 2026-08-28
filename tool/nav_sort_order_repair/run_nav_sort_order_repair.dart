// ignore_for_file: avoid_print
//
// Repairs `library_navigation_items.sort_order` values that collide across
// nesting levels.
//
// Root cause (fixed at generation time in
// commentary_research_library_service_epub_indexing.dart /
// commentary_research_library_service_epub_parsing.dart): a heading found
// inside a root's page was given `sortOrder = rootSortOrder * 1000 +
// headingIndex`, which only avoids collisions if roots are spaced at least
// 1000 apart. Real-TOC roots are numbered sequentially (0, 1, 2, ...), so
// that scaling instead landed a heading's sortOrder directly on top of a
// neighboring root's sortOrder, and a flat sort by sortOrder alone then
// interleaved that heading's row with an unrelated chapter.
//
// This script fixes already-imported rows in place. It does NOT re-parse
// any EPUB: parent_id/depth/label/href in the existing rows are correct —
// only the numeric sort_order needs renumbering. For each affected library
// item, it rebuilds the parent/child tree from the existing rows, walks it
// depth-first (siblings ordered by their existing sort_order, which is
// reliable *within* one parent group), and assigns a fresh sequential
// sort_order in visit order — the same algorithm the fixed app code now
// uses for new imports.
//
// Usage:
//   dart run tool/nav_sort_order_repair/run_nav_sort_order_repair.dart \
//     <eLibrary.db path> [--apply] [--report <output.json>]
//
// Without --apply this is a dry run: it prints/writes the report but makes
// no database changes.

import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NavRow {
  _NavRow({
    required this.id,
    required this.parentId,
    required this.label,
    required this.sortOrder,
  });

  final String id;
  final String? parentId;
  final String label;
  final int sortOrder;
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
      'Usage: dart run tool/nav_sort_order_repair/run_nav_sort_order_repair.dart '
      '<eLibrary.db> [--apply] [--report <output.json>]',
    );
    exitCode = 64;
    return;
  }

  final dbPath = positional[0];

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(dbPath);

  // An item is affected if some depth>=2 row shares a sort_order value with
  // a depth==1 row in the same item — the exact collision signature this
  // bug produces.
  final affectedRows = await db.rawQuery('''
    SELECT DISTINCT n.library_item_id
    FROM library_navigation_items n
    WHERE n.depth >= 2 AND n.parent_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM library_navigation_items sib
      WHERE sib.library_item_id = n.library_item_id
        AND sib.depth = 1
        AND sib.sort_order = n.sort_order
    )
  ''');
  final affectedItemIds = affectedRows
      .map((row) => row['library_item_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toList();

  final results = <Map<String, Object?>>[];
  var itemsChanged = 0;
  var rowsChanged = 0;

  await db.transaction((txn) async {
    for (final itemId in affectedItemIds) {
      final rawRows = await txn.query(
        'library_navigation_items',
        columns: ['id', 'parent_id', 'label', 'sort_order'],
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      final rows = rawRows
          .map(
            (row) => _NavRow(
              id: row['id'] as String,
              parentId: row['parent_id'] as String?,
              label: row['label'] as String? ?? '',
              sortOrder: (row['sort_order'] as int?) ?? 0,
            ),
          )
          .toList();

      final childrenByParentId = <String?, List<_NavRow>>{};
      for (final row in rows) {
        childrenByParentId.putIfAbsent(row.parentId, () => []).add(row);
      }
      for (final siblings in childrenByParentId.values) {
        siblings.sort((a, b) {
          final cmp = a.sortOrder.compareTo(b.sortOrder);
          if (cmp != 0) return cmp;
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });
      }

      final newSortOrderById = <String, int>{};
      var nextSortOrder = 0;
      void visit(_NavRow row) {
        newSortOrderById[row.id] = nextSortOrder;
        nextSortOrder += 1;
        for (final child in childrenByParentId[row.id] ?? const []) {
          visit(child);
        }
      }

      for (final root in childrenByParentId[null] ?? const []) {
        visit(root);
      }

      final changes = <Map<String, Object?>>[];
      for (final row in rows) {
        final newSortOrder = newSortOrderById[row.id];
        if (newSortOrder == null || newSortOrder == row.sortOrder) continue;
        changes.add({
          'id': row.id,
          'label': row.label,
          'from': row.sortOrder,
          'to': newSortOrder,
        });
        if (apply) {
          await txn.update(
            'library_navigation_items',
            {'sort_order': newSortOrder},
            where: 'id = ?',
            whereArgs: [row.id],
          );
        }
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
    'items_affected': affectedItemIds.length,
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
    '$itemsChanged/${affectedItemIds.length} items changed, '
    '$rowsChanged rows renumbered.',
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
