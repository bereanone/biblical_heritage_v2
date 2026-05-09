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

class _ContentsPopupSheet extends StatefulWidget {
  const _ContentsPopupSheet({
    required this.itemTitle,
    required this.entries,
    required this.sections,
    required this.selectedNavigationItemId,
    required this.selectedNavigationIndex,
    required this.selectedSectionIndex,
    required this.isNightMode,
  });

  final String itemTitle;
  final List<_NavigationDisplayEntry> entries;
  final List<LibraryBookSection> sections;
  final String? selectedNavigationItemId;
  final int selectedNavigationIndex;
  final int selectedSectionIndex;
  final bool isNightMode;

  @override
  State<_ContentsPopupSheet> createState() => _ContentsPopupSheetState();
}

class _ContentsPopupSheetState extends State<_ContentsPopupSheet> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  String? _lastTargetKey;

  @override
  void initState() {
    super.initState();
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

  void _scheduleInitialScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetKey = _initialTargetKey();
      final targetIndex = _initialTargetIndex();
      if (targetKey == null || targetIndex == null) return;

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

      if (targetKey == _lastTargetKey) return;
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
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: widget.entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () =>
                                        Navigator.of(context).pop(entry.item),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.item.label,
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
}
