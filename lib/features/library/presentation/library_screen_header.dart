part of 'library_screen.dart';

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.hasRoot,
    required this.rootPath,
    required this.currentFolderFilter,
    required this.currentFolderLabel,
    required this.onOpenBible,
    required this.onOpenLibraryRootSetup,
    required this.onOpenELibrarySetup,
    required this.onRefresh,
  });

  final bool hasRoot;
  final String? rootPath;
  final String currentFolderFilter;
  final String currentFolderLabel;
  final VoidCallback onOpenBible;
  final VoidCallback onOpenLibraryRootSetup;
  final VoidCallback onOpenELibrarySetup;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipColor = hasRoot
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 48),
          child: FilledButton.tonalIcon(
            onPressed: onOpenBible,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Bible'),
            style: _libraryTonalButtonStyle(context),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'eLibrary',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const Spacer(),
        Tooltip(
          message: rootPath ?? 'Choose a Library Root',
          child: _StatusPill(
            icon: hasRoot ? Icons.folder_open : Icons.folder_off_outlined,
            label: hasRoot ? 'Ready' : 'No root',
            color: chipColor,
          ),
        ),
        const SizedBox(width: 8),
        _FolderRootMenu(
          currentValue: currentFolderFilter,
          currentLabel: currentFolderLabel,
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
              case 'ePubs':
              case 'PDFs':
              case 'all':
                break;
            }
          },
          customMenuItems: const [
            PopupMenuItem(value: 'root', child: Text('Choose Library Folder')),
            PopupMenuItem(value: 'setup', child: Text('Open eLibrary Setup')),
            PopupMenuItem(value: 'refresh', child: Text('Refresh Folders')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'ePubs', child: Text('ePubs')),
            PopupMenuItem(value: 'PDFs', child: Text('PDFs')),
            PopupMenuItem(value: 'all', child: Text('All')),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _FolderRootMenu extends StatelessWidget {
  const _FolderRootMenu({
    required this.currentValue,
    required this.currentLabel,
    required this.onSelected,
    this.customMenuItems,
  });

  final String currentValue;
  final String currentLabel;
  final ValueChanged<String> onSelected;
  final List<PopupMenuEntry<String>>? customMenuItems;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Choose folder root',
      onSelected: onSelected,
      initialValue: currentValue,
      itemBuilder: (context) =>
          customMenuItems ??
          const [
            PopupMenuItem<String>(value: 'ePubs', child: Text('ePubs')),
            PopupMenuItem<String>(value: 'PDFs', child: Text('PDFs')),
            PopupMenuItem<String>(value: 'all', child: Text('All')),
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
              Icons.folder_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              currentLabel,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
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
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
