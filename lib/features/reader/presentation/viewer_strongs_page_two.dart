import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import '../data/topic_picker_service.dart';
import 'viewer_markup_span_builder.dart';
import 'viewer_strongs_models.dart';
import 'viewer_strongs_repository.dart';
import 'viewer_topic_picker_widgets.dart';

typedef ViewerStrongsOccurrenceData = ({
  List<ViewerStrongsOccurrence> rows,
  List<BookRecord> books,
  List<TopicSection> sections,
});

class ViewerStrongsOccurrenceViewState {
  const ViewerStrongsOccurrenceViewState({
    this.section = 'All',
    this.bookNumber,
    this.scrollOffset = 0,
  });

  final String section;
  final int? bookNumber;
  final double scrollOffset;
}

class ViewerStrongsPageTwo extends StatefulWidget {
  const ViewerStrongsPageTwo({
    super.key,
    required this.strongsId,
    required this.onSelectBlockId,
    this.onSelectOccurrence,
    this.initialViewState = const ViewerStrongsOccurrenceViewState(),
    this.repository = const ViewerStrongsRepository(),
    this.dataOverride,
  });

  final String strongsId;
  final ValueChanged<int> onSelectBlockId;
  final void Function(int blockId, ViewerStrongsOccurrenceViewState viewState)?
  onSelectOccurrence;
  final ViewerStrongsOccurrenceViewState initialViewState;
  final ViewerStrongsRepository repository;
  final Future<ViewerStrongsOccurrenceData>? dataOverride;

  @override
  State<ViewerStrongsPageTwo> createState() => _ViewerStrongsPageTwoState();
}

