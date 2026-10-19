import 'dart:ui' show loadFontFromList;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/core/theme/app_theme.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/reader/data/topic_picker_service.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_launcher.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_models.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_page_one.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_page_two.dart';
import 'package:studybible2/features/reader/presentation/viewer_strongs_repository.dart';

class _WordRepository extends ViewerStrongsRepository {
  const _WordRepository();

  @override
  Future<ViewerStrongsEntry?> loadEntry(String strongsId) async =>
      const ViewerStrongsEntry(
        strongsId: 'G3641',
        language: 'G',
        lemma: 'ὀλίγος',
        transliteration: 'olígos',
        pronunciation: "ol-ee'-gos",
        partOfSpeech: 'adjective',
        shortDefinition: 'few; little',
      );

  @override
  Future<int> loadOccurrenceCount(String strongsId) async => 42;

  @override
  Future<ViewerAbbottSmithEntry?> loadAbbottSmithEntry(
    String strongsId,
  ) async => null;
}

class _RichWordRepository extends _WordRepository {
  const _RichWordRepository();

  @override
  Future<ViewerAbbottSmithEntry?> loadAbbottSmithEntry(
    String strongsId,
  ) async => const ViewerAbbottSmithEntry(
    senses: [
      ViewerLexiconSense(
        number: '1.',
        parts: [
          ViewerLexiconPart('to serve: '),
          ViewerLexiconPart('Mt 20:28', blockId: 23821),
        ],
      ),
      ViewerLexiconSense(
        number: '2.',
        parts: [ViewerLexiconPart('to serve as deacon')],
      ),
    ],
    related: [],
  );
}

class _SourceNoteRepository extends _WordRepository {
  const _SourceNoteRepository();

  @override
  Future<ViewerStrongsEntry?> loadEntry(String strongsId) async =>
      const ViewerStrongsEntry(
        strongsId: 'G5315',
        language: 'G',
        lemma: 'φάγομαι',
        transliteration: 'phagomai',
        pronunciation: 'fag-om-ahee',
        partOfSpeech: 'verb',
        shortDefinition: 'to eat',
      );

  @override
  Future<ViewerAbbottSmithEntry?> loadAbbottSmithEntry(
    String strongsId,
  ) async => const ViewerAbbottSmithEntry(
    senses: [],
    related: [
      [ViewerLexiconPart('φάγομαι: see ἐσθίω')],
    ],
  );
}

class _HebrewBdbRepository extends ViewerStrongsRepository {
  const _HebrewBdbRepository();

  @override
  Future<ViewerStrongsEntry?> loadEntry(String strongsId) async =>
      const ViewerStrongsEntry(
        strongsId: 'H5982',
        language: 'H',
        lemma: 'עַמּוּד',
        transliteration: 'ammud',
        pronunciation: '',
        partOfSpeech: 'noun',
        shortDefinition: 'pillar',
      );

  @override
  Future<int> loadOccurrenceCount(String strongsId) async => 2;

  @override
  Future<ViewerAbbottSmithEntry?> loadAbbottSmithEntry(
    String strongsId,
  ) async => null;

  @override
  Future<ViewerBdbEntry?> loadBdbEntry(String strongsId) async =>
      ViewerBdbEntry(
        articleId: 'BDB07151',
        text: '[Str5982] עַמּוּד pillar, column; '
            '${'The source discusses columns and their uses in the text. ' * 7}',
      );
}

