import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import '../data/highlight_groups_repository.dart';
import 'viewer_book_group_colors.dart';
import 'viewer_search_filter_widgets.dart';
import 'viewer_search_models.dart';
import 'viewer_search_options.dart';
import 'viewer_search_results_panel.dart';

Future<ViewerSearchSelection?> showViewerSearchDialog(
  BuildContext context, {
  required double fontScale,
  String? lastSearchTerm,
  int? initialHighlightGroupId,
  bool startInHighlightMode = false,
}) {
  return showGeneralDialog<ViewerSearchSelection>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Verse Search',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, __) => SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: ViewerSearchDialog(
            fontScale: fontScale,
            lastSearchTerm: lastSearchTerm,
            initialHighlightGroupId: initialHighlightGroupId,
            startInHighlightMode: startInHighlightMode,
          ),
        ),
      ),
    ),
  );
}

class ViewerSearchDialog extends StatefulWidget {
  const ViewerSearchDialog({
    super.key,
    required this.fontScale,
    this.lastSearchTerm,
    this.initialHighlightGroupId,
    this.startInHighlightMode = false,
  });

  final double fontScale;
  final String? lastSearchTerm;
  final int? initialHighlightGroupId;
  final bool startInHighlightMode;

  @override
  State<ViewerSearchDialog> createState() => _ViewerSearchDialogState();
}

class _ViewerSearchDialogState extends State<ViewerSearchDialog> {
  static const _pageSize = 200;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<PassageSearchResult> _results = const [];
  List<BookRecord> _books = const [];
  List<HighlightGroupRecord> _highlightGroups = const [];
  var _selectedSection = 'All';
  int? _selectedBookNumber;
  int? _selectedHighlightGroupId;
  bool _lookupByHighlight = false;
  var _isLoading = false;
  var _hasSearched = false;
  var _isBroadSearch = false;
  var _totalResultsCount = 0;

  @override
  void initState() {
    super.initState();
    if ((widget.lastSearchTerm ?? '').trim().isNotEmpty) {
      _controller.text = widget.lastSearchTerm!;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
    _controller.addListener(_onQueryChanged);
    _lookupByHighlight = widget.startInHighlightMode;
    _selectedHighlightGroupId = widget.initialHighlightGroupId;
    _loadBooks();
    _loadHighlightGroups();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_lookupByHighlight) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (mounted) setState(() {});
  }

