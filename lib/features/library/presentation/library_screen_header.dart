part of 'library_screen.dart';

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.selection,
    required this.onOpenBible,
    required this.onOpenLibraryRootSetup,
    required this.onOpenELibrarySetup,
    required this.onRefresh,
  });

  final LibraryRootSelection? selection;
  final VoidCallback onOpenBible;
  final VoidCallback onOpenLibraryRootSetup;
  final VoidCallback onOpenELibrarySetup;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontScale = libraryFontScaleOf(context);
    final currentSelection = selection;
    final hasRoot = currentSelection?.exists == true;
    final label = currentSelection?.badgeLabel ?? 'No root';
    final rootPath = currentSelection?.path;
    final chipColor = switch (selection?.source) {
      LibraryRootSource.userSelected => theme.colorScheme.primary,
      LibraryRootSource.defaultAppFolder => theme.colorScheme.tertiary,
      LibraryRootSource.legacyImplicit => theme.colorScheme.secondary,
      LibraryRootSource.unknown => theme.colorScheme.error,
      null => theme.colorScheme.onSurfaceVariant,
    };

    final bibleButton = FilledButton.tonalIcon(
      onPressed: onOpenBible,
      icon: const Icon(Icons.arrow_back),
      label: Text(
        'Bible',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: libraryControlTextStyle(
          context,
          theme.textTheme.labelLarge,
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      style: _libraryTonalButtonStyle(context),
    );

    final statusPill = Tooltip(
      message: currentSelection == null
          ? 'Choose a Library Root'
          : '${currentSelection.statusLabel}\n${rootPath ?? 'No path selected.'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenLibraryRootSetup,
          borderRadius: BorderRadius.circular(999),
          child: _StatusPill(
            icon: hasRoot ? Icons.folder_open : Icons.folder_off_outlined,
            label: label,
            color: chipColor,
          ),
        ),
      ),
    );

    final actionsMenu = _LibraryActionsMenu(
      onSelected: (value) {
        switch (value) {
          case 'root':
            onOpenLibraryRootSetup();
            break;
          case 'setup':
            onOpenELibrarySetup();
            break;
          case 'refresh':
            onRefresh();
            break;
        }
      },
    );

    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    if (isNarrow) {
      // Phone portrait: two-row layout to prevent right overflow.
      // Row 1: back button + title (Expanded so it never overflows).
      // Row 2: status pill + actions menu.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              bibleButton,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'eLibrary',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: libraryScaledTextStyle(
                    theme.textTheme.titleLarge,
                    libraryTitleScale(fontScale),
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              statusPill,
              const SizedBox(width: 8),
              actionsMenu,
            ],
          ),
        ],
      );
    }

    // Wide layout (iPad / macOS): original single-row layout.
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: bibleButton,
        ),
        const SizedBox(width: 12),
        Text(
          'eLibrary',
          style: libraryScaledTextStyle(
            theme.textTheme.headlineMedium,
            libraryTitleScale(fontScale),
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        statusPill,
        const SizedBox(width: 8),
        actionsMenu,
        const SizedBox(width: 8),
      ],
    );
  }
}

class _LibraryActionsMenu extends StatelessWidget {
  const _LibraryActionsMenu({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Library actions',
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'root', child: Text('Choose Library Folder')),
        PopupMenuItem(value: 'setup', child: Text('Open eLibrary Setup')),
        PopupMenuItem(value: 'refresh', child: Text('Refresh Folders')),
      ],
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
              Icons.more_horiz,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Menu',
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: libraryControlTextStyle(
              context,
              Theme.of(context).textTheme.labelLarge,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