class _ViewerStrongsPageTwoState extends State<ViewerStrongsPageTwo> {
  late String _selectedSection = widget.initialViewState.section;
  late int? _selectedBookNumber = widget.initialViewState.bookNumber;
  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: widget.initialViewState.scrollOffset,
  );
  late Future<
    ({
      List<ViewerStrongsOccurrence> rows,
      List<BookRecord> books,
      List<TopicSection> sections,
    })
  >
  _data;

  @override
  void initState() {
    super.initState();
    _data = widget.dataOverride ?? _loadData(widget.strongsId);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canonical =
        normalizeStrongsCanonical(widget.strongsId) ?? widget.strongsId.trim();
    return FutureBuilder<
      ({
        List<ViewerStrongsOccurrence> rows,
        List<BookRecord> books,
        List<TopicSection> sections,
      })
    >(
      future: _data,
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final rows = snapshot.data?.rows ?? const <ViewerStrongsOccurrence>[];
        final books = snapshot.data?.books ?? const <BookRecord>[];
        final sections = snapshot.data?.sections ?? const <TopicSection>[];
        final selectedSection = sections
            .where((section) => section.name == _selectedSection)
            .firstOrNull;
        final selectedBook = books
            .where((book) => book.bookNumber == _selectedBookNumber)
            .firstOrNull;
        final sectionItems = sections
            .map((section) {
              final hex = section.colorHex.replaceFirst('#', '');
              final color = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
                  ? Color(int.parse('FF$hex', radix: 16))
                  : theme.colorScheme.primary;
              return ViewerTopicGraphItem(
                id: section.id,
                label: section.name,
                count: rows
                    .where(
                      (row) =>
                          row.blockId >= section.minBlockId &&
                          row.blockId <= section.maxBlockId,
                    )
                    .length,
                color: color,
              );
            })
            .where((item) => item.count > 0)
            .toList(growable: false);
        final sectionRows = selectedSection == null
            ? rows
            : rows
                  .where(
                    (row) =>
                        row.blockId >= selectedSection.minBlockId &&
                        row.blockId <= selectedSection.maxBlockId,
                  )
                  .toList(growable: false);
        final bookCounts = <int, int>{};
        if (selectedSection != null) {
          for (final row in sectionRows) {
            bookCounts.update(
              row.bookNumber,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }
        }
        final selectedSectionColor = sectionItems
            .where((item) => item.id == selectedSection?.id)
            .firstOrNull
            ?.color;
        final bookItems = books
            .where((book) => bookCounts.containsKey(book.bookNumber))
            .map(
              (book) => ViewerTopicGraphItem(
                id: book.bookNumber,
                label: book.bookName,
                count: bookCounts[book.bookNumber]!,
                color: selectedSectionColor ?? theme.colorScheme.primary,
              ),
            )
            .toList(growable: false);
        final filteredRows = _selectedBookNumber == null
            ? sectionRows
            : sectionRows
                  .where((row) => row.bookNumber == _selectedBookNumber)
                  .toList(growable: false);

        final headerWidgets = <Widget>[
          Row(
            children: [
              Expanded(
                child: Text(
                  "Strong's $canonical",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            selectedSection == null
                ? 'Showing all ${rows.length} verses'
                : 'Showing ${filteredRows.length} of ${rows.length} verses'
                      ' · ${selectedBook?.bookName ?? selectedSection.name}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (rows.isNotEmpty && sectionItems.isNotEmpty) ...[
            Text('Occurrences by section', style: theme.textTheme.titleSmall),
            ViewerTopicGraphPanel(
              items: sectionItems,
              selectedItemId: selectedSection?.id,
              onTap: (id) {
                final index = sections.indexWhere(
                  (section) => section.id == id,
                );
                if (index < 0) return;
                setState(() {
                  _selectedSection = _selectedSection == sections[index].name
                      ? 'All'
                      : sections[index].name;
                  _selectedBookNumber = null;
                });
              },
              fontScale: 1,
              customRowHeight: 28,
              customFontSize: 13,
            ),
            if (selectedSection != null && bookItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Books in ${selectedSection.name}',
                style: theme.textTheme.titleSmall,
              ),
              ViewerTopicGraphPanel(
                items: bookItems,
                selectedItemId: _selectedBookNumber,
                onTap: (bookNumber) => setState(() {
                  _selectedBookNumber = _selectedBookNumber == bookNumber
                      ? null
                      : bookNumber;
                }),
                fontScale: 1,
                customRowHeight: 28,
                customFontSize: 13,
              ),
            ],
            const SizedBox(height: 12),
          ],
          if (snapshot.connectionState != ConnectionState.done)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (snapshot.connectionState == ConnectionState.done && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('No verses found.', style: theme.textTheme.bodyLarge),
            ),
          if (snapshot.connectionState == ConnectionState.done &&
              rows.isNotEmpty &&
              filteredRows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'No verses match the selected filters.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
        ];

        return Material(
          color: theme.colorScheme.surface,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: headerWidgets.length + filteredRows.length,
            itemBuilder: (context, index) {
              if (index < headerWidgets.length) return headerWidgets[index];
              final row = filteredRows[index - headerWidgets.length];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  row.reference,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text.rich(
                  buildViewerMarkupSpan(
                    html: row.html,
                    fallbackText: row.text,
                    baseStyle: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    redLetterColor: theme.colorScheme.error,
                    isNightMode: theme.brightness == Brightness.dark,
                    highlightedStrongs: {canonical},
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final viewState = ViewerStrongsOccurrenceViewState(
                    section: _selectedSection,
                    bookNumber: _selectedBookNumber,
                    scrollOffset: _scrollController.hasClients
                        ? _scrollController.offset
                        : 0,
                  );
                  Navigator.of(context).pop();
                  final contextual = widget.onSelectOccurrence;
                  if (contextual != null) {
                    contextual(row.blockId, viewState);
                  } else {
                    widget.onSelectBlockId(row.blockId);
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<
    ({
      List<ViewerStrongsOccurrence> rows,
      List<BookRecord> books,
      List<TopicSection> sections,
    })
  >
  _loadData(String canonical) async {
    final results = await Future.wait([
      widget.repository.loadOccurrences(canonical),
      StudyBibleDatabase.instance.loadBooks(),
      _loadSections(),
    ]);
    return (
      rows: results[0] as List<ViewerStrongsOccurrence>,
      books: results[1] as List<BookRecord>,
      sections: results[2] as List<TopicSection>,
    );
  }

  Future<List<TopicSection>> _loadSections() async {
    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.rawQuery('''
      SELECT section_id, section_name, color_hex, min_block_id, max_block_id
      FROM bible_sections ORDER BY section_id
    ''');
    return [
      for (final row in rows)
        TopicSection(
          id: (row['section_id'] as num).toInt(),
          name: row['section_name']?.toString() ?? '',
          colorHex: row['color_hex']?.toString() ?? '',
          minBlockId: (row['min_block_id'] as num).toInt(),
          maxBlockId: (row['max_block_id'] as num).toInt(),
        ),
    ];
  }
}
