import 'dart:convert';
import 'dart:typed_data';
import 'package:studybible2/features/reader/presentation/note_image_layout_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/presentation/note_image_layout.dart';
import 'package:studybible2/features/reader/presentation/note_image_flow.dart';

void main() {
  test('only solid rectangular selections are accepted', () {
    expect(
      NoteImageLayout.fromCells(rows: 3, columns: 3, cells: {0, 1, 3}),
      isNull,
    );
    expect(
      NoteImageLayout.fromCells(rows: 3, columns: 3, cells: {0, 2}),
      isNull,
    );
    final layout = NoteImageLayout.fromCells(
      rows: 3,
      columns: 3,
      cells: {1, 2, 4, 5},
    )!;
    expect(layout.cells, {1, 2, 4, 5});
    expect(NoteImageLayout.fromJson(layout.toJson())!.cells, layout.cells);
  });
  test('layout editing preserves formatting and other metadata', () {
    final original = jsonEncode({
      'source': 'original',
      'spans': [1],
      'base_text_hash': 'old',
    });
    final result = mergeNoteFormattingAndImageLayout(
      original: original,
      formatted: jsonEncode({
        'spans': [2],
        'base_text_hash': 'new',
      }),
      layout: const NoteImageLayout(),
    );
    final decoded = jsonDecode(result!);
    expect(decoded['source'], 'original');
    expect(decoded['spans'], [2]);
    expect(decoded['base_text_hash'], 'new');
    final removed = jsonDecode(noteFormatWithImageLayout(result, null)!);
    expect(removed.containsKey('image_layout'), false);
    expect(removed['spans'], [2]);
  });
  testWidgets('corner image leaves continuous text outside image', (
    tester,
  ) async {
    const text =
        'First paragraph with bold words.\n\nSecond paragraph with cities and Sabbath. 😀 The end.';
    const rect = Rect.fromLTWH(400, 0, 200, 120);
    final plan = planNoteImageFlow(
      text: text,
      formatJson: null,
      style: const TextStyle(fontSize: 20),
      size: const Size(600, 400),
      imageRect: rect,
    );
    expect(plan.fits, true);
    expect(plan.lines.map((l) => text.substring(l.start, l.end)).join(), text);
    for (final line in plan.lines) {
      expect((line.offset & line.painter.size).overlaps(rect), false);
    }
    plan.dispose();
  });

  test('independent block alignments round trip without losing text metadata', () {
    const settings=PresentationBlockAlignments(title:TextAlign.left,body:TextAlign.justify,
      footer:TextAlign.right,citation:TextAlign.center);
    final raw=settings.withFormat(jsonEncode({'spans':[1],'source':'preserved'}));
    final restored=PresentationBlockAlignments.fromFormat(raw);
    expect(restored.title,TextAlign.left);expect(restored.body,TextAlign.justify);
    expect(restored.footer,TextAlign.right);expect(restored.citation,TextAlign.center);
    expect(jsonDecode(raw)['source'],'preserved');expect(jsonDecode(raw)['spans'],[1]);
  });
  testWidgets('preview and full screen share canonical stage geometry', (tester) async {
    Widget stage(double width,double height)=>MaterialApp(home:Center(child:SizedBox(width:width,height:height,
      child:NoteImageFlow(text:'A short note.',formatJson:null,layout:const NoteImageLayout(header:'Header',footer:'Footer'),
        aspectRatio:4/3,image:const ColoredBox(color:Colors.blue),style:const TextStyle(fontSize:28)))));
    await tester.pumpWidget(stage(320,180));
    final first=tester.getSize(find.byType(CustomPaint).last);
    expect(first.width/first.height,greaterThan(1));
    expect(find.textContaining('Text exceeds'),findsNothing);
    await tester.pumpWidget(stage(700,500));
    expect(tester.getSize(find.byType(CustomPaint).last),first);
    expect(tester.takeException(),isNull);
  });
  testWidgets('grid taps retain prior cells and reject disconnected selection', (tester) async {
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>TextButton(onPressed:()=>showNoteImageLayoutEditor(context,
      images:[Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jL1cAAAAASUVORK5CYII='))],text:'Note',formatJson:null),child:const Text('Open')))));
    await tester.tap(find.text('Open'));await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Image cell 1, 1'));await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Use layout')).onPressed,isNull);
    await tester.tap(find.bySemanticsLabel('Image cell 1, 1'));await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Use layout')).onPressed,isNotNull);
    await tester.ensureVisible(find.text('Header and footer'));
    await tester.tap(find.text('Header and footer'));await tester.pumpAndSettle();
    final footer=find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText=='Footer (optional)');
    expect(footer.hitTestable(),findsOneWidget);
    await tester.enterText(footer,'A footer');await tester.pumpAndSettle();
    expect(find.text('A footer'),findsWidgets);
    expect(tester.takeException(),isNull);
  });

  testWidgets('justified Unicode flow paints the same consumed line boundaries', (tester) async {
    const text='Cities and words with family 👨‍👩‍👧‍👦 and café é. More words fill this line and the next.\n\nFinal paragraph.';
    final plan=planNoteImageFlow(text:text,formatJson:null,style:const TextStyle(fontSize:18),
      size:const Size(600,500),imageRect:const Rect.fromLTWH(400,0,200,180),alignment:TextAlign.justify);
    expect(plan.fits,true);
    expect(plan.lines.map((l)=>text.substring(l.start,l.end)).join(),text);
    for(final line in plan.lines) {
      final boundary=line.painter.getLineBoundary(const TextPosition(offset:0));
      final expected=text.substring(line.start,line.end).replaceAll('\n','');
      final painted=line.painter.text!.toPlainText().substring(0,boundary.end).replaceAll('\n','');
      expect(painted,expected);
      expect((line.offset & line.painter.size).overlaps(const Rect.fromLTWH(400,0,200,180)),false);
    }
    plan.dispose();
  });
}
