import 'package:studybible2/features/reader/data/presentation/note_image_layout.dart';
import 'package:studybible2/features/reader/presentation/note_image_flow.dart';
import 'package:studybible2/features/reader/presentation/presentation_image_element.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_slide_settings.dart';
import 'package:studybible2/features/reader/presentation/presentation_slide_editor.dart';

void main() {
  testWidgets('image margin and snapped drag support undo cancel save and reopen', (tester) async {
    const original = NoteImageLayout(rows: 4, columns: 4, row: 0, column: 2, rowSpan: 1, columnSpan: 1);
    var saved = const PresentationSlideSettings();
    PresentationSlideSettings? draft;
    Widget app(String id) => MaterialApp(home: Scaffold(body: PresentationSlideEditor(
      key: ValueKey(id), settings: saved, onSave: (value) async => saved = value,
      builder: (value, _) { draft = value; return NoteImageFlow(text: 'Some words next to the image.',
        formatJson: null, elementItemId: 'one', style: const TextStyle(fontSize: 24),
        layout: value.imageLayouts['item:one:image'] ?? original,
        image: const ColoredBox(color: Colors.blue)); },
    )));
    await tester.pumpWidget(app('start')); await tester.pumpAndSettle();
    await tester.longPress(find.byType(PresentationImageElement)); await tester.pumpAndSettle();
    expect(find.byTooltip('More image margin'), findsOneWidget);
    expect(find.byTooltip('Align left'), findsNothing);
    await tester.tap(find.byTooltip('More image margin')); await tester.pumpAndSettle();
    expect(draft!.imageLayouts['item:one:image']!.textGap, 18);
    await tester.drag(find.byType(PresentationImageElement), const Offset(-220, 0)); await tester.pumpAndSettle();
    expect(draft!.imageLayouts['item:one:image']!.column, lessThan(2));
    await tester.tap(find.text('Undo')); await tester.pumpAndSettle();
    expect(draft!.imageLayouts, isEmpty);
    await tester.tap(find.byTooltip('More image margin')); await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(saved.imageLayouts, isEmpty);
    await tester.longPress(find.byType(PresentationImageElement)); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More image margin')); await tester.pumpAndSettle();
    await tester.drag(find.byType(PresentationImageElement), const Offset(-220, 0)); await tester.pumpAndSettle();
    await tester.tap(find.text('Save')); await tester.pumpAndSettle();
    await tester.pumpWidget(app('reopened')); await tester.pumpAndSettle();
    final flow = tester.widget<NoteImageFlow>(find.byType(NoteImageFlow));
    expect(flow.layout.textGap, 18);
    expect(flow.layout.column, lessThan(2));
    expect(saved.elementFontSizes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'draft, undo, cancel and saved reopening keep per-slide changes explicit',
    (tester) async {
      var saved = PresentationSlideSettings.defaults();
      var writes = 0;
      Widget app(String key) => MaterialApp(
        home: Scaffold(
          body: PresentationSlideEditor(
            key: ValueKey(key),
            settings: saved,
            onSave: (value) async {
              saved = value;
              writes++;
            },
            builder: (settings, report) {
              report(settings.fontSizeOverride ?? 30);
              return Center(
                child: Text('Body ${settings.fontSizeOverride ?? 30}'),
              );
            },
          ),
        ),
      );
      await tester.pumpWidget(app('first'));
      await tester.longPress(find.text('Body 30.0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.pump();
      expect(find.text('Body 30.0'), findsNothing);
      expect(writes, 0);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(find.text('Body 30.0'), findsOneWidget);
      await tester.tap(find.byTooltip('Larger text'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.text('Body 30.0'), findsOneWidget);
      expect(writes, 0);
      await tester.longPress(find.text('Body 30.0'));
      await tester.pump();
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(saved.fontSizeOverride, lessThan(30));
      await tester.pumpWidget(app('reopened'));
      await tester.pump();
      expect(find.text('Body ${saved.fontSizeOverride}'), findsOneWidget);
      await tester.longPress(find.text('Body ${saved.fontSizeOverride}'));
      await tester.pump();
      await tester.tap(find.text('Fit'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved.fontSizeOverride, isNull);
      expect(saved.autoFitEnabled, true);
    },
  );

  testWidgets(
    'two-finger pinch reflows font size only after entering edit mode',
    (tester) async {
      PresentationSlideSettings? draft;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresentationSlideEditor(
              settings: PresentationSlideSettings.defaults(),
              onSave: (_) async {},
              builder: (settings, report) {
                draft = settings;
                report(settings.fontSizeOverride ?? 30);
                return const ColoredBox(color: Colors.black);
              },
            ),
          ),
        ),
      );
      expect(draft!.fontSizeOverride, isNull);
      await tester.longPressAt(const Offset(400, 300));
      await tester.pump();
      final one = await tester.startGesture(const Offset(250, 300), pointer: 1);
      final two = await tester.startGesture(const Offset(550, 300), pointer: 2);
      await tester.pump();
      await one.moveTo(const Offset(300, 300));
      await tester.pump();
      await two.moveTo(const Offset(500, 300));
      await tester.pump();
      await one.up();
      await two.up();
      await tester.pump();
      expect(draft!.fontSizeOverride, isNotNull);
      expect(draft!.fontSizeOverride!, lessThan(30));
    },
  );

  testWidgets('failed save retains draft and does not leave edit mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PresentationSlideEditor(
            settings: PresentationSlideSettings.defaults(),
            onSave: (_) async => throw Exception('test'),
            builder: (settings, report) {
              report(30);
              return const Center(child: Text('Body'));
            },
          ),
        ),
      ),
    );
    await tester.longPress(find.text('Body'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    expect(find.textContaining('Could not save.'), findsOneWidget);
  });
  testWidgets('desktop uses compact size buttons with no slider', (
    tester,
  ) async {
    PresentationSlideSettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: PresentationSlideEditor(
            settings: PresentationSlideSettings.defaults(),
            onSave: (value) async => saved = value,
            builder: (settings, report) {
              report(settings.fontSizeOverride ?? 30);
              return const Center(child: Text('Slide'));
            },
          ),
        ),
      ),
    );
    expect(find.byType(Slider), findsNothing);
    await tester.longPress(find.text('Slide'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.fontSizeOverride, greaterThan(30));
    expect(find.byType(Slider), findsNothing);
    await tester.longPress(find.text('Slide'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
  });
}
