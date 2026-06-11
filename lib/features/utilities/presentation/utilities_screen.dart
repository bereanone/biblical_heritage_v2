import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme_mode.dart';
import '../data/study_bible_backup_service.dart';
import '../data/study_bible_storage_index_report_service.dart';
import 'library_root_setup_screen.dart';
import '../../reader/presentation/bible_explorer_screen.dart';
import 'elibrary_download_screen.dart';
import 'elibrary_setup_screen.dart';

class UtilitiesScreen extends StatelessWidget {
  const UtilitiesScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeChanged;

  void _openBibleExplorer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BibleExplorerScreen(
          themeMode: themeMode,
          onThemeChanged: onThemeChanged,
        ),
      ),
    );
  }

  Future<void> _showChurchAutoMuteDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Church AutoMute'),
        content: const Text(
          'Church AutoMute is under construction for a future version.\n\n'
          'We are simplifying the setup so it will be easier to use for silencing your phone during church and restoring normal mode afterward.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBackupUserDataDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final shouldStart = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Backup User Data'),
        content: const Text(
          'Saves your tags, notes, highlights, markup, bookmarks, '
          'presentations, and settings. Downloaded EGW books are not included '
          'because they can be downloaded again.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Back Up'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (!context.mounted || shouldStart != true) return;
    await _runBackup(messenger);
  }

  Future<void> _showStorageAndIndexReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = await StudyBibleStorageIndexReportService.instance.build();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Storage and Index Report'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              child: SelectableText(report.toDiagnosticText()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not build the storage report: $error'),
        ),
      );
    }
  }

  Future<void> _runBackup(ScaffoldMessengerState messenger) async {
    try {
      final result = await StudyBibleBackupService.instance.createBackup();
      if (result == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Backup cancelled')),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Backup complete: ${result.backupPath}'),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Backup failed: ${_friendlyBackupError(error)}'),
        ),
      );
    }
  }

  String _friendlyBackupError(Object error) {
    final text = error.toString();
    return text.startsWith('StateError: ')
        ? text.substring('StateError: '.length)
        : text;
  }

  Future<void> _showCommentaryInstructionsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Commentary Instructions'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How commentary setup works',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                '1. Locate trusted commentary EPUB files. Biblical Heritage uses EPUB-first commentary because EPUB gives cleaner paragraph boundaries and better reading stability than PDF.',
              ),
              SizedBox(height: 8),
              Text(
                '2. Download the files normally to Downloads, Files, or another folder you can browse from this device.',
              ),
              SizedBox(height: 8),
              Text('3. Open Utilities, then Commentary Library Setup.'),
              SizedBox(height: 8),
              Text(
                '4. Choose Sync Base if you want the library mirrored through OneDrive or another cloud-backed folder. The app creates separate commentary_library and research_library folders there automatically.',
              ),
              SizedBox(height: 8),
              Text(
                '5. Tap Import EPUB/PDF and select the files you downloaded.',
              ),
              SizedBox(height: 8),
              Text(
                '6. BC commentary volumes are routed into Commentary Library. Other books are routed into Research Library automatically.',
              ),
              SizedBox(height: 8),
              Text(
                '7. The originals are never altered. Biblical Heritage copies imported files into a managed local library so your source files remain untouched.',
              ),
              SizedBox(height: 8),
              Text(
                '8. Tap Sync Now to mirror the managed library to your chosen cloud folder. Other devices using the same cloud base can then pull down the same library.',
              ),
              SizedBox(height: 12),
              Text(
                'Important notes',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                '• Commentary mode uses the proper BC commentary volume for the current Bible book.',
              ),
              SizedBox(height: 6),
              Text(
                '• Research mode searches the broader research library separately.',
              ),
              SizedBox(height: 6),
              Text(
                '• You can trim storage later by removing individual files or clearing commentary or research sections.',
              ),
              SizedBox(height: 6),
              Text(
                '• Cloud sync mirrors your managed library, but your original EPUB and PDF source files remain untouched.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCommentaryBlockSharingDialog(BuildContext context) async {
    final selection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Commentary Block Sharing'),
        content: const SizedBox(
          width: 540,
          child: Text(
            'Use this screen for bulk sharing of commentary blocks. Import is append-only and will not overwrite your existing notes.\n\n'
            'Import tip: copy shared block text to clipboard, then tap Import Clipboard.',
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('export'),
            child: const Text('Export All'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('import'),
            child: const Text('Import Clipboard'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (!context.mounted || selection == null) return;
    if (selection == 'export') {
      await Clipboard.setData(
        const ClipboardData(
          text: 'Commentary block export is not yet migrated into StudyBible2.',
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export placeholder copied to clipboard.'),
        ),
      );
      return;
    }

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboard?.text?.trim();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          clipboardText == null || clipboardText.isEmpty
              ? 'Clipboard was empty.'
              : 'Clipboard content ready to import.',
        ),
      ),
    );
  }

  Future<void> _showCommunityLinksDialog(BuildContext context) async {
    const websiteUrl = 'https://BiblicalHeritage.net';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Community Links'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'BiblicalHeritage.net',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'The main public home for Biblical Heritage resources, tutorials, downloads, privacy information, and shared study material.',
            ),
            SizedBox(height: 8),
            SelectableText(websiteUrl),
            SizedBox(height: 10),
            Text(
              'Facebook Community',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Sharing is encouraged through the Biblical Heritage #StudyBible Facebook page, where users can exchange study lists, commentary material, and future curated resources.',
            ),
            SizedBox(height: 8),
            Text(
              r'Shared #tag and $tag lists may include an identifying header for clarity and referral to BiblicalHeritage.net, but the app can still import the list content even if that header has been removed.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: websiteUrl));
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Website link copied.')),
              );
            },
            child: const Text('Copy Website'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(
                const ClipboardData(
                  text:
                      'Biblical Heritage #StudyBible Facebook page - see BiblicalHeritage.net for current links and community updates.',
                ),
              );
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Community note copied.')),
              );
            },
            child: const Text('Copy Community Note'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSupportDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Support Biblical Heritage'),
        content: const Text(
          'Biblical Heritage is intended to remain free. If God has blessed you and you want to support this work, your gift helps make wider translation possible and helps carry the gospel to more lost souls through the app store.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Utilities',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: _setupLeading(context),
        leadingWidth: _setupLeadingWidth(),
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.surface,
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                colorScheme.surface,
              ],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  Text(
                    'Setup and sharing tools for Biblical Heritage #StudyBible.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  _UtilityActionButton(
                    label: 'Church AutoMute',
                    icon: Icons.phone_android,
                    filled: true,
                    onPressed: () => _showChurchAutoMuteDialog(context),
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'Backup User Data',
                    icon: Icons.cloud,
                    filled: true,
                    onPressed: () => _showBackupUserDataDialog(context),
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'Storage and Index Report',
                    icon: Icons.storage_rounded,
                    filled: false,
                    onPressed: () => _showStorageAndIndexReport(context),
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'Library Root Setup',
                    icon: Icons.library_books_outlined,
                    filled: true,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LibraryRootSetupScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'eLibrary Downloads',
                    icon: Icons.download_rounded,
                    filled: true,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ELibraryDownloadScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'eLibrary Setup',
                    icon: Icons.library_books_outlined,
                    filled: true,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ELibrarySetupScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'Commentary Instructions',
                    icon: Icons.help_outline,
                    filled: false,
                    onPressed: () => _showCommentaryInstructionsDialog(context),
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'Commentary Block Sharing',
                    icon: Icons.import_export,
                    filled: true,
                    onPressed: () => _showCommentaryBlockSharingDialog(context),
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'Community Links',
                    icon: Icons.public,
                    filled: false,
                    onPressed: () => _showCommunityLinksDialog(context),
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'Support Biblical Heritage',
                    icon: Icons.volunteer_activism_outlined,
                    filled: true,
                    onPressed: () => _showSupportDialog(context),
                  ),
                  const SizedBox(height: 12),
                  _UtilityActionButton(
                    label: 'Open Bible Explorer',
                    icon: Icons.menu_book,
                    filled: false,
                    onPressed: () => _openBibleExplorer(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CommentaryLibrarySetupScreen extends StatelessWidget {
  const CommentaryLibrarySetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Commentary Library Setup'),
        leading: _setupLeading(context),
        leadingWidth: _setupLeadingWidth(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 16,
                  children: [
                    Text(
                      'Commentary Library Setup',
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      'This screen is the home for commentary import, sync base selection, and library synchronization. The full workflow is still being brought over from the original app, but the route is now wired and ready for the real implementation.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    _SetupActionTile(
                      icon: Icons.upload_file,
                      title: 'Import EPUB/PDF',
                      subtitle:
                          'Bring commentary files into the managed library',
                      onTap: () => _showPlaceholderSnackBar(
                        context,
                        'Commentary import is not yet migrated into StudyBible2.',
                      ),
                    ),
                    _SetupActionTile(
                      icon: Icons.folder_open_outlined,
                      title: 'Choose Sync Base',
                      subtitle:
                          'Pick the cloud-backed folder for shared library sync',
                      onTap: () => _showPlaceholderSnackBar(
                        context,
                        'Sync base selection will be wired when cloud sync lands.',
                      ),
                    ),
                    _SetupActionTile(
                      icon: Icons.sync,
                      title: 'Sync Now',
                      subtitle:
                          'Mirror the managed library to your chosen sync folder',
                      onTap: () => _showPlaceholderSnackBar(
                        context,
                        'Sync now will be connected after the commentary library service is ported.',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The original app uses this area for EPUB-first commentary setup, cloud sync base configuration, and managed-library synchronization.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupLeading(BuildContext context) {
    final inset = defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0;
    return Padding(
      padding: EdgeInsets.only(left: inset),
      child: const BackButton(),
    );
  }

  double _setupLeadingWidth() {
    return 56 + (defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0);
  }
}

class _UtilityActionButton extends StatelessWidget {
  const _UtilityActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(999);
    final style = filled
        ? FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: colorScheme.primary,
            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          );

    return filled
        ? FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}

class _SetupActionTile extends StatelessWidget {
  const _SetupActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

void _showPlaceholderSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Widget _setupLeading(BuildContext context) {
  final inset = defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0;
  return Padding(
    padding: EdgeInsets.only(left: inset),
    child: const BackButton(),
  );
}

double _setupLeadingWidth() {
  return 56 + (defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0);
}