  void _insertSearchToken(String token) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final prefix = text.substring(0, start);
    final suffix = text.substring(end);
    final needsLeadingSpace =
        prefix.isNotEmpty && !prefix.endsWith(' ') && token != ')';
    final needsTrailingSpace =
        suffix.isNotEmpty && !suffix.startsWith(' ') && token != '(';
    final inserted = '${needsLeadingSpace ? ' ' : ''}$token${needsTrailingSpace ? ' ' : ''}';
    final nextText = '$prefix$inserted$suffix';
    final caretOffset = (prefix + inserted).length;

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caretOffset),
    );
    _focusNode.requestFocus();
  }

  Future<void> _loadBooks() async {
    final books = await StudyBibleDatabase.instance.loadBooks();
    if (!mounted) return;
    setState(() {
      _books = books;
    });
  }

  Future<void> _loadHighlightGroups() async {
    final groups = await HighlightGroupsRepository().loadGroups();
    if (!mounted) return;
    setState(() {
      _highlightGroups = groups;
      _selectedHighlightGroupId ??= groups.isEmpty ? null : groups.first.id;
    });
  }

  Future<void> _performSearch({bool append = false}) async {
    final query = _controller.text.trim();
    if (!_lookupByHighlight && query.isEmpty) return;
    if (_lookupByHighlight && _selectedHighlightGroupId == null) return;

    setState(() {
      _isLoading = true;
      if (!append) {
        _hasSearched = true;
      }
    });

    final search = _lookupByHighlight
        ? await _performHighlightLookup(append: append)
        : await StudyBibleDatabase.instance.searchPassages(
            query,
            section: _selectedSection,
            bookNumber: _selectedBookNumber,
            limit: _pageSize,
            offset: append ? _results.length : 0,
          );
    if (!mounted) return;
    setState(() {
      _results = append
          ? <PassageSearchResult>[..._results, ...search.results]
          : search.results;
      _totalResultsCount = search.totalCount;
      _isBroadSearch = search.totalCount > 200;
      _isLoading = false;
    });
  }

  Future<PassageSearchResponse> _performHighlightLookup({
    required bool append,
  }) async {
    final groupId = _selectedHighlightGroupId;
    if (groupId == null) {
      return const PassageSearchResponse(results: [], totalCount: 0);
    }
    final refs = await HighlightGroupsRepository().loadVerseRefsForGroup(groupId);
    return StudyBibleDatabase.instance.loadPassagesForVerseRefs(
      refs,
      section: _selectedSection,
      bookNumber: _selectedBookNumber,
      limit: _pageSize,
      offset: append ? _results.length : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogScale = widget.fontScale.clamp(1.0, 2.4);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize:
          ((theme.textTheme.bodyMedium?.fontSize ?? 14) * dialogScale).clamp(
        14.0,
        22.0,
      ),
    );
    final bookOptions = buildViewerSearchBookOptions(_books, _selectedSection);
    final selectedBook = bookOptions.firstWhere(
      (option) => option.bookNumber == _selectedBookNumber,
      orElse: () => bookOptions.first,
    );
    final selectedHighlightGroup = _highlightGroups.cast<HighlightGroupRecord?>().firstWhere(
          (group) => group?.id == _selectedHighlightGroupId,
          orElse: () => _highlightGroups.isEmpty ? null : _highlightGroups.first,
        );

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width.clamp(280.0, 560.0),
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 340;
            final isRoomy = constraints.maxWidth >= 430;
            final fieldSpacing = isCompact ? 6.0 : (isRoomy ? 12.0 : 8.0);
            final horizontalPadding = isCompact ? 12.0 : (isRoomy ? 18.0 : 16.0);
            final topFieldPadding = isCompact ? 12.0 : (isRoomy ? 18.0 : 14.0);
            final resultTopPadding = isCompact ? 6.0 : (isRoomy ? 14.0 : 10.0);
            final syntaxText = isCompact
                ? '*, (), "", AND/OR/NOT'
                : 'Supports *, (), "phrases", AND, OR, NOT';
            final actionSpacing = isCompact ? 6.0 : 8.0;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close Search',
                      ),
                      Expanded(
                        child: Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              Text('Search:', style: titleStyle),
                              SegmentedButton<bool>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment<bool>(value: false, label: Text('Verse')),
                                  ButtonSegment<bool>(value: true, label: Text('Color')),
                                ],
                                selected: {_lookupByHighlight},
                                onSelectionChanged: (Set<bool> newSelection) {
                                  final isHighlightMode = newSelection.first;
                                  if (_lookupByHighlight == isHighlightMode) return;
                                  setState(() {
                                    _lookupByHighlight = isHighlightMode;
                                    _results = const [];
                                    _hasSearched = false;
                                    _isBroadSearch = false;
                                    _totalResultsCount = 0;
                                    if (_lookupByHighlight) {
                                      _selectedHighlightGroupId ??=
                                          _highlightGroups.isEmpty ? null : _highlightGroups.first.id;
                                    }
                                  });
                                  if (!_lookupByHighlight) {
                                    _focusNode.requestFocus();
                                  } else if (_selectedHighlightGroupId != null) {
                                    _performSearch();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.dividerColor),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            topFieldPadding,
                            horizontalPadding,
                            fieldSpacing,
                          ),
                          child: _lookupByHighlight
                              ? ViewerSearchHighlightFilterField(
                                  selectedGroup: selectedHighlightGroup,
                                  groups: _highlightGroups,
                                  compact: true,
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedHighlightGroupId = value;
                                      _results = const [];
                                      _hasSearched = false;
                                      _isBroadSearch = false;
                                      _totalResultsCount = 0;
                                    });
                                    if (value != null) {
                                      _performSearch();
                                    }
                                  },
                                )
                              : TextField(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _performSearch(),
                                  decoration: InputDecoration(
                                    labelText: isCompact
                                        ? 'Search phrase'
                                        : 'Search for a phrase (e.g., "in the beginning")',
                                    hintText: 'Use * as a wildcard',
                                    border: const OutlineInputBorder(),
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_controller.text.isNotEmpty)
                                          IconButton(
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              _controller.clear();
                                              setState(() {
                                                _results = const [];
                                                _hasSearched = false;
                                                _isBroadSearch = false;
                                                _totalResultsCount = 0;
                                              });
                                            },
                                          ),
                                        IconButton(
                                          icon: const Icon(Icons.search),
                                          onPressed: _performSearch,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          child: isCompact
                              ? Column(
                                  children: [
                                    ViewerSearchSectionFilterField(
                                      selectedSection: _selectedSection,
                                      sectionOptions: viewerSearchSectionOptions,
                                      sectionColor: _sectionColor,
                                      compact: true,
                                      onChanged: (value) {
                                        if (value == _selectedSection) return;
                                        setState(() {
                                          _selectedSection = value;
                                          _selectedBookNumber = null;
                                          _results = const [];
                                        });
                                        if (_hasSearched && !_isLoading) {
                                          _performSearch();
                                        }
                                      },
                                    ),
                                    SizedBox(height: fieldSpacing),
                                    ViewerSearchBookFilterField(
                                      selectedBookLabel: selectedBook.label,
                                      selectedBookNumber: _selectedBookNumber,
                                      bookOptions: bookOptions,
                                      compact: true,
                                      onChanged: (bookNumber) {
                                        if (bookNumber == _selectedBookNumber) return;
                                        setState(() {
                                          _selectedBookNumber = bookNumber;
                                          _results = const [];
                                        });
                                        if (_hasSearched && !_isLoading) {
                                          _performSearch();
                                        }
                                      },
                                    ),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: ViewerSearchSectionFilterField(
                                        selectedSection: _selectedSection,
                                        sectionOptions: viewerSearchSectionOptions,
                                        sectionColor: _sectionColor,
                                        compact: false,
                                        onChanged: (value) {
                                          if (value == _selectedSection) return;
                                          setState(() {
                                            _selectedSection = value;
                                            _selectedBookNumber = null;
                                            _results = const [];
                                          });
                                          if (_hasSearched && !_isLoading) {
                                            _performSearch();
                                          }
                                        },
                                      ),
                                    ),
                                    SizedBox(width: fieldSpacing),
                                    Expanded(
                                      child: ViewerSearchBookFilterField(
                                        selectedBookLabel: selectedBook.label,
                                        selectedBookNumber: _selectedBookNumber,
                                        bookOptions: bookOptions,
                                        compact: false,
                                        onChanged: (bookNumber) {
                                          if (bookNumber == _selectedBookNumber) return;
                                          setState(() {
                                            _selectedBookNumber = bookNumber;
                                            _results = const [];
                                          });
                                          if (_hasSearched && !_isLoading) {
                                            _performSearch();
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        if (!_lookupByHighlight) ...[
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              fieldSpacing,
                              horizontalPadding,
                              0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  syntaxText,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                SizedBox(height: isCompact ? 4 : 6),
                                Wrap(
                                  spacing: actionSpacing,
                                  runSpacing: actionSpacing,
                                  children: [
                                    ViewerSearchActionChip(
                                      label: 'AND',
                                      onTap: () => _insertSearchToken('AND'),
                                    ),
                                    ViewerSearchActionChip(
                                      label: 'OR',
                                      onTap: () => _insertSearchToken('OR'),
                                    ),
                                    ViewerSearchActionChip(
                                      label: 'NOT',
                                      onTap: () => _insertSearchToken('NOT'),
                                    ),
                                    ViewerSearchActionChip(
                                      label: '(',
                                      onTap: () => _insertSearchToken('('),
                                    ),
                                    ViewerSearchActionChip(
                                      label: ')',
                                      onTap: () => _insertSearchToken(')'),
                                    ),
                                    ViewerSearchActionChip(
                                      label: 'Reset',
                                      onTap: () {
                                        _controller.clear();
                                        setState(() {
                                          _results = const [];
                                          _hasSearched = false;
                                          _isBroadSearch = false;
                                          _totalResultsCount = 0;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              fieldSpacing,
                              horizontalPadding,
                              0,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '#tags coming soon',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (_isBroadSearch)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              resultTopPadding,
                              horizontalPadding,
                              0,
                            ),
                            child: Text(
                              'Showing ${_results.length} of $_totalResultsCount matches',
                              style: bodyStyle,
                            ),
                          ),
                        ViewerSearchResultsPanel(
                          results: _results,
                          isLoading: _isLoading,
                          hasSearched: _hasSearched,
                          totalResultsCount: _totalResultsCount,
                          titleStyle: titleStyle,
                          bodyStyle: bodyStyle,
                          onLoadMore: () => _performSearch(append: true),
                          onSelectResult: (result) => Navigator.of(context).pop(
                            ViewerSearchSelection(
                              bookNumber: result.bookNumber,
                              chapter: result.chapter,
                              verse: result.verse,
                              lastSearchTerm: _controller.text.trim(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color? _sectionColor(ViewerSearchSectionOption section) {
    if (section.bookNumber != null) {
      return viewerBookGroupColor(section.bookNumber!);
    }
    return section.color;
  }
}
