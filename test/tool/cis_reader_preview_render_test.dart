// Opt-in rendering of the isolated CIS candidate. No live settings or DB access.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_assets.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('isolated CIS Passover chart renders at narrow and wide widths', (tester) async {
    if (Platform.environment['RUN_CIS_READER_PREVIEW'] != '1') return;
    final root = p.absolute(Platform.environment['CIS_READER_ROOT'] ?? 'tool/Verification/cis_1914_restoration/output/StudyBible2_CIS_current_preview');
    final tableMode = Platform.environment['CIS_READER_TABLE'] == '1';
    final poemMode = Platform.environment['CIS_READER_POEM'] == '1';
    final navigationMode = Platform.environment['CIS_READER_NAVIGATION'] == '1';
    final citationMode = Platform.environment['CIS_READER_CITATION'] == '1';
    final firstOpenMode = Platform.environment['CIS_READER_FIRST_OPEN'] == '1';
    final output = Directory(p.absolute('tool/Verification/cis_1914_restoration/output/reader_checks'));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => p.join(root, '.runtime'));
    final setup = (await tester.runAsync(() async {
      sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
      LibraryRootService.instance.invalidateCachedSelection();
      await LibraryRootService.instance.setLibraryRoot(path: root);
      final db = await ELibraryDatabase.instance.database;
      await UserDatabase.instance.database;
      final report=jsonDecode(await File(p.join(root,'CIS_1914_REHEARSAL_REPORT.json')).readAsString()) as Map<String,dynamic>;
      final itemId=report['item_id'] as String;
      final row = (await db.query('library_items',where:'id=?',whereArgs:[itemId])).single;
      final chart = (await db.rawQuery(citationMode
          ? "SELECT * FROM library_document_blocks WHERE library_item_id=? AND source_refcode='CIS 132.1'"
          : navigationMode
          ? "SELECT * FROM library_document_blocks WHERE library_item_id=? AND plain_text='Chapter 17 - The Sin-Offering'"
          : poemMode
          ? "SELECT * FROM library_document_blocks WHERE library_item_id=? AND plain_text='The Heavenly Priesthood'"
          : tableMode
          ? "SELECT * FROM library_document_blocks WHERE library_item_id=? AND json_extract(formatted_content,'\$.metadata.table_rows') IS NOT NULL AND plain_text LIKE '%Behold the lamb of God%'"
          : "SELECT * FROM library_document_blocks WHERE library_item_id=? AND block_type='image' AND plain_text LIKE 'The Passover: Type and Antitype.%'",[itemId])).single;
      final item = LibraryCatalogItem.fromRow({...row,
        'anchor_id':firstOpenMode ? null : 'canonical:${chart['id']}',
        'paragraph_index':firstOpenMode ? 0 : row['paragraph_index'],
        'last_opened':firstOpenMode ? null : DateTime.now().toIso8601String()});
      await output.create(recursive:true);
      for (final font in ['Roboto','NotoSerif']) {
        final loader = FontLoader(font)..addFont(rootBundle.load('assets/fonts/$font-Regular.ttf'));
        await loader.load();
      }
      final assets=await LibraryDocumentAssets.restore(db:db,itemId:itemId,libraryRoot:Directory(root));
      expect(assets,isNotNull);
      return (db:db,item:item,assets:assets!);
    }))!;
    for (final width in navigationMode ? [1100.0] : [430.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key:key, child:MaterialApp(
        theme:ThemeData(fontFamily:'Roboto'),
        home:CanonicalLibraryReaderScreen(item:setup.item,repository:LibraryDocumentRepository(setup.db),sourceRoot:setup.assets,macosAutoscroll:false),
      )));
      for (var i=0;i<45;i++) {
        await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds:10)));
        await tester.pump(const Duration(milliseconds:100));
      }
      expect(tester.takeException(), isNull);
      if (firstOpenMode) {
        final heading = find.text('Chapter 1 - Light in the Darkness');
        expect(heading, findsWidgets);
        final list = find.byKey(const ValueKey('canonical-flat-list'));
        final top = tester.getTopLeft(list).dy;
        final positions = heading.evaluate().map((e) => tester.getTopLeft(find.byWidget(e.widget)).dy).toList();
        expect(positions.any((y) => y >= top && y < top + 80), isTrue,
          reason:'Fresh CIS must start at Chapter One, not an earlier poem');
      }
      if (!firstOpenMode && !tableMode && !poemMode && !navigationMode && !citationMode) expect(find.byKey(const ValueKey('canonical-local-image')), findsWidgets);
      if (citationMode) {
        final paragraph = tester.widgetList<SelectableText>(find.byType(SelectableText))
            .firstWhere((w) => w.textSpan?.toPlainText().startsWith('The whole burnt-offering had its origin') == true);
        final spans = paragraph.textSpan!.children!.whereType<TextSpan>();
        final citation = spans.firstWhere((s) => s.toPlainText().contains('Genesis 4:4'));
        expect(citation.style!.fontSize, closeTo(paragraph.textSpan!.style!.fontSize! * .85, .001));
        expect(citation.recognizer, isNotNull);
      }
      if (navigationMode) {
        await tester.tap(find.byTooltip('Next section heading'));
        for (var i = 0; i < 25; i++) {
          await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds:10)));
          await tester.pump(const Duration(milliseconds:100));
        }
        final heading = find.byWidgetPredicate((widget) => widget is SelectableText &&
            widget.textSpan?.toPlainText() == 'Chapter 18 - The Burnt-Offering');
        expect(heading, findsOneWidget);
        expect(tester.getTopLeft(heading).dy, inInclusiveRange(180, 330));
      }
      if (poemMode) {
        final lines = tester.widgetList<SelectableText>(find.byType(SelectableText))
            .where((widget) => widget.textSpan?.toPlainText().contains('His earthly work is done') == true).toList();
        expect(lines, isNotEmpty);
        for (final line in lines) expect(line.textAlign, TextAlign.center);
        if (Platform.environment['CIS_READER_COMPACT'] == '1') {
          Finder line(String text) => find.byWidgetPredicate((w) => w is SelectableText && w.textSpan?.toPlainText() == text);
          final first = tester.getRect(line('His earthly work is done,'));
          final second = tester.getRect(line("The Victim's blood is shed,"));
          expect(second.top - first.bottom, closeTo(0, .1), reason: 'Compact centered poem lines must not acquire ordinary paragraph gaps');
        }
        if (Platform.environment['CIS_READER_RELATIVE_SIZE'] == '1') {
          final opening = tester.widgetList<SelectableText>(find.byType(SelectableText))
              .firstWhere((w) => w.textSpan?.toPlainText() == 'He sprinkles with his blood');
          expect(opening.textSpan!.style!.fontSize, lines.first.textSpan!.style!.fontSize,
              reason: 'Source stanza heading and poem line are both 75% of body size');
        }
      }
      if (tableMode) {
        expect(find.byWidgetPredicate((widget) => widget is SelectableText &&
            widget.textSpan?.toPlainText() == 'Type'), findsWidgets);
        expect(find.byWidgetPredicate((widget) => widget is SelectableText &&
            widget.textSpan?.toPlainText() == 'Antitype'), findsWidgets);
      }
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image=await boundary.toImage();
        final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
        await File(p.join(output.path,'${citationMode ? 'inline_citation' : navigationMode ? 'chapter18_navigation' : poemMode ? 'heavenly_priesthood' : tableMode ? 'sin_offering_table' : 'passover'}_${width.toInt()}.png')).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds:1));
    }
    tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
    await tester.runAsync(() async {
      await ELibraryDatabase.instance.close(); await UserDatabase.instance.close();
    });
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
  });
}
