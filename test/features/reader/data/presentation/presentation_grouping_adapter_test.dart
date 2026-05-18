import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/features/reader/data/presentation/presentation_grouping_adapter.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_models.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

HashTagEntry _entry({
  required int id,
  required int bookNumber,
  required int chapter,
  required int verse,
  required String verseRef,
  required String verseText,
  required int createdAt,
  required int sortOrder,
  int? verseEnd,
  bool isNormalized = false,
  int? presentationSlideNumber,
  PresentationItemPlacement? presentationSlideRegion,
  String? userTitle,
  String? referenceCode,
  String? displayTextOverride,
  String? titleFormatJson,
  String? displayTextFormatJson,
  String? contentHtml,
  String? noteText,
  String? noteFormatJson,
}) {
  return HashTagEntry(
    id: id,
    bookNumber: bookNumber,
    chapter: chapter,
    verse: verse,
    verseEnd: verseEnd ?? verse,
    verseRef: verseRef,
    verseText: verseText,
    createdAt: createdAt,
    sortOrder: sortOrder,
    isNormalized: isNormalized,
    presentationSlideNumber: presentationSlideNumber,
    presentationSlideRegion: presentationSlideRegion,
    userTitle: userTitle,
    referenceCode: referenceCode,
    displayTextOverride: displayTextOverride,
    titleFormatJson: titleFormatJson,
    displayTextFormatJson: displayTextFormatJson,
    contentHtml: contentHtml,
    noteText: noteText,
    noteFormatJson: noteFormatJson,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp;
  pathProviderChannel.setMockMethodCallHandler((call) async {
    switch (call.method) {
      case 'getApplicationSupportDirectory':
      case 'getApplicationDocumentsDirectory':
      case 'getTemporaryDirectory':
      case 'getLibraryDirectory':
        return supportDir.path;
    }
    return supportDir.path;
  });
  tearDownAll(() => pathProviderChannel.setMockMethodCallHandler(null));

  test('adapts current flat rows into read-only presentation slides', () async {
    final entries = [
      _entry(
        id: 22,
        bookNumber: 43,
        chapter: 3,
        verse: 17,
        verseRef: '43:3:17',
        verseText: 'Second verse text',
        createdAt: 200,
        sortOrder: 2,
      ),
      _entry(
        id: 11,
        bookNumber: 43,
        chapter: 3,
        verse: 16,
        verseRef: '43:3:16',
        verseText: 'First verse text',
        createdAt: 100,
        sortOrder: 1,
      ),
    ];

    final adapter = PresentationGroupingAdapter(legacyGroupKey: '#Grace');
    final slides = await adapter.adaptEntries(entries);

    expect(slides, hasLength(2));
    expect(slides.first.slideNumber, 1);
    expect(slides.last.slideNumber, 2);
    expect(slides.first.layoutType, PresentationLayoutType.fullWidth);
    expect(slides.last.layoutType, PresentationLayoutType.fullWidth);
    expect(slides.first.legacyGroupKey, '#Grace');
    expect(slides.last.legacyGroupKey, '#Grace');
    expect(slides.first.items, hasLength(1));
    expect(slides.last.items, hasLength(1));
    expect(
      slides.first.items.single.layoutRegion,
      PresentationLayoutRegion.full,
    );
    expect(
      slides.last.items.single.layoutRegion,
      PresentationLayoutRegion.full,
    );
    expect(slides.first.items.single.displayText, 'Second verse text');
    expect(slides.last.items.single.displayText, 'First verse text');
  });

  test(
    'maps note-only rows to note slides without exposing placeholders',
    () async {
      final entries = [
        _entry(
          id: 31,
          bookNumber: 0,
          chapter: 0,
          verse: 0,
          verseRef: 'note:999999',
          verseText: '',
          createdAt: 300,
          sortOrder: 3,
          noteText: 'Standalone note text',
        ),
      ];

      final slides = await const PresentationGroupingAdapter().adaptEntries(
        entries,
      );

      expect(slides, hasLength(1));
      final slide = slides.single;
      expect(slide.layoutType, PresentationLayoutType.fullWidth);
      expect(slide.items, hasLength(1));
      final item = slide.items.single;
      expect(item.itemKind, PresentationItemKind.note);
      expect(item.layoutRegion, PresentationLayoutRegion.full);
      expect(item.layoutOrder, 0);
      expect(item.displayTitle, 'Note');
      expect(item.displayText, 'Standalone note text');
      expect(item.displayText, isNot(startsWith('note:')));
    },
  );

  test('keeps zeroed eLibrary rows out of Bible verse identities', () async {
    final entries = [
      _entry(
        id: 71,
        bookNumber: 0,
        chapter: 0,
        verse: 0,
        verseRef: 'elibrary:71',
        verseText: '',
        createdAt: 700,
        sortOrder: 1,
        referenceCode: 'p. 14',
        noteText: 'eLibrary quote text',
        noteFormatJson: jsonEncode({
          'kind': 'elibrary_note',
          'source_title': 'Selected Reading',
          'source_location': 'p. 14',
          'stable_ref': 'elibrary:stable-71',
        }),
      ),
    ];

    final slides = await const PresentationGroupingAdapter().adaptEntries(
      entries,
    );

    expect(slides, hasLength(1));
    final slide = slides.single;
    expect(slide.settingsKey, 'elibrary_note:elibrary:stable-71');
    expect(slide.slideTitle, 'Selected Reading — p. 14');
    expect(slide.items, hasLength(1));
    final item = slide.items.single;
    expect(item.itemKind, PresentationItemKind.note);
    expect(item.sourceType, 'elibrary_note');
    expect(item.sourceId, 'elibrary:stable-71');
    expect(item.bookNumber, 0);
    expect(item.chapter, 0);
    expect(item.verse, 0);
    expect(item.displayText, 'eLibrary quote text');
  });

  test('uses the saved reference code for eLibrary titles', () async {
    final entries = [
      _entry(
        id: 72,
        bookNumber: 0,
        chapter: 0,
        verse: 0,
        verseRef: 'elibrary:72',
        verseText: '',
        createdAt: 720,
        sortOrder: 1,
        referenceCode: 'RC 123.5',
        noteText: 'eLibrary quote text',
        noteFormatJson: jsonEncode({
          'kind': 'elibrary_note',
          'source_title': 'Reflecting Christ',
          'source_location': 'RC ¶5',
          'stable_ref': 'elibrary:stable-72',
        }),
      ),
    ];

    final slides = await const PresentationGroupingAdapter().adaptEntries(
      entries,
    );

    expect(slides, hasLength(1));
    final slide = slides.single;
    expect(slide.slideTitle, 'Reflecting Christ — RC 123.5');
    expect(slide.items.single.displayTitle, 'Reflecting Christ — RC 123.5');
  });

  test('drops internal eLibrary paths from fallback titles', () async {
    final entries = [
      _entry(
        id: 73,
        bookNumber: 0,
        chapter: 0,
        verse: 0,
        verseRef: 'elibrary:73',
        verseText: '',
        createdAt: 730,
        sortOrder: 1,
        noteText: 'eLibrary quote text',
        noteFormatJson: jsonEncode({
          'kind': 'elibrary_note',
          'source_title':
              'elibrary:library_item_research_epubs_research_egw_devotionals_en_rc_epub:115:5::OEBPS/content110.xhtml',
          'source_title_acronym': 'RC',
          'source_location':
              'elibrary:library_item_research_epubs_research_egw_devotionals_en_rc_epub:115:5::OEBPS/content110.xhtml',
          'source_paragraph_index': 5,
          'stable_ref': 'elibrary:stable-73',
        }),
      ),
    ];

    final slides = await const PresentationGroupingAdapter().adaptEntries(
      entries,
    );

    expect(slides, hasLength(1));
    final slide = slides.single;
    expect(slide.slideTitle, isNot(contains('elibrary:')));
    expect(slide.slideTitle, isNot(contains('OEBPS/')));
    expect(slide.slideTitle, 'RC ¶5');
    expect(slide.items.single.displayTitle, 'RC ¶5');
  });

  test('keeps verse-attached notes on the verse item', () async {
    final entries = [
      _entry(
        id: 41,
        bookNumber: 43,
        chapter: 3,
        verse: 18,
        verseRef: '43:3:18',
        verseText: 'Verse with a note',
        createdAt: 400,
        sortOrder: 4,
        noteText: 'Attached note text',
      ),
    ];

    final slides = await const PresentationGroupingAdapter().adaptEntries(
      entries,
    );

    expect(slides, hasLength(1));
    final slide = slides.single;
    expect(slide.slideNumber, 1);
    expect(slide.layoutType, PresentationLayoutType.fullWidth);
    expect(slide.items, hasLength(1));

    final verseItem = slide.items.single;
    expect(verseItem.itemKind, PresentationItemKind.verse);
    expect(verseItem.layoutRegion, PresentationLayoutRegion.full);
    expect(verseItem.layoutOrder, 0);
    expect(verseItem.displayText, 'Verse with a note');
    expect(verseItem.noteText, 'Attached note text');
  });

  test(
    'groups rows that share the same slide assignment into one slide',
    () async {
      final entries = [
        _entry(
          id: 51,
          bookNumber: 1,
          chapter: 1,
          verse: 28,
          verseRef: '1:1:28',
          verseText: 'Be fruitful and multiply',
          createdAt: 500,
          sortOrder: 1,
          presentationSlideNumber: 1,
        ),
        _entry(
          id: 52,
          bookNumber: 1,
          chapter: 1,
          verse: 23,
          verseRef: '1:1:23',
          verseText: 'Genesis 1:23 verse text',
          createdAt: 510,
          sortOrder: 2,
          presentationSlideNumber: 1,
        ),
        _entry(
          id: 53,
          bookNumber: 1,
          chapter: 1,
          verse: 30,
          verseRef: '1:1:30',
          verseText: 'Genesis 1:30 verse text',
          createdAt: 520,
          sortOrder: 3,
          presentationSlideNumber: 1,
          noteText: 'Verse-attached note',
        ),
      ];

      final slides = await const PresentationGroupingAdapter().adaptEntries(
        entries,
      );

      expect(slides, hasLength(1));
      final slide = slides.single;
      expect(slide.layoutType, PresentationLayoutType.fullWidth);
      expect(slide.items, hasLength(3));
      expect(slide.items[0].itemKind, PresentationItemKind.verse);
      expect(slide.items[0].layoutRegion, PresentationLayoutRegion.full);
      expect(slide.items[0].displayText, 'Be fruitful and multiply');
      expect(slide.items[0].noteText, isNull);
      expect(slide.items[1].itemKind, PresentationItemKind.verse);
      expect(slide.items[1].layoutRegion, PresentationLayoutRegion.full);
      expect(slide.items[1].displayText, 'Genesis 1:23 verse text');
      expect(slide.items[1].noteText, isNull);
      expect(slide.items[2].itemKind, PresentationItemKind.verse);
      expect(slide.items[2].layoutRegion, PresentationLayoutRegion.full);
      expect(slide.items[2].displayText, 'Genesis 1:30 verse text');
      expect(
        slide.items.any((item) => item.displayText.contains('note:')),
        isFalse,
      );
      expect(slide.items[2].noteText, 'Verse-attached note');
    },
  );

  test('keeps slide title blank in the legacy bridge', () async {
    final entries = [
      _entry(
        id: 61,
        bookNumber: 43,
        chapter: 3,
        verse: 16,
        verseRef: '43:3:16',
        verseText: 'For God so loved the world',
        createdAt: 600,
        sortOrder: 1,
      ),
    ];

    final slides = await const PresentationGroupingAdapter().adaptEntries(
      entries,
    );

    expect(slides, hasLength(1));
    expect(slides.single.slideTitle, 'John 3:16');
  });
}
