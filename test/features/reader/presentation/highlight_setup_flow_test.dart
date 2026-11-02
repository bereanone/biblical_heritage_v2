import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:studybible2/features/reader/data/highlight_groups_repository.dart';
import 'package:studybible2/features/reader/data/highlights_repository.dart';
import 'package:studybible2/features/reader/presentation/markup_settings_screen.dart';
import 'package:studybible2/features/reader/presentation/viewer_markup_applier.dart';
import 'package:studybible2/features/reader/presentation/viewer_passage_models.dart';
import 'package:studybible2/features/reader/presentation/viewer_range_selection.dart';
import 'package:studybible2/features/reader/presentation/viewer_top_bar.dart';
import 'package:studybible2/features/library/presentation/elibrary_highlight_color_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  late Database db;
  late int sun;
  late int blue;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('highlight_setup_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => root.path,
        );
    db = await UserDatabase.instance.database;
    final groups = HighlightGroupsRepository();
    sun = (await groups.createGroup(name: 'Test Sun', colorHex: '#F4DE45')).id;
    blue = (await groups.createGroup(
      name: 'Test Blue',
      colorHex: '#66AEEA',
    )).id;
    await HighlightsRepository().applyHighlight(
      groupId: sun,
      verseRef: 'John 11:35',
    );
  });

  setUp(() async {
    await AppSettingsService.instance.saveDefaultHighlightGroupId(sun);
  });

  tearDownAll(() async {
    await UserDatabase.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Widget reader({
    required bool selected,
    required ValueChanged<bool?> returned,
  }) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            ViewerTopBar(
              bookName: 'John',
              chapter: 11,
              verse: 35,
              fontScale: 1,
              baseBibleFontSize: 16,
              onSearch: () {},
              onPaintSelection: selected ? () {} : null,
              onColorSetup: () async => returned(
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) =>
                        MarkupSettingsScreen(canApplyHighlight: selected),
                  ),
                ),
              ),
              highlightColor: Colors.amber,
              highlightName: 'Sun',
              onSavedPresentations: () {},
              onStandardTag: () {},
              onDollarTag: () {},
              onRapidTag: () {},
              activeFamily: null,
              onTopics: () {},
              onChoosePassage: () {},
            ),
            const Expanded(child: Text('Selected text')),
          ],
        ),
      ),
    ),
  );

  testWidgets(
    'sample opens setup; help and backing out do not alter saved highlights',
    (tester) async {
      final before = await tester.runAsync(() => db.query('highlights'));
      bool? result;
      await tester.pumpWidget(
        reader(selected: true, returned: (value) => result = value),
      );
      await tester.tap(find.byKey(const ValueKey('viewer-highlight-color')));
      await settle(tester);
      expect(find.text('Color Setup'), findsOneWidget);
      expect(find.text('Apply Highlight'), findsOneWidget);
      expect(find.textContaining('Press and hold a word'), findsNothing);
      await tester.tap(find.byTooltip('Highlighting help'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Tap Paint (the paintbrush button)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(await tester.runAsync(() => db.query('highlights')), before);
    },
  );

  testWidgets(
    'setup applies chosen group through existing range applier and preserves other highlights',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        reader(selected: true, returned: (value) => result = value),
      );
      await tester.tap(find.byKey(const ValueKey('viewer-highlight-color')));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Test Blue'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final chooseBlue = find.byTooltip('Use as default highlight color').last;
      await tester.ensureVisible(chooseBlue);
      await tester.tap(chooseBlue);
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('setup-apply-highlight')).hitTestable(),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('setup-apply-highlight')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      await tester.runAsync(() async {
        final chosen = await AppSettingsService.instance
            .loadDefaultHighlightGroupId();
        expect(chosen, blue);
        final applied = await applyDefaultMarkup(
          groupId: chosen!,
          rangeSelection: const ViewerRangeSelection(
            startBlockId: 1,
            endBlockId: 1,
          ),
          passage: const PassageData(
            bookNumber: 43,
            bookName: 'John',
            chapter: 11,
            lines: [
              VerseLine(
                blockId: 1,
                bookNumber: 43,
                chapter: 11,
                verse: 36,
                html: '',
                text: 'Then said the Jews',
              ),
            ],
          ),
          isLineInRange: (_) => true,
          buildTokenSelections: (_) => [],
        );
        expect(applied, isTrue);
        expect(
          (await db.query(
            'highlights',
            where: 'verse_ref = ?',
            whereArgs: ['John 11:36'],
          )).single['group_id'],
          blue,
        );
        expect(
          (await db.query(
            'highlights',
            where: 'verse_ref = ?',
            whereArgs: ['John 11:35'],
          )).single['group_id'],
          sun,
        );
      });
    },
  );

  testWidgets(
    'setup without selection explains disabled paint; short screen scrolls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(568, 320);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: MarkupSettingsScreen()));
      await settle(tester);
      final apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply Highlight'),
      );
      expect(apply.onPressed, isNull);
      expect(
        find.text('Select text in the Bible first, then tap Paint.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Test Blue'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Test Blue').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'eLibrary has paintbrush apply and help; cancel returns no color',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      String? result = 'unchanged';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await showElibraryHighlightColorPicker(context),
                child: const Text('Highlight selection'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Highlight selection'));
      await settle(tester);
      await tester.tap(find.byTooltip('Highlighting help'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Choosing a color sample alone'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('Highlight selection'));
      await settle(tester);
      await tester.tap(find.text('Apply Highlight'));
      await tester.pumpAndSettle();
      expect(result, startsWith('#'));
      expect(tester.takeException(), isNull);
    },
  );
}
