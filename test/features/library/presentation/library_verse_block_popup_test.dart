import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/library/presentation/library_verse_popup.dart';
import 'package:studybible2/features/reader/presentation/viewer_markup_span_builder.dart';

String displayed(LibraryPopupVerse verse) => verse
    .buildSpan(baseStyle: const TextStyle(), redLetterColor: Colors.red)
    .toPlainText();

Iterable<TextSpan> spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* spans(child);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('bible-block-popup-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
  });
  tearDownAll(() async {
    await (await StudyBibleDatabase.instance.bible).close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test('real Psalm blocks retain opening He and all verse content', () async {
    final verses = await loadLibraryPopupVerses('Psalm 104:13-15');
    expect(verses.map((v) => v.target.verse), [13, 14, 15]);
    expect(displayed(verses[0]), startsWith('He watereth'));
    expect(
      displayed(verses[1]),
      'He causeth the grass to grow for the cattle, and herb for the service '
      'of man: that he may bring forth food out of the earth;',
    );
    final db = await StudyBibleDatabase.instance.bible;
    for (final verse in verses) {
      final row = (await db.query(
        'bible_blocks',
        where: 'id = ?',
        whereArgs: [verse.blockId],
      )).single;
      expect(verse.html, row['html']);
      final reader = buildViewerMarkupSpan(
        html: row['html']! as String,
        fallbackText: '',
        baseStyle: const TextStyle(),
        redLetterColor: Colors.red,
        startsInRedLetter: verse.startsInRedLetter,
      );
      expect(displayed(verse), reader.toPlainText());
    }
    final badCopy = (await db.query(
      'bible_blocks',
      columns: ['plain_text'],
      where: 'id = ?',
      whereArgs: [verses[1].blockId],
    )).single['plain_text'];
    expect(badCopy, startsWith('causeth'));
    expect(displayed(verses[1]), isNot(badCopy));
    final addedWords =
        spans(
              verses[2].buildSpan(
                baseStyle: const TextStyle(),
                redLetterColor: Colors.red,
              ),
            )
            .where((s) => s.style?.fontStyle == FontStyle.italic)
            .map((s) => s.text)
            .join();
    expect(addedWords, contains('that'));
    expect(displayed(verses[2]), isNot(contains('Heb.')));
  });

  test('grouped blocks keep gaps, order, and speech context', () async {
    final verses = await loadLibraryPopupVerses('John 3:3,5; Psalm 104:14');
    expect(
      verses.map(
        (v) => '${v.target.book}:${v.target.chapter}:${v.target.verse}',
      ),
      ['43:3:3', '43:3:5', '19:104:14'],
    );
    final red = spans(
      verses.first.buildSpan(
        baseStyle: const TextStyle(),
        redLetterColor: Colors.red,
      ),
    ).where((s) => s.style?.color == Colors.red).map((s) => s.text).join();
    expect(red, contains('Verily'));
    final inherited = (await loadLibraryPopupVerses('John 3:16')).single;
    expect(inherited.startsInRedLetter, isTrue);
    expect(
      spans(
        inherited.buildSpan(
          baseStyle: const TextStyle(),
          redLetterColor: Colors.red,
        ),
      ).where((s) => s.style?.color == Colors.red).map((s) => s.text).join(),
      contains('God so loved the world'),
    );
    expect(
      () => loadLibraryPopupVerses('Psalm 104:14,999'),
      throwsFormatException,
    );
  });

  testWidgets('popup visibly renders the complete stored verse block', (
    tester,
  ) async {
    final verses = (await tester.runAsync(
      () => loadLibraryPopupVerses('Psalm 104:14'),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryVersePopup(
            citation: 'Psalm 104:14',
            loader: (_) async => verses,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(
      text.textSpan!.toPlainText(),
      'Psalms 104:14\n${displayed(verses.single)}',
    );
    expect(text.textSpan!.toPlainText(), contains('\nHe causeth'));
    expect(tester.takeException(), isNull);
  });
}
