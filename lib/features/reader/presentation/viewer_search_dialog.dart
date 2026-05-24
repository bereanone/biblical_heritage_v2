import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_settings_service.dart';
import '../../../core/database/study_bible_database.dart';
import '../../library/presentation/library_book_reader_screen.dart';
import '../../library/data/library_catalog_service.dart';
import '../../library/presentation/library_catalog_search_panel.dart';
import '../../library/presentation/library_font_scale.dart';
import '../data/highlight_groups_repository.dart';
import 'viewer_book_group_colors.dart';
import 'reader_search_mode_picker.dart';
import 'viewer_search_filter_widgets.dart';
import 'viewer_search_models.dart';
import 'viewer_search_options.dart';
import 'viewer_search_query.dart';
import 'viewer_search_results_panel.dart';
import 'tag_quick_apply_helper.dart';

Future<ViewerSearchSelection?> showViewerSearchDialog(
  BuildContext context, {
  required double fontScale,
  String? lastSearchTerm,
  String? currentTag,
  Future<void> Function(String tag)? onBibleResultAdded,
  ReaderSearchMode initialMode = ReaderSearchMode.bible,
  int? initialHighlightGroupId,
  bool startInHighlightMode = false,
}) {
  return showGeneralDialog<ViewerSearchSelection>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Search',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, route, page) => SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: ViewerSearchDialog(
            fontScale: fontScale,
            lastSearchTerm: lastSearchTerm,
            currentTag: currentTag,
            onBibleResultAdded: onBibleResultAdded,
            initialMode: initialMode,
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
    this.currentTag,
    this.onBibleResultAdded,
    this.initialMode = ReaderSearchMode.bible,
    this.initialHighlightGroupId,
    this.startInHighlightMode = false,
  });

  final double fontScale;
  final String? lastSearchTerm;
  final String? currentTag;
  final Future<void> Function(String tag)? onBibleResultAdded;
  final ReaderSearchMode initialMode;
  final int? initialHighlightGroupId;
  final bool startInHighlightMode;

  @override
  State<ViewerSearchDialog> createState() => _ViewerSearchDialogState();
}

class _ViewerSearchDialogState extends State<ViewerSearchDialog> {
  static const _pageSize = 200;
  final _tagRepository = HashTagRepository();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<PassageSearchResult> _results = const [];
  List<BookRecord> _books = const [];
  List<HighlightGroupRecord> _highlightGroups = const [];
  var _selectedSection = 'All';
  int? _selectedBookNumber;
  int? _selectedHighlightGroupId;
  bool _lookupByHighlight = false;
  late ReaderSearchMode _mode;
  String? _activeSearchTerm;
  String? _currentDefaultTag;
  bool _loadingCurrentDefaultTag = true;
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
    _mode = widget.initialMode;
    _lookupByHighlight = widget.startInHighlightMode;
    _selectedHighlightGroupId = widget.initialHighlightGroupId;
    _loadBooks();
    _loadHighlightGroups();
    if ((widget.currentTag ?? '').trim().isNotEmpty) {
      _currentDefaultTag = widget.currentTag!.trim();
      _loadingCurrentDefaultTag = false;
    } else {
      _loadCurrentDefaultTag();
    }
    _loadRememberedBibleSearch();
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

