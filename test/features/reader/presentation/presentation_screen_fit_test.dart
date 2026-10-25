import 'package:studybible2/features/reader/presentation/presentation_fit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:studybible2/features/reader/presentation/note_image_flow.dart';
import 'package:studybible2/features/reader/data/presentation/note_image_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_models.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_slide_settings.dart';
import 'package:studybible2/features/reader/presentation/presentation_slide_canvas.dart';
import 'package:studybible2/features/reader/presentation/viewer_presentation_settings.dart';

const sabbath =
    '8 Remember the sabbath day, to keep it holy.\n'
    '9 Six days shalt thou labour, and do all thy work:\n'
    '10 But the seventh day is the sabbath of the LORD thy God: in it thou shalt not do any work, '
    'thou, nor thy son, nor thy daughter, thy manservant, nor thy maidservant, nor thy cattle, '
    'nor thy stranger that is within thy gates:\n'
    '11 For in six days the LORD made heaven and earth, the sea, and all that in them is, '
    'and rested the seventh day: wherefore the LORD blessed the sabbath day, and hallowed it.';

PresentationSlideItem passage(String text, {bool image = false}) =>
    PresentationSlideItem(
      id: 'passage',
      presentationSlideId: 'slide',
      sourceType: 'bible',
      sourceId: '1',
      bookNumber: 2,
      chapter: 20,
      verse: 8,
      verseEnd: 11,
      layoutRegion: PresentationLayoutRegion.full,
      layoutOrder: 0,
      itemKind: PresentationItemKind.verse,
      displayTitle: '',
      displayText: text,
      mediaRefs: image ? ['missing-review-image.png'] : null,
    );

