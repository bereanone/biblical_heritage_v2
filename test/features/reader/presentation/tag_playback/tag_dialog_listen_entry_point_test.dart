import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/tag_dialog_hash_tab.dart';
import 'package:studybible2/features/reader/presentation/tag_dialog_models.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

Widget tab(
  List<HashTagSummary> summaries,
  ValueChanged<HashTagSummary> onOpen,
) {
  return MaterialApp(
    home: Scaffold(
      body: TagDialogHashTab(
        tagSymbol: '#',
        fontScale: 1,
        loading: false,
        groupedSummaries: [
          MapEntry<String?, List<HashTagSummary>>(null, summaries),
        ],
        searchSummaries: summaries,
        tagController: TextEditingController(),
        categoryController: TextEditingController(),
        searchController: TextEditingController(),
        selectedCategory: null,
        categoryOptions: const [],
        categoryFilter: null,
        sortMode: TagSortMode.categoryAlpha,
        working: false,
        onTagSubmitted: (_) async {},
        onApplySelection: () {},
        onCategoryChanged: (_) {},
        onToggleSelectedCategoryBrowseFilter: () {},
        onResetBrowseState: () {},
        onSearchSelected: (_) async {},
        onSortModeChanged: (_) {},
        onOpenSummaryDetails: onOpen,
      ),
    ),
  );
}

void main() {
  testWidgets('every tag row offers Listen next to Open verses', (
    tester,
  ) async {
    await tester.pumpWidget(
      tab(const [
        HashTagSummary(tag: '#faith', count: 3),
        HashTagSummary(tag: '#hope', count: 0),
      ], (_) {}),
    );
    expect(find.byTooltip('Listen to this tag'), findsNWidgets(2));
    expect(find.byTooltip('Open verses'), findsNWidgets(2));
  });

  testWidgets('an empty tag cannot be played; a populated one can', (
    tester,
  ) async {
    await tester.pumpWidget(
      tab(const [
        HashTagSummary(tag: '#faith', count: 3),
        HashTagSummary(tag: '#hope', count: 0),
      ], (_) {}),
    );
    final buttons = tester
        .widgetList<IconButton>(
          find.ancestor(
            of: find.byIcon(Icons.headphones_rounded),
            matching: find.byType(IconButton),
          ),
        )
        .toList();
    expect(buttons.map((b) => b.onPressed != null), [true, false]);
  });

  testWidgets('Open verses still opens the detail view', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      tab(const [
        HashTagSummary(tag: '#faith', count: 3),
      ], (s) => opened.add(s.tag)),
    );
    await tester.tap(find.byTooltip('Open verses'));
    expect(opened, ['#faith']);
  });
}
