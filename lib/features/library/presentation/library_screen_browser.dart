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
          style: libraryBodyTextStyle(
            context,
            Theme.of(context).textTheme.bodyLarge,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
          style: libraryBodyTextStyle(
            context,
            Theme.of(context).textTheme.bodyLarge,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.isNotEmpty;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.search,
          style: libraryBodyTextStyle(
            context,
            theme.textTheme.bodyMedium,
            color: theme.colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Find book/title',
            hintStyle: libraryCaptionTextStyle(
              context,
              theme.textTheme.bodySmall,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            suffixIcon: hasText
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Apply search',
                        icon: const Icon(Icons.search),
                        onPressed: onApply,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: onClear,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                      ),
                    ],
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
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
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            labelStyle: libraryControlTextStyle(
              context,
              theme.textTheme.bodyMedium,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

class _CollectionFilterMenu extends StatelessWidget {
  const _CollectionFilterMenu({
    required this.currentValue,
    required this.options,
    required this.onSelected,
  });

  final String currentValue;
  final List<LibraryCollectionFilterOption> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(14);
    return Tooltip(
      message: 'Choose collection',
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: DropdownButtonFormField<String>(
          initialValue: currentValue,
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option.value,
                child: Text(option.label),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            onSelected(value);
          },
          isDense: true,
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          borderRadius: borderRadius,
          icon: Icon(
            Icons.arrow_drop_down,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          iconSize: 22,
          style: libraryControlTextStyle(
            context,
            theme.textTheme.labelLarge,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
          dropdownColor: _librarySurfaceHighColor(theme),
          decoration: InputDecoration(
            prefixIconConstraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
            prefixIcon: Icon(
              Icons.folder_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            filled: true,
            fillColor: _librarySurfaceHighColor(theme),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 0,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _libraryOutlineColor(theme)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _libraryOutlineColor(theme)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileTypeFilterMenu extends StatelessWidget {
  const _FileTypeFilterMenu({
    required this.currentValue,
    required this.onSelected,
  });

  final String currentValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = switch (currentValue.trim().toLowerCase()) {
      'pdfs' => 'PDFs',
      'all' => 'All',
      _ => 'ePubs',
    };
    return _FilterMenuButton(
      tooltip: 'Choose file type',
      icon: Icons.filter_alt_outlined,
      label: label,
      onSelected: onSelected,
      currentValue: currentValue,
      items: const [
        PopupMenuItem<String>(value: 'ePubs', child: Text('ePubs')),
        PopupMenuItem<String>(value: 'PDFs', child: Text('PDFs')),
        PopupMenuItem<String>(value: 'all', child: Text('All')),
      ],
    );
  }
}

class _FilterMenuButton extends StatelessWidget {
  const _FilterMenuButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onSelected,
    required this.currentValue,
    required this.items,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final ValueChanged<String> onSelected;
  final String currentValue;
  final List<PopupMenuEntry<String>> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      onSelected: onSelected,
      initialValue: currentValue,
      itemBuilder: (context) => items,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _librarySurfaceHighColor(Theme.of(context)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _libraryOutlineColor(Theme.of(context))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: libraryControlTextStyle(
                context,
                Theme.of(context).textTheme.labelLarge,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchTextButton extends StatelessWidget {
  const _SearchTextButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _librarySurfaceHighColor(theme),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.manage_search_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Search Text',
                style: libraryControlTextStyle(
                  context,
                  theme.textTheme.labelLarge,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
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
      segments: [
        ButtonSegment(
          value: _LibraryTab.books,
          icon: Icon(Icons.auto_stories_outlined),
          label: Text(
            'Books',
            style: libraryControlTextStyle(
              context,
              Theme.of(context).textTheme.labelLarge,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        ButtonSegment(
          value: _LibraryTab.recent,
          icon: Icon(Icons.history_rounded),
          label: Text(
            'Recent',
            style: libraryControlTextStyle(
              context,
              Theme.of(context).textTheme.labelLarge,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
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
        segments: [
          ButtonSegment(
            value: _LibraryView.shelf,
            icon: Icon(Icons.grid_view_rounded),
            label: Text(
              'Shelf',
              style: libraryControlTextStyle(
                context,
                Theme.of(context).textTheme.labelLarge,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          ButtonSegment(
            value: _LibraryView.list,
            icon: Icon(Icons.view_list_rounded),
            label: Text(
              'List',
              style: libraryControlTextStyle(
                context,
                Theme.of(context).textTheme.labelLarge,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
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
      labelStyle: libraryControlTextStyle(
        context,
        Theme.of(context).textTheme.labelLarge,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
      ),
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
  required BorderRadius borderRadius,
  required bool compact,
  required bool showCaption,
  required bool showCenterTitle,
}) {
  final theme = Theme.of(context);
  final fillColor = _libraryFallbackCoverColor(theme);
  final accentColor = _placeholderAccentColor(title);
  final monogram = _thumbnailMonogram(title);
  final fontScale = libraryFontScaleOf(context);
  final titleStyle = libraryScaledTextStyle(
    compact ? theme.textTheme.labelMedium : theme.textTheme.titleSmall,
    libraryTitleScale(fontScale),
    fontWeight: FontWeight.w800,
    color: theme.colorScheme.onSurface,
    height: 1.05,
  );
  final subtitleStyle = libraryScaledTextStyle(
    compact ? theme.textTheme.labelSmall : theme.textTheme.bodySmall,
    libraryCaptionScale(fontScale),
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(fillColor, accentColor, compact ? 0.08 : 0.12)!,
            Color.lerp(fillColor, accentColor, compact ? 0.22 : 0.18)!,
          ],
        ),
        border: Border.all(
          color: _libraryOutlineColor(theme).withValues(alpha: 0.75),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.15, -0.25),
                  radius: 1.05,
                  colors: [
                    theme.colorScheme.surface.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.18 : 0.28,
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: compact ? 5 : 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accentColor.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.28 : 0.20,
                ),
              ),
            ),
          ),
          Positioned(
            right: compact ? 5 : 7,
            top: compact ? 5 : 7,
            bottom: compact ? 5 : 7,
            width: compact ? 1.5 : 2.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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
          if (!showCenterTitle && !showCaption)
            if (compact)
              Center(
                child: Text(
                  monogram,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                  ),
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 42,
                        height: 52,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.22
                                : 0.30,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.12,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            monogram,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.78,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Icon(
                        Icons.menu_book_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.28,
                        ),
                      ),
                    ],
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
                style: libraryControlTextStyle(
                  context,
                  Theme.of(context).textTheme.bodyMedium,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: libraryCaptionTextStyle(
                  context,
                  Theme.of(context).textTheme.bodySmall,
                  color: subduedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _placeholderAccentColor(String title) {
  const palette = <Color>[
    Color(0xFF8F6F4E),
    Color(0xFF6F8A65),
    Color(0xFF8A6B5E),
    Color(0xFF76896F),
    Color(0xFF8A7A4F),
    Color(0xFF7B6A58),
  ];
  final normalized = title.trim();
  final index = normalized.hashCode.abs() % palette.length;
  return palette[index];
}

String _thumbnailMonogram(String title) {
  final normalized = title
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'[^a-zA-Z0-9 ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) return 'BK';

  final stopWords = <String>{
    'the',
    'a',
    'an',
    'of',
    'and',
    'to',
    'in',
    'on',
    'for',
    'from',
    'by',
    'with',
    'at',
    'into',
    'over',
    'under',
  };
  final words = normalized
      .split(' ')
      .where((word) => word.isNotEmpty)
      .where((word) => !stopWords.contains(word.toLowerCase()))
      .toList(growable: false);
  final sourceWords = words.isNotEmpty
      ? words
      : normalized.split(' ').where((word) => word.isNotEmpty).toList();
  if (sourceWords.isEmpty) return 'BK';

  final letters = <String>[];
  for (final word in sourceWords) {
    final firstLetter = RegExp(r'[A-Za-z0-9]').firstMatch(word)?.group(0);
    if (firstLetter == null) continue;
    letters.add(firstLetter.toUpperCase());
    if (letters.length >= 3) break;
  }

  if (letters.isNotEmpty) {
    if (letters.length == 1) {
      final compactWord = sourceWords.first.replaceAll(
        RegExp(r'[^A-Za-z0-9]+'),
        '',
      );
      if (compactWord.length >= 2) {
        return compactWord.substring(0, 2).toUpperCase();
      }
    }
    return letters.join();
  }

  final compactWord = sourceWords.first.replaceAll(
    RegExp(r'[^A-Za-z0-9]+'),
    '',
  );
  if (compactWord.isEmpty) return 'BK';
  return compactWord.length >= 2
      ? compactWord.substring(0, 2).toUpperCase()
      : compactWord.toUpperCase();
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
            style: libraryControlTextStyle(
              context,
              Theme.of(context).textTheme.titleSmall,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          subtitle: Text(
            '${item.subtitle}${item.lastOpened == null ? '' : ' • ${_stamp(item.lastOpened!)}'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: libraryCaptionTextStyle(
              context,
              Theme.of(context).textTheme.bodySmall,
              color: subduedColor,
            ),
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
      style: libraryCaptionTextStyle(
        context,
        Theme.of(context).textTheme.bodySmall,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      borderRadius: borderRadius,
      compact: compact,
      showCaption: false,
      showCenterTitle: false,
    );
  }
}
