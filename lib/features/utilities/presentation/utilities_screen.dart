import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme_mode.dart';
import '../../library/data/library_setup_invitation_service.dart';
import '../../library/presentation/set_up_my_library_screen.dart';
import '../../library/presentation/import_pioneer_library_screen.dart';
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

  Future<void> _showBackupUserDataDialog(BuildContext context) async {
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
    await _runBackup(context);
  }

  /// Restores the one-time "Set Up My Library" invitation so it will offer
  /// itself again next time the app is idle at the Entry screen. Only ever
  /// touches the small setup-invitation preference
  /// ([LibrarySetupInvitationService.reset]) — never deletes books, clears
  /// databases, removes source-folder permissions, or alters user data.
  Future<void> _showLibrarySetupAgain(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await LibrarySetupInvitationService.instance.reset();
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Library setup will be offered again next time you open the app.',
        ),
      ),
    );
  }

  Future<void> _showRestoreBackupDialog(BuildContext context) async {
    final archivePath = await StudyBibleBackupService.instance
        .chooseBackupArchivePath();
    if (!context.mounted || archivePath == null) return;

    final inspection = await StudyBibleBackupService.instance
        .inspectBackupArchive(archivePath);
    if (!context.mounted) return;
    if (!inspection.isPass) {
      await _showReportDialog(
        context,
        title: 'Restore Backup',
        reportText: inspection.toDiagnosticText(),
      );
      return;
    }

    final restoreChoice = await showDialog<_RestoreChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore Backup'),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              'This will replace your current user data.\n\n'
              'Backups are for your own personal data and personal-use library files. '
              'You are responsible for following copyright and source-site rules. '
              'Library PDF/EPUB files should not be shared or redistributed.\n\n'
              'If the backup includes personal-use library/media files, those files will be restored too.\n\n'
              'Would you like to create a safety backup of the current user data before restoring?',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_RestoreChoice.cancel),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_RestoreChoice.restoreOnly),
            child: const Text('Restore Without Safety Backup'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_RestoreChoice.backupThenRestore),
            child: const Text('Create Safety Backup First'),
          ),
        ],
      ),
    );

    if (!context.mounted ||
        restoreChoice == null ||
        restoreChoice == _RestoreChoice.cancel) {
      return;
    }

    final restoreResult = await StudyBibleBackupService.instance
        .restoreBackupArchive(
          archivePath,
          createSafetyBackup: restoreChoice == _RestoreChoice.backupThenRestore,
        );
    if (!context.mounted) return;
    await _showReportDialog(
      context,
      title: 'Restore Backup',
      reportText: restoreResult.toDiagnosticText(),
    );
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
        SnackBar(content: Text('Could not build the storage report: $error')),
      );
    }
  }

  Future<void> _runBackup(BuildContext context) async {
    try {
      final result = await StudyBibleBackupService.instance.createBackup();
      if (!context.mounted) return;
      final reportText = result == null
          ? 'Backup was cancelled.'
          : [
              'Backup complete.',
              'Saved to: ${result.backupPath}',
              'Included files:',
              ...result.includedFiles.map((file) => '  $file'),
            ].join('\n');
      await _showReportDialog(
        context,
        title: 'Backup User Data',
        reportText: reportText,
      );
    } catch (error) {
      if (!context.mounted) return;
      await _showReportDialog(
        context,
        title: 'Backup User Data',
        reportText: 'Backup failed: ${_friendlyBackupError(error)}',
      );
    }
  }

  String _friendlyBackupError(Object error) {
    final text = error.toString();
    return text.startsWith('StateError: ')
        ? text.substring('StateError: '.length)
        : text;
  }

  Future<void> _showReportDialog(
    BuildContext context, {
    required String title,
    required String reportText,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(child: SelectableText(reportText)),
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
              colors: _utilitiesBackgroundGradient(theme.colorScheme),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isTwoColumn =
                  constraints.maxWidth >= _wideUtilitiesBreakpoint;
              final horizontalPadding = isTwoColumn ? 32.0 : 20.0;
              final contentWidth = isTwoColumn
                  ? math.min(constraints.maxWidth, _wideUtilitiesMaxWidth)
                  : constraints.maxWidth;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  14,
                  horizontalPadding,
                  28,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Setup and sharing tools for Biblical Heritage #StudyBible.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        Card(
                          key: const Key('utilities-set-up-my-library'),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SetUpMyLibraryScreen(),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.auto_stories_outlined,
                                    size: 32,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Set Up My Library',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Download books, import a Pioneer '
                                          'collection, or add your own EPUB.',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (isTwoColumn)
                          _UtilitiesTwoColumnDashboard(
                            leftSections: [
                              _UtilitiesSectionCard(
                                key: const Key('utilities-section-app-tools'),
                                title: 'App Tools',
                                helperText:
                                    'Manage common app settings and protect your personal data.',
                                actions: [
                                  _UtilityActionButton(
                                    label: 'Backup User Data',
                                    icon: Icons.cloud,
                                    filled: true,
                                    onPressed: () =>
                                        _showBackupUserDataDialog(context),
                                  ),
                                  _UtilityActionButton(
                                    label: 'Restore Backup',
                                    icon: Icons.restore,
                                    filled: false,
                                    onPressed: () =>
                                        _showRestoreBackupDialog(context),
                                  ),
                                  _UtilityActionButton(
                                    label: 'Show Library Setup Again',
                                    icon: Icons.replay_outlined,
                                    filled: false,
                                    onPressed: () =>
                                        _showLibrarySetupAgain(context),
                                  ),
                                ],
                              ),
                              _UtilitiesSectionCard(
                                key: const Key('utilities-section-elibrary'),
                                title: 'Existing eLibrary Tools (Advanced)',
                                helperText:
                                    'Technical tools for storage, downloads, imports, and indexing. Most people should use Set Up My Library above instead.',
                                actions: [
                                  _UtilityActionButton(
                                    label: 'eLibrary Setup',
                                    icon: Icons.library_books_outlined,
                                    filled: true,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const ELibrarySetupScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _UtilityActionButton(
                                    label: 'Download Books',
                                    icon: Icons.download_rounded,
                                    filled: false,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const ELibraryDownloadScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _UtilityActionButton(
                                    label: 'Pioneer Library',
                                    icon: Icons.menu_book_outlined,
                                    filled: false,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const ImportPioneerLibraryScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _UtilityActionButton(
                                    label: 'Library Storage',
                                    icon: Icons.library_books_outlined,
                                    filled: false,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const LibraryRootSetupScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _UtilityActionButton(
                                    label: 'Storage & Index Report',
                                    icon: Icons.storage_rounded,
                                    filled: false,
                                    onPressed: () =>
                                        _showStorageAndIndexReport(context),
                                  ),
                                ],
                              ),
                            ],
                            rightSections: [
                              _UtilitiesSectionCard(
                                key: const Key(
                                  'utilities-section-commentary-sharing',
                                ),
                                title: 'Commentary & Sharing',
                                helperText:
                                    'Learn how commentary blocks work and share them with others.',
                                actions: [
                                  _UtilityActionButton(
                                    label: 'Commentary Instructions',
                                    icon: Icons.help_outline,
                                    filled: false,
                                    onPressed: () =>
                                        _showCommentaryInstructionsDialog(
                                          context,
                                        ),
                                  ),
                                  _UtilityActionButton(
                                    label: 'Community Links',
                                    icon: Icons.public,
                                    filled: false,
                                    onPressed: () =>
                                        _showCommunityLinksDialog(context),
                                  ),
                                ],
                              ),
                              _UtilitiesSectionCard(
                                key: const Key('utilities-section-support'),
                                title: 'Support & More',
                                helperText:
                                    'Support the project and open additional study tools.',
                                actions: [
                                  _UtilityActionButton(
                                    label: 'Support Biblical Heritage',
                                    icon: Icons.volunteer_activism_outlined,
                                    filled: true,
                                    onPressed: () =>
                                        _showSupportDialog(context),
                                  ),
                                  _UtilityActionButton(
                                    label: 'Open Bible Explorer',
                                    icon: Icons.menu_book,
                                    filled: false,
                                    onPressed: () =>
                                        _openBibleExplorer(context),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _UtilitiesSectionCard(
                                key: const Key('utilities-section-app-tools'),
                                title: 'App Tools',
                                helperText:
                                    'Manage common app settings and protect your personal data.',
                                actions: [
                                  _UtilityActionButton(
                                    label: 'Backup User Data',
                                    icon: Icons.cloud,
                                    filled: true,
                                    onPressed: () =>
                                        _showBackupUserDataDialog(context),
                                  ),
                                  _UtilityActionButton(
                                    label: 'Restore Backup',
                                    icon: Icons.restore,
                                    filled: false,
                                    onPressed: () =>
                                        _showRestoreBackupDialog(context),
                                  ),
                                  _UtilityActionButton(
                                    label: 'Show Library Setup Again',
                                    icon: Icons.replay_outlined,
                                    filled: false,
                                    onPressed: () =>
                                        _showLibrarySetupAgain(context),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _UtilitiesSectionCard(
                                key: const Key('utilities-section-elibrary'),
                                title: 'Existing eLibrary Tools (Advanced)',
                                helperText:
                                    'Technical tools for storage, downloads, imports, and indexing. Most people should use Set Up My Library above instead.',
                                actions: [
                                  _UtilityActionButton(
                                    label: 'eLibrary Setup',
                                    icon: Icons.library_books_outlined,
                                    filled: true,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const ELibrarySetupScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _UtilityActionButton(
                                    label: 'Download Books',
                                    icon: Icons.download_rounded,
                                    filled: false,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const ELibraryDownloadScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _UtilityActionButton(
                                    label: 'Pioneer Library',
                                    icon: Icons.menu_book_outlined,
                                    filled: false,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const ImportPioneerLibraryScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _UtilityActionButton(
                                    label: 'Library Storage',
                                    icon: Icons.library_books_outlined,
                                    filled: false,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const LibraryRootSetupScreen(),
                                        ),
                                      );
                                    },
                                  ),
                                  _UtilityActionButton(
                                    label: 'Storage & Index Report',
                                    icon: Icons.storage_rounded,
                                    filled: false,
                                    onPressed: () =>
                                        _showStorageAndIndexReport(context),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _UtilitiesSectionCard(
                                key: const Key(
                                  'utilities-section-commentary-sharing',
                                ),
                                title: 'Commentary & Sharing',
                                helperText:
                                    'Learn how commentary blocks work and share them with others.',
                                actions: [
                                  _UtilityActionButton(
                                    label: 'Commentary Instructions',
                                    icon: Icons.help_outline,
                                    filled: false,
                                    onPressed: () =>
                                        _showCommentaryInstructionsDialog(
                                          context,
                                        ),
                                  ),
                                  _UtilityActionButton(
                                    label: 'Community Links',
                                    icon: Icons.public,
                                    filled: false,
                                    onPressed: () =>
                                        _showCommunityLinksDialog(context),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _UtilitiesSectionCard(
                                key: const Key('utilities-section-support'),
                                title: 'Support & More',
                                helperText:
                                    'Support the project and open additional study tools.',
                                actions: [
                                  _UtilityActionButton(
                                    label: 'Support Biblical Heritage',
                                    icon: Icons.volunteer_activism_outlined,
                                    filled: true,
                                    onPressed: () =>
                                        _showSupportDialog(context),
                                  ),
                                  _UtilityActionButton(
                                    label: 'Open Bible Explorer',
                                    icon: Icons.menu_book,
                                    filled: false,
                                    onPressed: () =>
                                        _openBibleExplorer(context),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
    final buttonFill = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF59E0B)
        : const Color(0xFFD97706);
    final style = filled
        ? FilledButton.styleFrom(
            backgroundColor: buttonFill,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            alignment: Alignment.centerLeft,
          )
        : OutlinedButton.styleFrom(
            foregroundColor: colorScheme.primary,
            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            alignment: Alignment.centerLeft,
          );

    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 18),
              label: Text(label, maxLines: 2),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 18),
              label: Text(label, maxLines: 2),
            ),
    );
  }
}

class _UtilitiesSectionCard extends StatelessWidget {
  const _UtilitiesSectionCard({
    super.key,
    required this.title,
    required this.helperText,
    required this.actions,
  });

  final String title;
  final String helperText;
  final List<_UtilityActionButton> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              helperText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns =
                    constraints.maxWidth >= _buttonGridBreakpoint;
                final buttonSpacing = 12.0;
                final columns = useTwoColumns ? 2 : 1;
                final buttonWidth = useTwoColumns
                    ? (constraints.maxWidth - buttonSpacing) / 2
                    : constraints.maxWidth;

                if (columns == 1) {
                  return Column(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        SizedBox(width: buttonWidth, child: actions[i]),
                        if (i != actions.length - 1) const SizedBox(height: 12),
                      ],
                    ],
                  );
                }

                final rows = <Widget>[];
                for (var i = 0; i < actions.length; i += 2) {
                  final first = actions[i];
                  final second = i + 1 < actions.length ? actions[i + 1] : null;
                  rows.add(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: buttonWidth, child: first),
                        if (second != null) ...[
                          const SizedBox(width: 12),
                          SizedBox(width: buttonWidth, child: second),
                        ],
                      ],
                    ),
                  );
                  if (i + 2 < actions.length) {
                    rows.add(const SizedBox(height: 12));
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _UtilitiesTwoColumnDashboard extends StatelessWidget {
  const _UtilitiesTwoColumnDashboard({
    required this.leftSections,
    required this.rightSections,
  });

  final List<Widget> leftSections;
  final List<Widget> rightSections;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < leftSections.length; i++) ...[
                leftSections[i],
                if (i != leftSections.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rightSections.length; i++) ...[
                rightSections[i],
                if (i != rightSections.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

const double _wideUtilitiesBreakpoint = 900;
const double _wideUtilitiesMaxWidth = 1280;
const double _buttonGridBreakpoint = 520;

List<Color> _utilitiesBackgroundGradient(ColorScheme colorScheme) {
  return [
    colorScheme.surface,
    colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
    colorScheme.surface,
  ];
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

enum _RestoreChoice { cancel, restoreOnly, backupThenRestore }

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
