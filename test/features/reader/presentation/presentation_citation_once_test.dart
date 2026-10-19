import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_models.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_slide_settings.dart';
import 'package:studybible2/features/reader/presentation/presentation_slide_canvas.dart';
import 'package:studybible2/features/reader/presentation/viewer_presentation_settings.dart';

void main() {
  for (final title in ['Exodus 20:8-11', 'The Sabbath']) {
    testWidgets('citation appears once with title $title', (tester) async {
      final item = PresentationSlideItem(id: 'item', presentationSlideId: 'slide', sourceType: 'bible', sourceId: '1', bookNumber: 2, chapter: 20, verse: 8, verseEnd: 11, layoutRegion: PresentationLayoutRegion.full, layoutOrder: 0, itemKind: PresentationItemKind.verse, displayTitle: '', displayText: 'Remember the sabbath day, to keep it holy.', citationText: 'Exodus 20:8-11');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PresentationSlideCanvas(slide: PresentationSlide(id: 'slide', settingsKey: 'slide', slideNumber: 1, layoutType: PresentationLayoutType.fullWidth, slideTitle: title, items: [item]), aspectRatioPreset: PresentationAspectRatioPreset.auto, bookNames: const {2: 'Exodus'}, settings: const PresentationSlideSettings(), mediaRootPaths: const []))));
      expect(find.text('Exodus 20:8-11'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
