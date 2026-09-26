import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/library/data/library_citation_links.dart';
import 'package:studybible2/features/library/presentation/library_verse_popup.dart';

/// Read-only audit of the render-time citation gate against a real,
/// already-imported library: for every work it re-derives what the reader
/// would show (baked links revalidated + fresh detection over unlinked
/// text) and reports what changed versus what was already stored. Citation
/// linking applies app-wide, so every title is in scope. Never opens the
/// live app database directly — point it at a `.backup` copy via
/// CITATION_GATE_AUDIT_DB. Writes nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('citation gate audit against real imported library data', () async {
    final dbPath = Platform.environment['CITATION_GATE_AUDIT_DB'];
    if (dbPath == null) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final bibleDb = await openDatabase(
      p.absolute('assets/databases/bible_base.db'),
      readOnly: true,
    );
    final bookRows = await bibleDb.query(
      'books',
      columns: ['book_number', 'book_name', 'book_index'],
      orderBy: 'book_index',
    );
    final books = bookRows
        .map(
          (row) => BookRecord(
            bookNumber: row['book_number'] as int,
            bookName: row['book_name'] as String,
            bookIndex: row['book_index'] as int,
          ),
        )
        .toList();
    final countRows = await bibleDb.rawQuery(
      'SELECT book_number, chapter, MAX(block_index) AS max_verse '
      'FROM bible_blocks GROUP BY book_number, chapter',
    );
    final verseCounts = <int, Map<int, int>>{};
    for (final row in countRows) {
      final book = (row['book_number'] as num).toInt();
      final chapter = (row['chapter'] as num).toInt();
      final maxVerse = (row['max_verse'] as num).toInt();
      (verseCounts[book] ??= <int, int>{})[chapter] = maxVerse;
    }
    await bibleDb.close();
    bool resolves(String book, String locator) =>
        libraryCitationResolves(book, locator, books, verseCounts);

    final libraryDb = await openDatabase(p.absolute(dbPath), readOnly: true);
    final itemRows = await libraryDb.query(
      'library_items',
      columns: ['id', 'title'],
    );
    final titleById = {
      for (final row in itemRows)
        row['id'] as String: row['title'] as String? ?? '',
    };

    final report = <String, Object?>{};
    for (final itemId in titleById.keys) {
      final title = titleById[itemId]!;
      final blocks = await libraryDb.query(
        'library_document_blocks',
        columns: ['formatted_content'],
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      if (blocks.isEmpty) continue;
      var storedLinks = 0;
      var afterLinks = 0;
      var strippedBadBaked = 0;
      var addedNewlyResolved = 0;
      final strippedExamples = <String>[];
      final addedExamples = <String>[];
      for (final row in blocks) {
        final raw = row['formatted_content'] as String?;
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw) as Map<String, Object?>;
        final nodes = (decoded['nodes'] as List)
            .map((n) => Map<String, Object?>.from(n as Map))
            .toList();
        final before = <String>{
          for (final n in nodes)
            if ((n['link'] as String?)?.startsWith('studybible-citation:') ??
                false)
              n['link'] as String,
        };
        storedLinks += before.length;
        final after = linkLibraryCitations(nodes, resolves: resolves);
        final afterSet = <String>{
          for (final n in after)
            if ((n['link'] as String?)?.startsWith('studybible-citation:') ??
                false)
              n['link'] as String,
        };
        afterLinks += afterSet.length;
        for (final link in before.difference(afterSet)) {
          strippedBadBaked += 1;
          if (strippedExamples.length < 15) {
            strippedExamples.add(
              Uri.decodeComponent(
                link.substring('studybible-citation:'.length),
              ),
            );
          }
        }
        for (final link in afterSet.difference(before)) {
          addedNewlyResolved += 1;
          if (addedExamples.length < 15) {
            addedExamples.add(
              Uri.decodeComponent(
                link.substring('studybible-citation:'.length),
              ),
            );
          }
        }
      }
      report[itemId] = {
        'title': title,
        'stored_baked_links': storedLinks,
        'after_gate_links': afterLinks,
        'stripped_unresolvable_baked': strippedBadBaked,
        'stripped_examples': strippedExamples,
        'newly_linked_after_abbrev_fixes': addedNewlyResolved,
        'newly_linked_examples': addedExamples,
      };
    }
    await libraryDb.close();

    final outPath = p.join(
      p.dirname(dbPath),
      'citation_gate_audit_report.json',
    );
    await File(
      outPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    print('Citation gate audit written to $outPath');
    for (final entry in report.entries) {
      print('${entry.key}: ${jsonEncode(entry.value)}');
    }
  });
}
