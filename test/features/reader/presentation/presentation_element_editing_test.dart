import 'package:studybible2/features/reader/presentation/note_image_flow.dart';
import 'package:studybible2/features/reader/data/presentation/note_image_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_models.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_slide_settings.dart';
import 'package:studybible2/features/reader/presentation/presentation_element.dart';
import 'package:studybible2/features/reader/presentation/presentation_slide_canvas.dart';
import 'package:studybible2/features/reader/presentation/presentation_slide_editor.dart';
import 'package:studybible2/features/reader/presentation/viewer_presentation_settings.dart';

PresentationSlideItem passage(String id, String text) => PresentationSlideItem(
  id: id,
  presentationSlideId: 'linked',
  sourceType: 'verse',
  sourceId: id,
  bookNumber: 1,
  chapter: 1,
  verse: id == 'first' ? 1 : 2,
  verseEnd: 0,
  layoutRegion: PresentationLayoutRegion.full,
  layoutOrder: 0,
  itemKind: PresentationItemKind.verse,
  displayTitle: '',
  displayText: text,
  noteText: id == 'second' ? 'Attached explanation.' : null,
);

void main() {
  testWidgets(
    'heading and linked passages resize independently and survive Save',
    (tester) async {
      var settings = const PresentationSlideSettings(fontSizeOverride: 24);
      final slide = PresentationSlide(
        id: 'linked',
        settingsKey: 'linked',
        slideNumber: 1,
        slideTitle: 'A heading',
        layoutType: PresentationLayoutType.fullWidth,
        items: [
          passage('first', 'First linked passage.'),
          passage('second', 'Second linked passage.'),
        ],
      );
      Widget app(String key) => MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: PresentationSlideEditor(
            key: ValueKey(key),
            settings: settings,
            onSave: (value) async => settings = value,
            builder: (value, report) => PresentationSlideCanvas(
              slide: slide,
              aspectRatioPreset: PresentationAspectRatioPreset.auto,
              bookNames: const {1: 'Genesis'},
              settings: value,
              mediaRootPaths: const [],
              onBodyFontSizeResolved: report,
            ),
          ),
        ),
      );
      double font(String text) =>
          tester.widget<Text>(find.text(text)).style!.fontSize!;
      await tester.pumpWidget(app('first'));
      await tester.pumpAndSettle();
      final titleBefore = font('A heading');
      await tester.longPress(find.text('A heading'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Larger text'));
      await tester.pump();
      expect(font('A heading'), greaterThan(titleBefore));
      for (final alignment in ['left', 'center', 'right', 'justify']) {
        await tester.tap(find.byTooltip('Align $alignment')); await tester.pump();
        expect(tester.widget<Text>(find.text('A heading')).textAlign, TextAlign.values.firstWhere((v) => v.name == alignment));
        expect(tester.widget<Text>(find.text('First linked passage.')).textAlign, TextAlign.left);
      }

      expect(font('First linked passage.'), 24);
      expect(font('Second linked passage.'), 24);
      await tester.tap(find.text('Second linked passage.'));
      await tester.pump();
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.pump();
      expect(font('First linked passage.'), 24);
      expect(font('Second linked passage.'), lessThan(24));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        settings.elementFontSizes.keys,
        containsAll(['slide:title', presentationElementKey('second', 'body')]),
      );
      expect(
        settings.elementFontSizes.containsKey(
          presentationElementKey('first', 'body'),
        ),
        false,
      );
      await tester.pumpWidget(app('reopen'));
      await tester.pumpAndSettle();
      expect(
        font('Second linked passage.'),
        settings.elementFontSizes[presentationElementKey('second', 'body')],
      );
      expect(font('First linked passage.'), 24);
      expect(tester.widget<Text>(find.text('A heading')).textAlign, TextAlign.justify);
    },
  );

  testWidgets('selected reference Undo and Fit preserve other draft elements', (
    tester,
  ) async {
    PresentationSlideSettings? draft, saved;
    const initial = PresentationSlideSettings(
      fontSizeOverride: 30,
      elementFontSizes: {'heading': 25, 'reference': 18},
      elementAlignments: {'heading': PresentationAlignmentPreference.center, 'reference': PresentationAlignmentPreference.right},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PresentationSlideEditor(
            settings: initial,
            onSave: (value) async => saved = value,
            builder: (settings, report) {
              draft = settings;
              report(30);
              return Column(
                children: [
                  PresentationElement(
                    elementKey: 'heading',
                    label: 'Heading',
                    defaultFontSize: 20,
                    child: const Text('Heading'),
                  ),
                  PresentationElement(
                    elementKey: 'reference',
                    label: 'Reference',
                    defaultFontSize: 14,
                    child: const Text('Reference'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.longPress(find.text('Heading'));
    await tester.pump();
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pump();
    final heading = draft!.elementFontSizes['heading'];
    await tester.tap(find.text('Reference'));
    await tester.pump();
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pump();
    await tester.tap(find.byTooltip('Align justify')); await tester.pump();
      await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(draft!.elementFontSizes['reference'], 18);
      expect(draft!.elementAlignments['reference'], PresentationAlignmentPreference.right);
      expect(draft!.elementAlignments['heading'], PresentationAlignmentPreference.center);
    expect(draft!.elementFontSizes['heading'], heading);
    await tester.tap(find.text('Fit'));
    await tester.pump();
    expect(draft!.elementFontSizes.containsKey('reference'), false);
    expect(draft!.elementFontSizes['heading'], heading);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.elementFontSizes, {'heading': heading});
  });
  testWidgets(
    'image note heading and footer adjust separately from wrapped body',
    (tester) async {
      PresentationSlideSettings? draft;
      double renderedBody = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: PresentationSlideEditor(
              settings: const PresentationSlideSettings(fontSizeOverride: 24),
              onSave: (_) async {},
              builder: (settings, report) {
                draft = settings;
                return NoteImageFlow(
                  text: 'A short wrapped note.',
                  formatJson: null,
                  elementItemId: 'image-note',
                  elementFontSizes: settings.elementFontSizes,
                  elementAlignments: settings.elementAlignments,
                  displayedFontSizeOverride: settings.fontSizeOverride,
                  onDisplayedFontSizeResolved: (font) {
                    renderedBody = font;
                    report(font);
                  },
                  layout: const NoteImageLayout(
                    header: 'Image heading',
                    footer: 'Image footer',
                  ),
                  aspectRatio: 4 / 3,
                  image: const ColoredBox(color: Colors.blue),
                  style: const TextStyle(fontSize: 24),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester
          .widget<Text>(find.text('Image heading'))
          .style!
          .fontSize!;
      final footer = tester
          .widget<Text>(find.text('Image footer'))
          .style!
          .fontSize!;
      await tester.longPress(find.text('Image heading'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Larger text'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('Image heading')).style!.fontSize,
        greaterThan(before),
      );
      expect(
        tester.widget<Text>(find.text('Image footer')).style!.fontSize,
        footer,
      );
      expect(renderedBody, closeTo(24, .01));
      await tester.tap(find.byTooltip('Align right')); await tester.pump();
      expect(tester.widget<Text>(find.text('Image heading')).textAlign, TextAlign.right);

      expect(draft!.elementFontSizes.keys, [
        presentationElementKey('image-note', 'header'),
      ]);
      await tester.tap(find.byTooltip('Move controls'));
      await tester.pump();
      await tester.tap(find.text('Image footer'));
      await tester.pump();
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('Image footer')).style!.fontSize,
        lessThan(footer),
      );
      expect(renderedBody, closeTo(24, .01));
    },
  );

  testWidgets(
    'oversized independent heading warns without overflowing the screen',
    (tester) async {
      final slide = PresentationSlide(
        id: 'long',
        settingsKey: 'long',
        slideNumber: 1,
        slideTitle: List.filled(20, 'A long heading').join(' '),
        layoutType: PresentationLayoutType.fullWidth,
        items: [passage('first', 'The body remains available.')],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresentationSlideCanvas(
              slide: slide,
              aspectRatioPreset: PresentationAspectRatioPreset.auto,
              bookNames: const {1: 'Genesis'},
              mediaRootPaths: const [],
              settings: const PresentationSlideSettings(
                fontSizeOverride: 24,
                elementFontSizes: {'slide:title': 160},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Text exceeds the heading'), findsOneWidget);
      expect(find.text('The body remains available.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