void main() {
  setUpAll(() async {
    for (final (path, family) in [
      ('assets/fonts/Roboto-Regular.ttf', 'Roboto'),
      ('assets/fonts/Roboto-Bold.ttf', 'Roboto'),
      ('assets/fonts/PlayfairDisplay-Regular.ttf', 'PlayfairDisplay'),
      ('assets/fonts/PlayfairDisplay-Bold.ttf', 'PlayfairDisplay'),
      ('assets/fonts/NotoSerif-Regular.ttf', 'NotoSerif'),
      ('assets/fonts/NotoSerif-Bold.ttf', 'NotoSerif'),
    ]) {
      final data = await rootBundle.load(path);
      await loadFontFromList(data.buffer.asUint8List(), fontFamily: family);
    }
  });

  testWidgets('Hebrew detail retains Strong’s and can expand BDB', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewerStrongsPageOne(
            strongsId: 'H5982',
            onOpenPageTwo: () {},
            repository: const _HebrewBdbRepository(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("Strong's H5982"), findsOneWidget);
    expect(find.text('pillar'), findsOneWidget);
    expect(find.text('Brown-Driver-Briggs'), findsOneWidget);
    expect(find.text('Read full entry'), findsOneWidget);
    await tester.ensureVisible(find.text('Read full entry'));
    await tester.tap(find.text('Read full entry'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('word dialog shows the full entry and retains the Bible route', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          theme: buildAppTheme(AppThemeMode.sepia),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const SizedBox(height: 90),
                  const Text('Hebrews 6:10'),
                  const Text('For God is not unrighteous to forget your work'),
                  const SizedBox(height: 90),
                  FilledButton(
                    onPressed: () => showViewerStrongsPageOne(
                      context,
                      strongsId: 'G3641',
                      mappedPhrase: 'a few',
                      onSelectBlockId: (_) {},
                      repository: const _WordRepository(),
                      occurrenceDataOverride:
                          Future<ViewerStrongsOccurrenceData>.value((
                            rows: const [
                              ViewerStrongsOccurrence(
                                blockId: 100,
                                bookNumber: 58,
                                bookName: 'Hebrews',
                                chapter: 6,
                                verse: 10,
                                html: '<w lemma="strong:G3641">a few</w>',
                                text: 'a few',
                              ),
                            ],
                            books: const [
                              BookRecord(
                                bookNumber: 58,
                                bookName: 'Hebrews',
                                bookIndex: 58,
                              ),
                            ],
                            sections: const [
                              TopicSection(
                                id: 1,
                                name: 'Present section',
                                colorHex: '#A85B4A',
                                minBlockId: 100,
                                maxBlockId: 101,
                              ),
                            ],
                          )),
                    ),
                    child: const Text('Open word'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open word'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Found in 42 verses'), findsOneWidget);
    expect(find.text('Brief definition'), findsOneWidget);
    expect(find.text('Copy entry'), findsOneWidget);
    expect(find.textContaining('Morphology tag:'), findsNothing);
    expect(find.textContaining('page 2'), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Hebrews 6:10'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('goldens/word_panel.png'),
    );
    await tester.tap(find.text('Found in 42 verses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Occurrences by section'), findsOneWidget);
  });

  testWidgets('occurrence results show only occupied colored sections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = Future<ViewerStrongsOccurrenceData>.value((
      rows: const [
        ViewerStrongsOccurrence(
          blockId: 100,
          bookNumber: 58,
          bookName: 'Hebrews',
          chapter: 6,
          verse: 10,
          html: '<w lemma="strong:G3641">a few</w> words',
          text: 'a few words',
        ),
        ViewerStrongsOccurrence(
          blockId: 101,
          bookNumber: 58,
          bookName: 'Hebrews',
          chapter: 6,
          verse: 11,
          html: '<w lemma="strong:G3641">a few</w> more',
          text: 'a few more',
        ),
      ],
      books: const [
        BookRecord(bookNumber: 58, bookName: 'Hebrews', bookIndex: 58),
      ],
      sections: const [
        TopicSection(
          id: 1,
          name: 'Present section',
          colorHex: '#A85B4A',
          minBlockId: 100,
          maxBlockId: 101,
        ),
        TopicSection(
          id: 2,
          name: 'Empty section',
          colorHex: '#2D72BB',
          minBlockId: 500,
          maxBlockId: 600,
        ),
      ],
    ));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          theme: buildAppTheme(AppThemeMode.sepia),
          home: Scaffold(
            body: SizedBox(
              height: 780,
              child: ViewerStrongsPageTwo(
                strongsId: 'G3641',
                onSelectBlockId: (_) {},
                dataOverride: data,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Occurrences by section'), findsOneWidget);
    expect(find.text('Empty section'), findsNothing);
    expect(find.text('Section'), findsNothing);
    expect(find.text('Book'), findsNothing);
    expect(find.text('All verses'), findsNothing);
    expect(find.text('Hebrews 6:10'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('capture')),
      matchesGoldenFile('goldens/occurrences.png'),
    );
    await tester.tap(find.text('Present section'));
    await tester.pump();
    expect(
      find.text('Showing 2 of 2 verses · Present section'),
      findsOneWidget,
    );
    expect(find.text('Books in Present section'), findsOneWidget);
    await tester.tap(find.text('Hebrews'));
    await tester.pump();
    expect(find.text('Showing 2 of 2 verses · Hebrews'), findsOneWidget);
    await tester.tap(find.text('Hebrews'));
    await tester.pump();
    expect(
      find.text('Showing 2 of 2 verses · Present section'),
      findsOneWidget,
    );
    await tester.tap(find.text('Present section'));
    await tester.pump();
    expect(find.text('Showing all 2 verses'), findsOneWidget);
    expect(find.text('Books in Present section'), findsNothing);
  });

  testWidgets('word details remain scrollable with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemeMode.sepia),
        home: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 360,
                  child: ViewerStrongsPageOne(
                    strongsId: 'G3641',
                    mappedPhrase: 'a few',
                    onOpenPageTwo: () {},
                    repository: const _WordRepository(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Copy entry'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching sections clears the prior book filter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = Future<ViewerStrongsOccurrenceData>.value((
      rows: const [
        ViewerStrongsOccurrence(
          blockId: 100,
          bookNumber: 40,
          bookName: 'Matthew',
          chapter: 1,
          verse: 1,
          html: 'first',
          text: 'first',
        ),
        ViewerStrongsOccurrence(
          blockId: 200,
          bookNumber: 45,
          bookName: 'Romans',
          chapter: 1,
          verse: 1,
          html: 'second',
          text: 'second',
        ),
      ],
      books: const [
        BookRecord(bookNumber: 40, bookName: 'Matthew', bookIndex: 40),
        BookRecord(bookNumber: 45, bookName: 'Romans', bookIndex: 45),
      ],
      sections: const [
        TopicSection(
          id: 1,
          name: 'Gospels and Acts',
          colorHex: '#A85B4A',
          minBlockId: 100,
          maxBlockId: 199,
        ),
        TopicSection(
          id: 2,
          name: 'Pauline Letters',
          colorHex: '#2D72BB',
          minBlockId: 200,
          maxBlockId: 299,
        ),
      ],
    ));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewerStrongsPageTwo(
            strongsId: 'G3641',
            onSelectBlockId: (_) {},
            dataOverride: data,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gospels and Acts'));
    await tester.pump();
    await tester.tap(find.text('Matthew'));
    await tester.pump();
    expect(find.text('Showing 1 of 2 verses · Matthew'), findsOneWidget);
    await tester.tap(find.text('Pauline Letters'));
    await tester.pump();
    expect(
      find.text('Showing 1 of 2 verses · Pauline Letters'),
      findsOneWidget,
    );
    expect(find.text('Books in Pauline Letters'), findsOneWidget);
    expect(find.text('Matthew'), findsNothing);
    expect(find.text('Romans 1:1'), findsOneWidget);
  });

  testWidgets('numbered meanings keep their own tappable verse links', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? selectedBlockId;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemeMode.sepia),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showViewerStrongsPageOne(
                context,
                strongsId: 'G1247',
                onSelectBlockId: (_) {},
                onSelectCitation: (blockId, _) => selectedBlockId = blockId,
                repository: const _RichWordRepository(),
              ),
              child: const Text('Open meaning'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open meaning'));
    await tester.pumpAndSettle();
    expect(find.text('Meanings and Scripture examples'), findsOneWidget);
    expect(
      find.textContaining('to serve as deacon', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Abbott-Smith'), findsOneWidget);
    await tester.ensureVisible(find.text('Mt 20:28'));
    await tester.tap(find.text('Mt 20:28'));
    await tester.pump();
    expect(selectedBlockId, 23821);
  });

  testWidgets('source-only Greek note keeps the existing definition', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ViewerStrongsPageOne(
            strongsId: 'G5315',
            onOpenPageTwo: _noop,
            repository: _SourceNoteRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Brief definition'), findsOneWidget);
    expect(find.text('to eat'), findsOneWidget);
    expect(find.text('Abbott-Smith source note'), findsOneWidget);
    expect(
      find.textContaining('see ἐσθίω', findRichText: true),
      findsOneWidget,
    );
  });
}

void _noop() {}
