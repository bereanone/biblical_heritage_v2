part of 'library_screen.dart';

class _LibraryPane extends StatelessWidget {
  const _LibraryPane({
    super.key,
    required this.books,
    required this.selectedBookId,
    required this.view,
    required this.onSelectBook,
    required this.isEmptyMessage,
  });

  final List<LibraryCatalogItem> books;
  final String? selectedBookId;
  final _LibraryView view;
  final ValueChanged<LibraryCatalogItem> onSelectBook;
  final String isEmptyMessage;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Center(
        child: Text(
          isEmptyMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return switch (view) {
      _LibraryView.shelf => GridView.builder(
        key: const PageStorageKey('library-shelf'),
        padding: const EdgeInsets.only(bottom: 12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 170,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.73,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final item = books[index];
          return _BookCoverCard(
            item: item,
            selected: item.id == selectedBookId,
            onTap: () => onSelectBook(item),
          );
        },
      ),
      _LibraryView.list => ListView.separated(
        key: const PageStorageKey('library-list'),
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: books.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = books[index];
          return _BookListTile(
            item: item,
            selected: item.id == selectedBookId,
            onTap: () => onSelectBook(item),
          );
        },
      ),
    };
  }
}

class _RecentPane extends StatelessWidget {
  const _RecentPane({
    super.key,
    required this.books,
    required this.selectedBookId,
    required this.onSelectBook,
    required this.isEmptyMessage,
  });

  final List<LibraryCatalogItem> books;
  final String? selectedBookId;
  final ValueChanged<LibraryCatalogItem> onSelectBook;
  final String isEmptyMessage;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Center(
        child: Text(
          isEmptyMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: books.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = books[index];
        return _BookListTile(
          item: item,
          selected: item.id == selectedBookId,
          onTap: () => onSelectBook(item),
          trailing: _RecentStamp(item: item),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'Search books',
        filled: true,
        fillColor: _librarySurfaceHighestColor(theme),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _libraryOutlineColor(theme)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _libraryOutlineColor(theme)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

class _TabSelector extends StatelessWidget {
  const _TabSelector({required this.selectedTab, required this.onChanged});

  final _LibraryTab selectedTab;
  final ValueChanged<_LibraryTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_LibraryTab>(
      segments: const [
        ButtonSegment(
          value: _LibraryTab.books,
          icon: Icon(Icons.auto_stories_outlined),
          label: Text('Books'),
        ),
        ButtonSegment(
          value: _LibraryTab.recent,
          icon: Icon(Icons.history_rounded),
          label: Text('Recent'),
        ),
      ],
      selected: {selectedTab},
      onSelectionChanged: (selection) {
        if (selection.isEmpty) return;
        onChanged(selection.first);
      },
    );
  }
}

class _ViewToggleRow extends StatelessWidget {
  const _ViewToggleRow({required this.view, required this.onViewChanged});

  final _LibraryView view;
  final ValueChanged<_LibraryView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<_LibraryView>(
        segments: const [
          ButtonSegment(
            value: _LibraryView.shelf,
            icon: Icon(Icons.grid_view_rounded),
            label: Text('Shelf'),
          ),
          ButtonSegment(
            value: _LibraryView.list,
            icon: Icon(Icons.view_list_rounded),
            label: Text('List'),
          ),
        ],
        selected: {view},
        onSelectionChanged: (selection) {
          if (selection.isEmpty) return;
          onViewChanged(selection.first);
        },
      ),
    );
  }
}

class _AlphabetStrip extends StatelessWidget {
  const _AlphabetStrip({
    required this.selectedInitialLetter,
    required this.availableInitialLetters,
    required this.onChanged,
  });

  final String? selectedInitialLetter;
  final List<String> availableInitialLetters;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (availableInitialLetters.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _LetterChip(
          label: 'All',
          selected: selectedInitialLetter == null,
          onPressed: () => onChanged(null),
        ),
        for (final letter in availableInitialLetters)
          _LetterChip(
            label: letter,
            selected: selectedInitialLetter == letter,
            onPressed: () => onChanged(letter),
          ),
      ],
    );
  }
}

class _LetterChip extends StatelessWidget {
  const _LetterChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onPressed(),
      selectedColor: _librarySelectedColor(Theme.of(context)),
      backgroundColor: _librarySurfaceHighestColor(Theme.of(context)),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      side: BorderSide(color: _libraryOutlineColor(Theme.of(context))),
      shape: StadiumBorder(
        side: BorderSide(color: _libraryOutlineColor(Theme.of(context))),
      ),
    );
  }
}

