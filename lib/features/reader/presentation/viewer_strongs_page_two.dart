import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import 'viewer_search_options.dart';
import 'viewer_search_query.dart';
import 'viewer_strongs_models.dart';
import 'viewer_strongs_repository.dart';

class ViewerStrongsPageTwo extends StatefulWidget {
  const ViewerStrongsPageTwo({
    super.key,
    required this.strongsId,
    required this.onSelectBlockId,
    this.repository = const ViewerStrongsRepository(),
  });

  final String strongsId;
  final ValueChanged<int> onSelectBlockId;
  final ViewerStrongsRepository repository;

  @override
  State<ViewerStrongsPageTwo> createState() => _ViewerStrongsPageTwoState();
}

class _ViewerStrongsPageTwoState extends State<ViewerStrongsPageTwo> {
  String _selectedSection = 'All';
  int? _selectedBookNumber;

  @override
  Widget build(BuildContext context) {
    final canonical =
        normalizeStrongsCanonical(widget.strongsId) ?? widget.strongsId.trim();
    return FutureBuilder<({List<ViewerStrongsOccurrence> rows, List<BookRecord> books})>(
      future: _loadData(canonical),
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final rows =
            snapshot.data?.rows ?? const <ViewerStrongsOccurrence>[];
        final books = snapshot.data?.books ?? const <BookRecord>[];
        final bookOptions = buildViewerSearchBookOptions(
          books,
          _selectedSection,
        );
        final filteredRows = rows.where(_matchesFilters).toList(growable: false);

        return Material(
          color: theme.colorScheme.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
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
                'Showing ${filteredRows.length} of ${rows.length} verses',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.done &&
                  rows.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedSection,
                        decoration: const InputDecoration(
                          labelText: 'Section',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: viewerSearchSectionOptions
                            .map(
                              (option) => DropdownMenuItem<String>(
                                value: option.value,
                                child: Text(option.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedSection = value;
                            _selectedBookNumber = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _selectedBookNumber,
                        decoration: const InputDecoration(
                          labelText: 'Book',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: bookOptions
                            .map(
                              (option) => DropdownMenuItem<int?>(
                                value: option.bookNumber,
                                child: Text(option.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setState(() {
                            _selectedBookNumber = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (snapshot.connectionState == ConnectionState.done &&
                  rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'No verses found.',
                    style: theme.textTheme.bodyLarge,
                  ),
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
              for (final row in filteredRows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    row.reference,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    row.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onSelectBlockId(row.blockId);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<({List<ViewerStrongsOccurrence> rows, List<BookRecord> books})> _loadData(
    String canonical,
  ) async {
    final results = await Future.wait([
      widget.repository.loadOccurrences(canonical),
      StudyBibleDatabase.instance.loadBooks(),
    ]);
    return (
      rows: results[0] as List<ViewerStrongsOccurrence>,
      books: results[1] as List<BookRecord>,
    );
  }

  bool _matchesFilters(ViewerStrongsOccurrence row) {
    if (_selectedBookNumber != null) {
      return row.bookNumber == _selectedBookNumber;
    }
    final range = viewerSectionBookRange(_selectedSection);
    if (range == null) return true;
    return row.bookNumber >= range.$1 && row.bookNumber <= range.$2;
  }
}
