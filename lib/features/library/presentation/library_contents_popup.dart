part of 'library_book_reader_screen.dart';

class _NavigationDisplayEntry {
  const _NavigationDisplayEntry({
    required this.item,
    required this.depth,
    required this.displayIndex,
  });

  final LibraryCatalogNavigationItem item;
  final int depth;
  final int displayIndex;
}

class _ContentsPopupRow {
  const _ContentsPopupRow({
    required this.entry,
    required this.depth,
    required this.isMonthHeading,
  });

  final _NavigationDisplayEntry entry;
  final int depth;
  final bool isMonthHeading;
}

class _ContentsPopupSheet extends StatefulWidget {
  const _ContentsPopupSheet({
    required this.itemTitle,
    required this.entries,
    required this.sections,
    required this.selectedNavigationItemId,
    required this.selectedNavigationIndex,
    required this.selectedSectionIndex,
    required this.isNightMode,
    required this.isDevotionalNavigation,
  });

  final String itemTitle;
  final List<_NavigationDisplayEntry> entries;
  final List<LibraryBookSection> sections;
  final String? selectedNavigationItemId;
  final int selectedNavigationIndex;
  final int selectedSectionIndex;
  final bool isNightMode;
  final bool isDevotionalNavigation;

  @override
  State<_ContentsPopupSheet> createState() => _ContentsPopupSheetState();
}