Widget _bookCoverFrame({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String? folderLabel,
  required BorderRadius borderRadius,
  required bool compact,
  required bool showCaption,
  required bool showCenterTitle,
}) {
  final theme = Theme.of(context);
  final fillColor = _libraryFallbackCoverColor(theme);
  final titleStyle = compact
      ? theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface,
          height: 1.05,
        )
      : theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onSurface,
          height: 1.05,
        );
  final subtitleStyle = compact
      ? theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        )
      : theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
  final captionInsets = EdgeInsets.symmetric(
    horizontal: compact ? 6 : 8,
    vertical: compact ? 4 : 6,
  );
  final captionSide = compact ? 6.0 : 10.0;
  final captionBottom = compact ? 6.0 : 10.0;

  return ClipRRect(
    borderRadius: borderRadius,
    child: DecoratedBox(
      decoration: BoxDecoration(color: fillColor),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (folderLabel != null)
            Positioned(
              left: compact ? 8 : 10,
              top: compact ? 8 : 10,
              child: _CoverTag(label: folderLabel),
            ),
          if (showCenterTitle)
            Center(
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 10),
                child: Text(
                  _fallbackSpineLabel(title),
                  textAlign: TextAlign.center,
                  maxLines: compact ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ),
          if (showCaption)
            Positioned(
              left: captionSide,
              right: captionSide,
              bottom: captionBottom,
              child: Container(
                padding: captionInsets,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.82 : 0.92,
                  ),
                  borderRadius: BorderRadius.circular(compact ? 10 : 12),
                  border: Border.all(color: _libraryOutlineColor(theme)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _BookCoverCard extends StatelessWidget {
  const _BookCoverCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final LibraryCatalogItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.displayTitle;
    final subtitle = item.displayAuthor;
    final textColor = theme.colorScheme.onSurface;
    final subduedColor = theme.colorScheme.onSurfaceVariant;

    return Material(
      color: selected
          ? _librarySelectedColor(theme)
          : _librarySurfaceLowColor(theme),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _BookThumbnail(
                  item: item,
                  borderRadius: BorderRadius.circular(14),
                  compact: false,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: subduedColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookListTile extends StatelessWidget {
  const _BookListTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final LibraryCatalogItem item;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final subduedColor = theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? _librarySelectedColor(theme)
          : _librarySurfaceLowColor(theme),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          leading: _MiniCover(item: item),
          title: Text(
            item.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          subtitle: Text(
            '${item.subtitle}${item.lastOpened == null ? '' : ' • ${_stamp(item.lastOpened!)}'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: subduedColor),
          ),
          trailing: trailing,
        ),
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({required this.item});

  final LibraryCatalogItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 64,
      child: _BookThumbnail(
        item: item,
        borderRadius: BorderRadius.circular(10),
        compact: true,
      ),
    );
  }
}

class _RecentStamp extends StatelessWidget {
  const _RecentStamp({required this.item});

  final LibraryCatalogItem item;

  @override
  Widget build(BuildContext context) {
    final stamp = item.lastOpened ?? item.dateAdded;
    if (stamp == null) return const SizedBox.shrink();
    return Text(
      _stamp(stamp),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _CoverTag extends StatelessWidget {
  const _CoverTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BookThumbnail extends StatelessWidget {
  const _BookThumbnail({
    required this.item,
    required this.borderRadius,
    required this.compact,
  });

  final LibraryCatalogItem item;
  final BorderRadius borderRadius;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final coverPath = item.coverPath?.trim() ?? '';
    if (coverPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(coverPath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _fallbackThumbnail(context),
            ),
            if (!compact && item.folderRoot.trim().isNotEmpty)
              Positioned(
                left: 8,
                top: 8,
                child: _CoverTag(label: item.folderRoot),
              ),
          ],
        ),
      );
    }

    return _fallbackThumbnail(context);
  }

  Widget _fallbackThumbnail(BuildContext context) {
    return _bookCoverFrame(
      context: context,
      title: item.displayTitle,
      subtitle: item.displayAuthor,
      folderLabel: compact ? null : item.folderRoot,
      borderRadius: borderRadius,
      compact: compact,
      showCaption: !compact,
      showCenterTitle: true,
    );
  }
}