  Future<void> _loadCurrentDefaultTag() async {
    final explicitCurrentTag = widget.currentTag?.trim() ?? '';
    if (explicitCurrentTag.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _currentDefaultTag = explicitCurrentTag;
        _loadingCurrentDefaultTag = false;
      });
      return;
    }
    final defaultTag = await _tagRepository.loadActiveDefaultTag();
    if (!mounted) return;
    setState(() {
      _currentDefaultTag = defaultTag;
      _loadingCurrentDefaultTag = false;
    });
  }

  Future<String?> _syncCurrentDefaultTag() async {
    final explicitCurrentTag = widget.currentTag?.trim() ?? '';
    if (explicitCurrentTag.isNotEmpty) {
      if (!mounted) return explicitCurrentTag;
      setState(() {
        _currentDefaultTag = explicitCurrentTag;
        _loadingCurrentDefaultTag = false;
      });
      return explicitCurrentTag;
    }
    final defaultTag = await _tagRepository.loadActiveDefaultTag();
    if (!mounted) return null;
    setState(() {
      _currentDefaultTag = defaultTag;
      _loadingCurrentDefaultTag = false;
    });
    return defaultTag;
  }

  Future<void> _loadRememberedBibleSearch() async {
    if (_mode != ReaderSearchMode.bible) return;
    if (_controller.text.trim().isNotEmpty) return;
    final remembered = await AppSettingsService.instance.loadLastBibleSearch();
    if (!mounted) return;
    final query = remembered?.trim() ?? '';
    if (query.isEmpty || _controller.text.trim().isNotEmpty) return;
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
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
    final inserted =
        '${needsLeadingSpace ? ' ' : ''}$token${needsTrailingSpace ? ' ' : ''}';
    final nextText = '$prefix$inserted$suffix';
    final caretOffset = (prefix + inserted).length;

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: caretOffset),
    );
    _focusNode.requestFocus();
  }

  void _setSearchMode(ReaderSearchMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
    });
    if (_mode == ReaderSearchMode.bible) {
      if (_controller.text.trim().isEmpty) {
        unawaited(_loadRememberedBibleSearch());
      }
      _focusNode.requestFocus();
    }
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

    if (_mode == ReaderSearchMode.bible && !_lookupByHighlight) {
      _activeSearchTerm = query;
      await AppSettingsService.instance.saveLastBibleSearch(query);
    }

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

  Future<void> _showMissingTagDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a #tag'),
        content: const Text(
          'No valid current #tag is selected. Open the Tags screen and set a default #tag before using quick apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<PassageSearchResponse> _performHighlightLookup({
    required bool append,
  }) async {
    final groupId = _selectedHighlightGroupId;
    if (groupId == null) {
      return const PassageSearchResponse(results: [], totalCount: 0);
    }
    final refs = await HighlightGroupsRepository().loadVerseRefsForGroup(
      groupId,
    );
    return StudyBibleDatabase.instance.loadPassagesForVerseRefs(
      refs,
      section: _selectedSection,
      bookNumber: _selectedBookNumber,
      limit: _pageSize,
      offset: append ? _results.length : 0,
    );
  }

  void _openLibraryItem(LibraryCatalogItem item, String searchQuery) {
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop();
    unawaited(
      Future<void>.microtask(() {
        if (!navigator.mounted) return;
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => LibraryBookReaderScreen(
              item: item,
              initialHref: item.epubHref,
              initialAnchorId: item.anchorId,
              initialSpineIndex: item.spineIndex,
              initialParagraphIndex: item.paragraphIndex,
              searchQuery: searchQuery,
              highlightTerms: extractLibrarySearchHighlightTerms(searchQuery),
            ),
          ),
        );
      }),
    );
  }

  String _searchResultMessage(
    String tag,
    HashTagSearchQuickApplyResult result,
  ) {
    if (result.inserted > 0) {
      if (result.createdDefaultTag) {
        return 'Created SearchResults and added result';
      }
      return 'Added to $tag';
    }
    if (result.skipped > 0) {
      return 'Already in $tag';
    }
    return 'Could not add to $tag';
  }

  Future<void> _quickApplyBibleSearchResult(PassageSearchResult result) async {
    try {
      final currentTag = (await _syncCurrentDefaultTag())?.trim() ?? '';
      if (currentTag.isEmpty) {
        await _showMissingTagDialog();
        return;
      }
      final repository = HashTagRepository();
      final response = await repository.addBibleSearchResultToTag(
        tag: currentTag,
        result: result,
      );
      if (!mounted || response.tag == null) return;
      if (response.inserted > 0) {
        final onBibleResultAdded = widget.onBibleResultAdded;
        if (onBibleResultAdded != null) {
          await onBibleResultAdded(response.tag!.trim());
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_searchResultMessage(response.tag!, response))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add to #tag: $error')));
    }
  }

  String _librarySearchStableRef(LibraryCatalogSearchResult result) {
    final item = result.item;
    final spine = item.spineIndex?.toString() ?? '';
    final paragraph = item.paragraphIndex?.toString() ?? '';
    final anchor = item.anchorId?.trim() ?? '';
    final href = item.epubHref?.trim() ?? '';
    return [
      'elibrary',
      item.id.trim(),
      spine,
      paragraph,
      anchor,
      href,
    ].join(':');
  }

  Future<void> _quickApplyLibrarySearchResult(
    LibraryCatalogSearchResult result,
    String searchQuery,
  ) async {
    try {
      final currentTag = (await _syncCurrentDefaultTag())?.trim() ?? '';
      if (currentTag.isEmpty) {
        await _showMissingTagDialog();
        return;
      }
      final paragraphText =
          (await LibraryCatalogService.instance.loadSearchResultParagraph(
            result,
          ))?.trim() ??
          '';
      if (paragraphText.isEmpty) {
        throw StateError('Missing paragraph text.');
      }
      final repository = HashTagRepository();
      final response = await repository.quickApplyELibrarySearchResult(
        bookTitle: result.item.displayTitle,
        locationText: result.locationText,
        paragraphText: paragraphText,
        stableRef: _librarySearchStableRef(result),
        referenceText: result.referenceText,
        sourceHref: result.item.epubHref,
        sourceAnchorId: result.item.anchorId,
        sourceSpineIndex: result.item.spineIndex,
        sourceParagraphIndex: result.item.paragraphIndex,
        sourceRelativePath: result.item.relativePath,
        searchQuery: searchQuery,
        tag: currentTag,
      );
      if (!mounted || response.tag == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_searchResultMessage(response.tag!, response))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add to #tag: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogScale = widget.fontScale.clamp(1.0, 2.4);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: ((theme.textTheme.bodyMedium?.fontSize ?? 14) * dialogScale)
          .clamp(14.0, 22.0),
    );
    final bookOptions = buildViewerSearchBookOptions(_books, _selectedSection);
    final selectedBook = bookOptions.firstWhere(
      (option) => option.bookNumber == _selectedBookNumber,
      orElse: () => bookOptions.first,
    );
    final selectedHighlightGroup = _highlightGroups
        .cast<HighlightGroupRecord?>()
        .firstWhere(
          (group) => group?.id == _selectedHighlightGroupId,
          orElse: () =>
              _highlightGroups.isEmpty ? null : _highlightGroups.first,
        );
    final isBibleMode = _mode == ReaderSearchMode.bible;
    final bibleSearchTerm = _activeSearchTerm ?? _controller.text.trim();
    final highlightTerms = isBibleMode && !_lookupByHighlight
        ? extractViewerSearchHighlightTerms(bibleSearchTerm)
        : const <String>[];

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
            final horizontalPadding = isCompact
                ? 12.0
                : (isRoomy ? 18.0 : 16.0);
            final topFieldPadding = isCompact ? 12.0 : (isRoomy ? 18.0 : 14.0);
            final resultTopPadding = isCompact ? 6.0 : (isRoomy ? 14.0 : 10.0);
            final syntaxText = isCompact
                ? '*, (), "", AND/OR/NOT'
                : 'Supports *, (), "phrases", AND, OR, NOT';
            final actionSpacing = isCompact ? 6.0 : 8.0;

            final bibleBody = SingleChildScrollView(
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
                                          _activeSearchTerm = null;
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
                                  if (bookNumber == _selectedBookNumber) {
                                    return;
                                  }
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
                                    if (bookNumber == _selectedBookNumber) {
                                      return;
                                    }
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
                    highlightTerms: highlightTerms,
                    currentTag: _currentDefaultTag,
                    isCurrentTagLoading: _loadingCurrentDefaultTag,
                    onLoadMore: () => _performSearch(append: true),
                    onSelectResult: (result) => Navigator.of(context).pop(
                      ViewerSearchSelection(
                        blockId: result.blockId,
                        bookNumber: result.bookNumber,
                        chapter: result.chapter,
                        verse: result.verse,
                        lastSearchTerm: bibleSearchTerm,
                      ),
                    ),
                    onQuickApplyResult: _quickApplyBibleSearchResult,
                  ),
                ],
              ),
            );

            final libraryBody = LibraryFontScaleScope(
              scale: widget.fontScale,
              child: LibraryCatalogSearchPanel(
                onSelectItem: _openLibraryItem,
                onQuickApplyItem: _quickApplyLibrarySearchResult,
              ),
            );

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close Search',
                      ),
                      Expanded(
                        child: Center(child: Text('Search', style: titleStyle)),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.dividerColor),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    topFieldPadding,
                    horizontalPadding,
                    fieldSpacing,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose whether to search the Bible or the eLibrary.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: isCompact ? 8 : 10),
                      SegmentedButton<ReaderSearchMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<ReaderSearchMode>(
                            value: ReaderSearchMode.bible,
                            icon: Icon(Icons.menu_book_outlined, size: 18),
                            label: Text('Bible'),
                          ),
                          ButtonSegment<ReaderSearchMode>(
                            value: ReaderSearchMode.elibrary,
                            icon: Icon(Icons.library_books_outlined, size: 18),
                            label: Text('eLibrary'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) return;
                          _setSearchMode(selection.first);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: isBibleMode ? 0 : 1,
                    children: [bibleBody, libraryBody],
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
