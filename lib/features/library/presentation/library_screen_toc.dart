// ignore_for_file: unused_element, unused_element_parameter

part of 'library_screen.dart';

class _TocPane extends StatelessWidget {
  const _TocPane({
    super.key,
    required this.selectedItem,
    required this.navigationItems,
    required this.loadingNavigation,
    required this.searchQuery,
    required this.onSelectBook,
    required this.onOpenBook,
  });

  final LibraryCatalogItem? selectedItem;
  final List<LibraryCatalogNavigationItem> navigationItems;
  final bool loadingNavigation;
  final String searchQuery;
  final ValueChanged<LibraryCatalogItem> onSelectBook;
  final ValueChanged<LibraryCatalogItem> onOpenBook;

  @override
  Widget build(BuildContext context) {
    final item = selectedItem;
    if (item == null) {
      return Center(
        child: Text(
          'Select a book to see its contents.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    final filteredNavigation = _filterNavigation(navigationItems, searchQuery);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SelectedBookSummary(item: item, onOpen: () => onOpenBook(item)),
        const SizedBox(height: 12),
        Expanded(
          child: loadingNavigation
              ? const Center(child: CircularProgressIndicator())
              : filteredNavigation.isEmpty
              ? Center(
                  child: Text(
                    'No TOC entries available for this title.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : _NavigationTree(items: filteredNavigation),
        ),
      ],
    );
  }
}

class _SelectedBookSummary extends StatelessWidget {
  const _SelectedBookSummary({required this.item, required this.onOpen});

  final LibraryCatalogItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final subduedColor = theme.colorScheme.onSurfaceVariant;
    return Material(
      color: _librarySurfaceLowColor(theme),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: onOpen,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(color: _libraryOutlineColor(theme)),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(color: subduedColor),
            ),
            const SizedBox(height: 4),
            Text(
              item.relativePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: subduedColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationTree extends StatefulWidget {
  const _NavigationTree({required this.items});

  final List<LibraryCatalogNavigationItem> items;

  @override
  State<_NavigationTree> createState() => _NavigationTreeState();
}

class _NavigationTreeState extends State<_NavigationTree> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  String? _lastTargetId;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToTarget();
  }

  @override
  void didUpdateWidget(covariant _NavigationTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _scheduleScrollToTarget();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToTarget() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetId = _initialTargetId();
      if (targetId == null || targetId == _lastTargetId) return;
      _lastTargetId = targetId;
      final targetKey = _itemKeys[targetId];
      final targetContext = targetKey?.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.08,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
      );
    });
  }

  String? _initialTargetId() {
    final tree = buildLibraryNavigationTree(widget.items);
    final roots = tree.childrenByParent[null] ?? const [];
    for (final root in roots) {
      if (root.isBodyStart) {
        return root.id;
      }
    }
    for (final root in roots) {
      if (_isLibraryChapterOneLabel(root.label)) {
        return root.id;
      }
      if (root.contentKind?.trim().toLowerCase() == 'body' ||
          (!root.isFrontMatter && !_isLibraryFrontMatterLabel(root.label))) {
        return root.id;
      }
    }

    if (roots.isNotEmpty) return roots.first.id;

    for (final item in widget.items) {
      if (item.isBodyStart) {
        return item.id;
      }
      if (item.contentKind?.trim().toLowerCase() == 'body' ||
          (!item.isFrontMatter && !_isLibraryFrontMatterLabel(item.label))) {
        return item.id;
      }
    }
    return widget.items.isNotEmpty ? widget.items.first.id : null;
  }

  GlobalKey _keyFor(String id) {
    return _itemKeys.putIfAbsent(id, GlobalKey.new);
  }

  @override
  Widget build(BuildContext context) {
    final tree = buildLibraryNavigationTree(widget.items);
    final childrenByParent = tree.childrenByParent;
    final roots = childrenByParent[null] ?? const [];
    if (roots.isEmpty) {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final item in widget.items)
            KeyedSubtree(
              key: _keyFor(item.id),
              child: _NavigationTile(item: item, indent: 0),
            ),
        ],
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        for (final root in roots) ...[
          KeyedSubtree(
            key: _keyFor(root.id),
            child: _NavigationTreeNode(
              item: root,
              childrenByParent: childrenByParent,
              depth: 0,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _NavigationTreeNode extends StatelessWidget {
  const _NavigationTreeNode({
    required this.item,
    required this.childrenByParent,
    required this.depth,
  });

  final LibraryCatalogNavigationItem item;
  final Map<String?, List<LibraryCatalogNavigationItem>> childrenByParent;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final children = childrenByParent[item.id] ?? const [];
    if (children.isEmpty) {
      return _NavigationTile(item: item, indent: depth);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _librarySurfaceLowColor(Theme.of(context)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.only(
          left: 12.0 + depth * 12.0,
          right: 12,
          top: 2,
          bottom: 2,
        ),
        childrenPadding: EdgeInsets.only(left: 10.0 + depth * 12.0, bottom: 8),
        backgroundColor: _librarySurfaceLowColor(theme),
        collapsedBackgroundColor: _librarySurfaceLowColor(theme),
        title: Text(
          item.label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        children: [
          for (final child in children) ...[
            _NavigationTreeNode(
              item: child,
              childrenByParent: childrenByParent,
              depth: depth + 1,
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({required this.item, required this.indent});

  final LibraryCatalogNavigationItem item;
  final int indent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final subduedColor = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.only(left: indent * 12.0, bottom: 6),
      child: Material(
        color: _librarySurfaceLowColor(theme),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          leading: Icon(
            Icons.subject_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            item.label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          subtitle: item.href == null
              ? null
              : Text(
                  item.href!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subduedColor,
                  ),
                ),
        ),
      ),
    );
  }
}