Future<void> showSlide(
  WidgetTester tester, {
  required Size size,
  String text = sabbath,
  double scale = 1,
  bool image = false,
  PresentationAspectRatioPreset aspect = PresentationAspectRatioPreset.auto,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: PresentationSlideCanvas(
            slide: PresentationSlide(
              id: 'slide',
              settingsKey: 'slide',
              slideNumber: 1,
              layoutType: PresentationLayoutType.fullWidth,
              items: [passage(text, image: image)],
            ),
            aspectRatioPreset: aspect,
            bookNames: const {2: 'Exodus'},
            settings: const PresentationSlideSettings(),
            mediaRootPaths: const [],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('linked Bible entries retain each saved image zone in presentation', (tester) async {
    PresentationSlideItem entry(String id, int column) => PresentationSlideItem(
      id: id, presentationSlideId: 'linked-zones', sourceType: 'bible', sourceId: id,
      bookNumber: 2, chapter: 20, verse: 8, verseEnd: 8,
      layoutRegion: PresentationLayoutRegion.full, layoutOrder: 0,
      itemKind: PresentationItemKind.verse, displayTitle: '', displayText: 'Remember the sabbath day.',
      noteFormatJson: mergeNoteFormattingAndImageLayout(original: null, formatted: null,
        layout: NoteImageLayout(rows: 4, columns: 4, row: 0, column: column, rowSpan: 2, columnSpan: 1)),
      mediaRefs: ['$id.png']);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PresentationSlideCanvas(
      slide: PresentationSlide(id: 'linked-zones', settingsKey: 'linked-zones', slideNumber: 1,
        layoutType: PresentationLayoutType.twoColumns, items: [entry('first', 0), entry('second', 3)]),
      aspectRatioPreset: PresentationAspectRatioPreset.auto, bookNames: const {2:'Exodus'},
      settings: const PresentationSlideSettings(layoutOverride: PresentationLayoutPreference.textLeftImageRight),
      mediaRootPaths: const [],
    ))));
    await tester.pumpAndSettle();
    final flows = tester.widgetList<NoteImageFlow>(find.byType(NoteImageFlow)).toList();
    expect(flows.length, 2);
    expect(flows.map((flow) => flow.elementItemId), ['first', 'second']);
    expect(flows.map((flow) => flow.layout.column), [0, 3]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Bible image zones wrap Scripture and keep citation and attached note', (tester) async {
    const layout = NoteImageLayout(rows: 4, columns: 4, row: 0, column: 2, rowSpan: 2, columnSpan: 2);
    for (final size in [const Size(1100, 760), const Size(390, 800)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PresentationSlideCanvas(
        slide: PresentationSlide(id: 'zones', settingsKey: 'zones', slideNumber: 1,
          layoutType: PresentationLayoutType.fullWidth,
          items: [PresentationSlideItem(id: 'scripture', presentationSlideId: 'zones',
            sourceType: 'bible', sourceId: '1', bookNumber: 2, chapter: 20,
            verse: 8, verseEnd: 11, layoutRegion: PresentationLayoutRegion.full,
            layoutOrder: 0, itemKind: PresentationItemKind.verse, displayTitle: '',
            displayText: sabbath, noteText: 'An independently editable explanation.',
            noteFormatJson: mergeNoteFormattingAndImageLayout(original: null, formatted: null, layout: layout),
            mediaRefs: const ['missing-zone-test.png'])]),
        aspectRatioPreset: PresentationAspectRatioPreset.auto,
        bookNames: const {2: 'Exodus'}, settings: const PresentationSlideSettings(
          elementFontSizes: {'item:scripture:citation': 17}), mediaRootPaths: const [],
      ))));
      await tester.pumpAndSettle();
      final flow = tester.widget<NoteImageFlow>(find.byType(NoteImageFlow));
      expect(flow.text, sabbath);
      expect(flow.layout.cells, layout.cells);
      expect(flow.layout.footer, 'Exodus 20:8-11');
      expect(flow.footerElementPart, 'citation');
      expect(find.text('An independently editable explanation.', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
  });
  testWidgets('Scripture fitting rejects a font that splits baptism', (tester) async {
    double measure(double font, [String text = 'baptism']) => presentationTextHeight(
      slide: PresentationSlide(id: 'word', settingsKey: 'word', slideNumber: 1,
        layoutType: PresentationLayoutType.fullWidth, items: [passage(text)]),
      bookNames: const {2: 'Exodus'}, width: 100, fontSize: font,
      bodyStyle: const TextStyle(), noteStyle: const TextStyle(),
      headingStyle: const TextStyle(), direction: TextDirection.ltr,
      textScaler: TextScaler.noScaling, alignment: TextAlign.left,
    );
    expect(measure(40), double.infinity);
    expect(measure(12).isFinite, true);
    // In the test font, seven letters fit at 14px but the comma does not.
    expect(measure(14, 'baptism, so'), double.infinity);
    expect(measure(12, 'baptism, so').isFinite, true);
  });

  testWidgets('auto grid wrap uses the whole portrait text region', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PresentationSlideCanvas(
            slide: PresentationSlide(
              id: 'grid',
              settingsKey: 'grid',
              slideNumber: 1,
              layoutType: PresentationLayoutType.fullWidth,
              items: [
                PresentationSlideItem(
                  id: 'note',
                  presentationSlideId: 'grid',
                  sourceType: 'note',
                  sourceId: '1',
                  bookNumber: 0,
                  chapter: 0,
                  verse: 0,
                  verseEnd: 0,
                  layoutRegion: PresentationLayoutRegion.full,
                  layoutOrder: 0,
                  itemKind: PresentationItemKind.note,
                  displayTitle: '',
                  displayText: 'A short note.',
                  noteFormatJson: noteFormatWithImageLayout(
                    null,
                    const NoteImageLayout(),
                  ),
                  mediaRefs: ['missing.png'],
                ),
              ],
            ),
            aspectRatioPreset: PresentationAspectRatioPreset.auto,
            bookNames: const {},
            settings: const PresentationSlideSettings(),
            mediaRootPaths: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final painting = find.descendant(
      of: find.byType(NoteImageFlow),
      matching: find.byType(CustomPaint),
    );
    final stage = tester.getSize(painting.last);
    expect(stage.height, greaterThan(stage.width));
    expect(find.textContaining('Text exceeds'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wrapped image layout recalculates warning after resize and merge',
    (tester) async {
      Future<void> stage(double width, double height, int span) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: width,
                height: height,
                child: NoteImageFlow(
                  minimumDisplayedFontSize: 18,
                  text: sabbath.split('\n11').first,
                  formatJson: null,
                  layout: NoteImageLayout(column: 3 - span, columnSpan: span),
                  image: const ColoredBox(color: Colors.blue),
                  style: const TextStyle(fontSize: 24, height: 1.18),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await stage(700, 500, 1);
      expect(find.textContaining('Text exceeds'), findsNothing);
      await stage(320, 180, 2);
      expect(find.textContaining('Text exceeds'), findsOneWidget);
      await stage(700, 500, 1);
      expect(find.textContaining('Text exceeds'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(1024, 768),
    const Size(390, 700),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('complete passage fits or warns at $size scale $scale', (
        tester,
      ) async {
        await showSlide(tester, size: size, scale: scale);
        expect(tester.takeException(), isNull);
        final warning = find.textContaining('Text exceeds');
        final scrolls = tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        );
        final clipped = scrolls.any((s) => s.position.maxScrollExtent > 1);
        if (clipped)
          expect(warning, findsWidgets, reason: 'Overflow must be explicit');
        for (final p in tester.renderObjectList<RenderParagraph>(
          find.byType(RichText),
        )) {
          expect(p.didExceedMaxLines, isFalse);
        }
        expect(find.text('Exodus 20:8-11', findRichText: true), findsOneWidget);
      });
    }
  }
  testWidgets('overcrowded slide warns instead of silently cutting text', (
    tester,
  ) async {
    await showSlide(
      tester,
      size: const Size(390, 700),
      text: List.filled(8, sabbath).join('\n'),
    );
    expect(find.textContaining('Text exceeds'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('image reservation triggers a fresh fit and warning', (
    tester,
  ) async {
    await showSlide(
      tester,
      size: const Size(600, 400),
      image: true,
      text: sabbath,
    );
    expect(find.textContaining('Text exceeds'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fitting uses lower area instead of counting citation as body', (
    tester,
  ) async {
    await showSlide(
      tester,
      size: const Size(1024, 768),
      aspect: PresentationAspectRatioPreset.sixteenByNine,
    );
    final body = tester.renderObject<RenderParagraph>(
      find
          .byType(RichText)
          .evaluate()
          .map((e) => e.widget as RichText)
          .where((w) => w.text.toPlainText() == sabbath)
          .map((w) => find.byWidget(w))
          .single,
    );
    expect(body.size.height, greaterThan(390));
    expect(find.textContaining('Text exceeds'), findsNothing);
  });
}
