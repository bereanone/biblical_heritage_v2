import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/pronunciation_editor.dart';

void main() {
  testWidgets('preview uses draft and Save commits edited rule', (
    tester,
  ) async {
    Map<String, String>? saved;
    Map<String, String>? preview;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => PronunciationEditor(
                initial: const {'hast': 'hasst'},
                onPreview: (text, rules) async {
                  preview = rules;
                },
                onSave: (rules) async {
                  saved = rules;
                },
                onStopPreview: () async {},
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hast'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'hast-short');
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(preview, {'hast': 'hast-short'});
    expect(saved, isNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, {'hast': 'hast-short'});
    expect(find.byType(PronunciationEditor), findsNothing);
  });
  testWidgets('Cancel does not save removals', (tester) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => PronunciationEditor(
                initial: const {'hast': 'hasst'},
                onPreview: (_, _) async {},
                onSave: (_) async {
                  saved = true;
                },
                onStopPreview: () async {},
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove hast'));
    await tester.pump();
    expect(find.text('hast'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
  });
}
