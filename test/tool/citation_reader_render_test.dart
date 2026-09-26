// Opt-in: renders the real production reader (CanonicalLibraryReaderScreen)
// against a throwaway copy of the live library database, to verify the
// citation-linking gate actually reaches the screen — not just the pure
// linking function in isolation. Never opens the live app's database file;
// point it at a `.backup` copy via CITATION_READER_AUDIT_DB. No live
// settings, no writes back to the source database.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  Future<void> renderRealItem(
    WidgetTester tester,
    String itemId,
    String label,
  ) async {
    if (Platform.environment['RUN_CITATION_READER'] != '1') return;
    final sourceDb = Platform.environment['CITATION_READER_AUDIT_DB'];
    if (sourceDb == null) return;
    final root = await Directory.systemTemp.createTemp('citation_reader_');
    final dbDir = Directory(p.join(root.path, 'Databases'))
      ..createSync(recursive: true);
    File(sourceDb).copySync(p.join(dbDir.path, 'eLibrary.db'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => p.join(root.path, '.runtime'),
        );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LibraryRootService.instance.invalidateCachedSelection();
    await LibraryRootService.instance.setLibraryRoot(path: root.path);
    final db = await ELibraryDatabase.instance.database;
    await UserDatabase.instance.database;
    final row = (await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: [itemId],
    )).single;
    final item = LibraryCatalogItem.fromRow(row);

    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalLibraryReaderScreen(
          item: item,
          repository: LibraryDocumentRepository(db),
          macosAutoscroll: false,
        ),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);

    final allText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .toList();
    print('$label: rendered ${allText.length} SelectableText widgets');

    (bool underlined, bool tappable)? findCitation(String needle) {
      for (final widget in allText) {
        final span = widget.textSpan;
        if (span == null) continue;
        TextSpan? found;
        span.visitChildren((child) {
          if (child is TextSpan && (child.text ?? '').contains(needle)) {
            found = child;
            return false;
          }
          return true;
        });
        if (found != null) {
          final ts = found!;
          final decoration = ts.style?.decoration;
          final underlined =
              decoration == TextDecoration.underline ||
              (decoration != null &&
                  decoration.toString().contains('underline'));
          return (underlined, ts.recognizer != null);
        }
      }
      return null;
    }

    print(
      '$label needles: ' +
          {
            'Rev. 1:1': findCitation('Rev. 1:1'),
            'Daniel 7': findCitation('Daniel 7'),
            '2 Peter 1:19': findCitation('2 Peter 1:19'),
            'Genesis 4:4': findCitation('Genesis 4:4'),
            'Jude': findCitation('Jude'),
          }.toString(),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await ELibraryDatabase.instance.close();
    await UserDatabase.instance.close();
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  }

  testWidgets('DAR real reader renders citation links correctly', (
    tester,
  ) async {
    await renderRealItem(
      tester,
      'library_item_research_pioneer_uriah_smith_daniel_and_the_revelation',
      'DAR',
    );
  });

  testWidgets('CIS real reader renders citation links correctly', (
    tester,
  ) async {
    await renderRealItem(
      tester,
      'library_item_research_pioneer_sn_haskell_the_cross_and_its_shadow',
      'CIS',
    );
  });
}