class _ContentsPopupSheetState extends State<_ContentsPopupSheet> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  String? _lastTargetKey;
  String? _expandedMonthId;

  @override
  void initState() {
    super.initState();
    _expandedMonthId = _initialExpandedMonthId();
    _scheduleInitialScroll();
  }

  @override
  void didUpdateWidget(covariant _ContentsPopupSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries ||
        oldWidget.sections != widget.sections ||
        oldWidget.selectedNavigationItemId != widget.selectedNavigationItemId ||
        oldWidget.selectedNavigationIndex != widget.selectedNavigationIndex ||
        oldWidget.selectedSectionIndex != widget.selectedSectionIndex) {
      _scheduleInitialScroll();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isDevotionalContents =>
      widget.isDevotionalNavigation && widget.entries.isNotEmpty;

  LibraryNavigationTreeResult get _navigationTree {
    return buildLibraryNavigationTree(
      widget.entries.map((entry) => entry.item).toList(growable: false),
      devotionalMode: widget.isDevotionalNavigation,
    );
  }

  Map<String, _NavigationDisplayEntry> get _entriesById {
    return {for (final entry in widget.entries) entry.item.id: entry};
  }

  LibraryCatalogNavigationItem? _selectedPopupNavigationItem() {
    final selectedId = widget.selectedNavigationItemId?.trim();
    if (selectedId != null && selectedId.isNotEmpty) {
      for (final entry in widget.entries) {
        if (entry.item.id == selectedId) {
          return entry.item;
        }
      }
    }

    for (final entry in widget.entries) {
      if (entry.displayIndex == widget.selectedNavigationIndex) {
        return entry.item;
      }
    }

    return null;
  }

  bool _isDevotionalMonthHeading(LibraryCatalogNavigationItem item) {
    return parseDevotionalNavigationLabel(item.label)?.isMonthHeading == true;
  }

  String? _parentMonthIdForSelectedItem(
    LibraryNavigationTreeResult tree,
    LibraryCatalogNavigationItem selectedItem,
  ) {
    if (_isDevotionalMonthHeading(selectedItem)) {
      return selectedItem.id;
    }

    final parentById = <String, String?>{};
    void visit(List<LibraryCatalogNavigationItem> items, String? parentId) {
      for (final item in items) {
        parentById[item.id] = parentId;
        visit(tree.childrenByParent[item.id] ?? const [], item.id);
      }
    }

    visit(tree.childrenByParent[null] ?? const [], null);

    var currentId = selectedItem.id;
    final visited = <String>{};
    while (visited.add(currentId)) {
      final parentId = parentById[currentId];
      if (parentId == null) return null;
      final parent = _entriesById[parentId]?.item;
      if (parent == null) return null;
      if (_isDevotionalMonthHeading(parent)) {
        return parent.id;
      }
      currentId = parentId;
    }

    return null;
  }

  String? _monthRootIdForMonth(
    LibraryNavigationTreeResult tree,
    int monthIndex,
  ) {
    final roots = tree.childrenByParent[null] ?? const [];
    for (final root in roots) {
      final labelInfo = parseDevotionalNavigationLabel(root.label);
      if (labelInfo != null &&
          labelInfo.isMonthHeading &&
          labelInfo.monthIndex == monthIndex) {
        return root.id;
      }
    }
    return null;
  }

  String? _initialExpandedMonthId() {
    if (!_isDevotionalContents) return null;

    final tree = _navigationTree;
    final roots = tree.childrenByParent[null] ?? const [];
    final monthRoots = roots.where(_isDevotionalMonthHeading).toList();
    if (monthRoots.isEmpty) return null;

    final selectedItem = _selectedPopupNavigationItem();
    if (selectedItem != null) {
      final selectedMonthId = _parentMonthIdForSelectedItem(tree, selectedItem);
      if (selectedMonthId != null) return selectedMonthId;
    }

    final currentMonthId = _monthRootIdForMonth(tree, DateTime.now().month);
    if (currentMonthId != null) return currentMonthId;

    final januaryMonthId = _monthRootIdForMonth(tree, 1);
    if (januaryMonthId != null) return januaryMonthId;

    return monthRoots.first.id;
  }

  List<_ContentsPopupRow> _visibleDevotionalRows(
    LibraryNavigationTreeResult tree,
    List<LibraryCatalogNavigationItem> roots,
  ) {
    final rows = <_ContentsPopupRow>[];
    final entriesById = _entriesById;

    void visit(LibraryCatalogNavigationItem item, int depth) {
      final entry = entriesById[item.id];
      if (entry == null) return;

      final isMonthHeading = _isDevotionalMonthHeading(item);
      rows.add(
        _ContentsPopupRow(
          entry: entry,
          depth: depth,
          isMonthHeading: isMonthHeading,
        ),
      );

      if (isMonthHeading && _expandedMonthId != item.id) {
        return;
      }

      for (final child in tree.childrenByParent[item.id] ?? const []) {
        visit(child, depth + 1);
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }

    return rows;
  }

  String? _targetKeyForDevotionalScroll() {
    final selectedItem = _selectedPopupNavigationItem();
    if (selectedItem == null) return _expandedMonthId;

    final tree = _navigationTree;
    final selectedMonthId = _parentMonthIdForSelectedItem(tree, selectedItem);
    if (selectedMonthId != null) {
      if (_expandedMonthId == selectedMonthId) {
        return selectedItem.id;
      }
      return selectedMonthId;
    }

    return selectedItem.id;
  }

  void _scheduleInitialScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetKey = _initialTargetKey();
      if (targetKey == null || targetKey == _lastTargetKey) return;

      if (_isDevotionalContents) {
        _lastTargetKey = targetKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final targetContext = _itemKeys[targetKey]?.currentContext;
          if (targetContext == null) return;
          Scrollable.ensureVisible(
            targetContext,
            alignment: 0.08,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
          );
        });
        return;
      }

      final targetIndex = _initialTargetIndex();
      if (targetIndex == null) return;

      final estimatedOffset = (targetIndex * _estimatedRowExtent())
          .clamp(
            0.0,
            _scrollController.hasClients
                ? _scrollController.position.maxScrollExtent
                : double.infinity,
          )
          .toDouble();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(estimatedOffset);
      }

      _lastTargetKey = targetKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final targetContext = _itemKeys[targetKey]?.currentContext;
        if (targetContext == null) return;
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.08,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
        );
      });
    });
  }

  _NavigationDisplayEntry? _initialTargetEntry() {
    if (widget.entries.isNotEmpty) {
      for (final entry in widget.entries) {
        if (entry.item.isBodyStart) {
          return entry;
        }
      }

      for (final entry in widget.entries) {
        final href = _cleanNavigationHref(entry.item.href);
        final entryLabel = p.basenameWithoutExtension(href ?? entry.item.label);
        if (_isReaderFrontMatterLabel(entry.item.label) ||
            _isReaderFrontMatterLabel(entryLabel) ||
            entry.item.isFrontMatter) {
          continue;
        }
        return entry;
      }

      return widget.entries.first;
    }
    return null;
  }

  int? _firstRealContentSectionIndex(List<LibraryBookSection> sections) {
    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      if (_isReaderChapterOneLabel(section.title) ||
          _isReaderChapterOneLabel(
            p.basenameWithoutExtension(section.entryName),
          )) {
        return index;
      }
    }

    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      if (_isReaderFrontMatterLabel(section.title) ||
          _isReaderFrontMatterLabel(
            p.basenameWithoutExtension(section.entryName),
          )) {
        continue;
      }
      return index;
    }
    return null;
  }

  int? _initialTargetIndex() {
    final targetEntry = _initialTargetEntry();
    if (targetEntry != null) return targetEntry.displayIndex;

    if (widget.sections.isNotEmpty) {
      if (widget.selectedSectionIndex >= 0 &&
          widget.selectedSectionIndex < widget.sections.length) {
        return widget.selectedSectionIndex;
      }

      final firstRealContentIndex = _firstRealContentSectionIndex(
        widget.sections,
      );
      return firstRealContentIndex ?? 0;
    }

    return null;
  }

  String? _initialTargetKey() {
    if (_isDevotionalContents) {
      return _targetKeyForDevotionalScroll();
    }

    final targetEntry = _initialTargetEntry();
    if (targetEntry != null) return targetEntry.item.id;

    if (widget.sections.isNotEmpty) {
      if (widget.selectedSectionIndex >= 0 &&
          widget.selectedSectionIndex < widget.sections.length) {
        return 'section:${widget.selectedSectionIndex}';
      }

      final firstRealContentIndex = _firstRealContentSectionIndex(
        widget.sections,
      );
      return 'section:${firstRealContentIndex ?? 0}';
    }

    return null;
  }

  double _estimatedRowExtent() {
    if (_isDevotionalContents) return 54.0;
    if (widget.entries.isNotEmpty) return 84.0;
    return 84.0;
  }

  GlobalKey _keyFor(String key) {
    return _itemKeys.putIfAbsent(key, GlobalKey.new);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNight = theme.brightness == Brightness.dark || widget.isNightMode;
    final background = _readerSurfaceHighColor(theme, isNight);
    final borderColor = _readerBorderColor(theme, isNight);
    final sheetTextColor = _readerTextColor(theme, isNight);
    final sheetSubduedColor = _readerSubduedColor(theme, isNight);
    final devotionalTree = _isDevotionalContents ? _navigationTree : null;
    final devotionalRoots = devotionalTree?.childrenByParent[null] ?? const [];
    final devotionalMonthRoots =
        devotionalRoots.where(_isDevotionalMonthHeading).toList(growable: false)
          ..sort((left, right) {
            final leftInfo = parseDevotionalNavigationLabel(left.label);
            final rightInfo = parseDevotionalNavigationLabel(right.label);
            return (leftInfo?.monthIndex ?? 0).compareTo(
              rightInfo?.monthIndex ?? 0,
            );
          });
    final devotionalRows = devotionalTree != null
        ? _visibleDevotionalRows(devotionalTree, devotionalMonthRoots)
        : const <_ContentsPopupRow>[];
    final selectedPopupItem = _selectedPopupNavigationItem();
    final selectedMonthId = devotionalTree != null && selectedPopupItem != null
        ? _parentMonthIdForSelectedItem(devotionalTree, selectedPopupItem)
        : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Contents',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: sheetTextColor,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Close contents',
                        style: IconButton.styleFrom(
                          foregroundColor: sheetTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    widget.itemTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: sheetSubduedColor,
                    ),
                  ),
                ),
                Divider(height: 1, color: borderColor),
                Expanded(
                  child: widget.entries.isEmpty
                      ? ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: widget.sections.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final section = widget.sections[index];
                            final selected =
                                index == widget.selectedSectionIndex;
                            return KeyedSubtree(
                              key: _keyFor('section:$index'),
                              child: Material(
                                color: selected
                                    ? _readerSelectedColor(theme, isNight)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => Navigator.of(context).pop(index),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          section.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: sheetTextColor,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${section.paragraphs.length} paragraphs',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: sheetSubduedColor,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : _isDevotionalContents
                      ? ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          children: [
                            ..._buildDevotionalRowWidgets(
                              context,
                              devotionalRows,
                              theme: theme,
                              isNight: isNight,
                              sheetTextColor: sheetTextColor,
                              sheetSubduedColor: sheetSubduedColor,
                              selectedPopupItem: selectedPopupItem,
                              selectedMonthId: selectedMonthId,
                              devotionalTree: devotionalTree,
                            ),
                          ],
                        )
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: widget.entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final entry = widget.entries[index];
                            final selected =
                                widget.selectedNavigationItemId != null
                                ? entry.item.id ==
                                      widget.selectedNavigationItemId
                                : entry.displayIndex ==
                                      widget.selectedNavigationIndex;
                            return Padding(
                              padding: EdgeInsets.only(
                                left: entry.depth * 12.0,
                              ),
                              child: KeyedSubtree(
                                key: _keyFor(entry.item.id),
                                child: Material(
                                  color: selected
                                      ? _readerSelectedColor(theme, isNight)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => Navigator.of(
                                      context,
                                    ).pop(_tapTargetForEntry(index)),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            navigationDisplayLabel(
                                              entry.item,
                                              devotionalMode:
                                                  widget.isDevotionalNavigation,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: sheetTextColor,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDevotionalRowWidgets(
    BuildContext context,
    List<_ContentsPopupRow> rows, {
    required ThemeData theme,
    required bool isNight,
    required Color sheetTextColor,
    required Color sheetSubduedColor,
    required LibraryCatalogNavigationItem? selectedPopupItem,
    required String? selectedMonthId,
    required LibraryNavigationTreeResult? devotionalTree,
  }) {
    return [
      for (final row in rows)
        _buildDevotionalNavigationRow(
          context,
          row,
          theme: theme,
          isNight: isNight,
          sheetTextColor: sheetTextColor,
          sheetSubduedColor: sheetSubduedColor,
          selectedPopupItem: selectedPopupItem,
          selectedMonthId: selectedMonthId,
          devotionalTree: devotionalTree,
        ),
    ];
  }

  Widget _buildDevotionalNavigationRow(
    BuildContext context,
    _ContentsPopupRow row, {
    required ThemeData theme,
    required bool isNight,
    required Color sheetTextColor,
    required Color sheetSubduedColor,
    required LibraryCatalogNavigationItem? selectedPopupItem,
    required String? selectedMonthId,
    required LibraryNavigationTreeResult? devotionalTree,
  }) {
    final item = row.entry.item;
    final selectedById = selectedPopupItem?.id == item.id;
    final selectedByIndex =
        selectedPopupItem == null &&
        row.entry.displayIndex == widget.selectedNavigationIndex;
    final isExpandedMonth = row.isMonthHeading && _expandedMonthId == item.id;
    final monthSelectedButCollapsed =
        row.isMonthHeading && selectedMonthId == item.id && !isExpandedMonth;
    final hasChildren =
        (devotionalTree?.childrenByParent[item.id]?.isNotEmpty ?? false) &&
        row.isMonthHeading;
    final selected =
        selectedById || selectedByIndex || monthSelectedButCollapsed;

    return Padding(
      key: _keyFor(item.id),
      padding: EdgeInsets.only(
        left: row.depth * 12.0,
        bottom: row.isMonthHeading ? 4 : 2,
      ),
      child: Material(
        color: selected
            ? _readerSelectedColor(theme, isNight)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(row.isMonthHeading ? 14 : 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(row.isMonthHeading ? 14 : 12),
          onTap: () {
            if (row.isMonthHeading) {
              setState(() {
                _expandedMonthId = isExpandedMonth ? null : item.id;
              });
              _scrollToKey(item.id);
              return;
            }
            Navigator.of(context).pop(item);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: row.isMonthHeading ? 9 : 7,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    navigationDisplayLabel(
                      item,
                      devotionalMode: widget.isDevotionalNavigation,
                    ),
                    maxLines: row.isMonthHeading ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (row.isMonthHeading
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.bodyLarge)
                            ?.copyWith(
                              fontWeight: row.isMonthHeading
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: sheetTextColor,
                            ),
                  ),
                ),
                if (row.isMonthHeading)
                  Icon(
                    isExpandedMonth
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    color: sheetSubduedColor,
                  )
                else if (hasChildren)
                  Icon(Icons.chevron_right, color: sheetSubduedColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToKey(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _itemKeys[key]?.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.08,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
      );
    });
  }

  LibraryCatalogNavigationItem _tapTargetForEntry(int index) {
    return widget.entries[index].item;
  }
}
