import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/highlights_repository.dart';
import 'package:studybible2/features/reader/presentation/viewer_markup_span_builder.dart';
import 'package:studybible2/features/reader/presentation/viewer_range_selection.dart';
import 'package:studybible2/core/database/user_v2_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  List<ViewerMarkupSegment> parse(String html) => parseViewerMarkupSegments(
    html: html,
    fallbackText: '',
    baseStyle: const TextStyle(),
    redLetterColor: Colors.red,
    splitWords: true,
  );

  test(
    'each English word has its own coordinate while source links stay grouped',
    () {
      final segments = parse(
        '<w lemma="strong:H7162">horns that were</w> <w>in</w>',
      );
      final words = segments.where((s) => s.wordIndex != null).toList();
      expect(words.map((s) => s.text), ['horns', 'that', 'were', 'in']);
      expect(words.map((s) => s.wordIndex), [1, 2, 3, 4]);
      expect(words.map((s) => s.tokenIndex), [1, 1, 1, 2]);
      expect(words.take(3).every((s) => s.strongs!.contains('H7162')), isTrue);
      var selection = const ViewerRangeSelection()
          .beginTokenRange(20, 1, wordIndices: true)
          .completeTokenRange(20, 3);
      selection = selection.moveEndpoint(
        start: false,
        blockId: 20,
        tokenIndex: 1,
      );
      expect(selection.isSingleToken, isTrue);
      expect(selection.usesWordIndices, isTrue);
      expect(selection.containsTokenPosition(20, 2), isFalse);
    },
  );

  test(
    'style boundaries inside one word do not introduce extra word coordinates',
    () {
      final segments = parse('<w>hor<i>ns</i> that were</w>');
      expect(segments.map((s) => s.text).join(), 'horns that were');
      expect(
        segments
            .where((s) => s.text == 'hor' || s.text == 'ns')
            .map((s) => s.wordIndex),
        [1, 1],
      );
    },
  );

  test(
    'long press and saved highlight can target horns alone in a source phrase',
    () {
      final selected = <int>[];
      InlineSpan build(List<VerseHighlightRecord> records) =>
          buildViewerMarkupSpan(
            html: '<w>horns that were</w>',
            fallbackText: '',
            baseStyle: const TextStyle(color: Colors.black),
            redLetterColor: Colors.red,
            blockId: 20,
            wordSelection: true,
            persistedHighlights: records,
            onTokenLongPress: selected.add,
          );
      final root = build(const []) as TextSpan;
      final horns = root.children!.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'horns',
      );
      (horns.recognizer as LongPressGestureRecognizer).onLongPress!();
      expect(selected, [1]);
      final saved =
          build(const [
                VerseHighlightRecord(
                  id: 1,
                  groupId: 1,
                  verseRef: 'Daniel 7:20',
                  colorHex: '#FFE34D',
                  startToken: 1,
                  endToken: 1,
                  startWord: 1,
                  endWord: 1,
                ),
              ])
              as TextSpan;
      final painted = saved.children!
          .whereType<TextSpan>()
          .where((s) => s.style?.backgroundColor != null)
          .map((s) => s.text)
          .join();
      expect(painted, 'horns');
      final legacy =
          build(const [
                VerseHighlightRecord(
                  id: 1,
                  groupId: 1,
                  verseRef: 'Daniel 7:20',
                  colorHex: '#FFE34D',
                  startToken: 1,
                  endToken: 1,
                ),
              ])
              as TextSpan;
      expect(
        legacy.children!
            .whereType<TextSpan>()
            .where((s) => s.style?.backgroundColor != null)
            .map((s) => s.text!.trim())
            .where((s) => s.isNotEmpty),
        ['horns', 'that', 'were'],
      );
    },
  );

  for (final night in [false, true]) {
    for (final precise in [false, true]) {
      test('continuous saved highlight paints only interior spaces night=$night precise=$precise', () {
        final span = buildViewerMarkupSpan(
          html: '<w>before</w> <w>horns that were</w> <w>after</w>', fallbackText: '',
          baseStyle: const TextStyle(color: Colors.white), redLetterColor: Colors.red,
          wordSelection: true, isNightMode: night,
          persistedHighlights: [VerseHighlightRecord(id: 1, groupId: 1, verseRef: 'Daniel 7:20',
            colorHex: '#3278A5', startToken: 2, endToken: 2,
            startWord: precise ? 2 : null, endWord: precise ? 4 : null)],
        ) as TextSpan;
        final children = span.children!.whereType<TextSpan>().toList();
        expect(children.where((s) => s.style?.backgroundColor != null).map((s) => s.text).join(), 'horns that were');
        expect(children.map((s) => s.text).join(), 'before horns that were after');
      });
    }
    test('temporary selection includes interior spaces night=$night', () {
      final span = buildViewerMarkupSpan(
        html: '<w>before horns that were after</w>', fallbackText: '',
        baseStyle: const TextStyle(color: Colors.white), redLetterColor: Colors.red,
        wordSelection: true, isNightMode: night, blockId: 20,
        rangeSelection: const ViewerRangeSelection(startBlockId: 20, endBlockId: 20,
          startTokenIndex: 2, endTokenIndex: 4, usesWordIndices: true),
      ) as TextSpan;
      expect(span.children!.whereType<TextSpan>().where((s) => s.style?.backgroundColor != null).map((s) => s.text).join(), 'horns that were');
    });
  }

  test(
    'precision columns preserve legacy saved ranges and migration is repeatable',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        await UserV2Schema.ensure(db, deviceId: 'selection-test');
        await db.insert('highlights', {
          'group_id': 1,
          'verse_ref': 'Daniel 7:20',
          'start_token': 3,
          'end_token': 3,
        });
        await UserV2Schema.ensure(db, deviceId: 'selection-test');
        final row = (await db.query('highlights')).single;
        expect(row['start_token'], 3);
        expect(row['end_token'], 3);
        expect(row['start_word'], isNull);
        await db.update('highlights', {'start_word': 5, 'end_word': 5});
        expect((await db.query('highlights')).single['end_word'], 5);
      } finally {
        await db.close();
      }
    },
  );
}
