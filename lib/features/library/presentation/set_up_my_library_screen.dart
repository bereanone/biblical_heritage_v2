import 'package:flutter/material.dart';

import '../data/library_setup_invitation_service.dart';
import 'add_my_own_epub_screen.dart';
import 'download_ellen_white_library_screen.dart';
import 'import_pioneer_library_screen.dart';

/// The single, plain-language entry point for getting books into the
/// library. Deliberately says nothing about Library Root, EPUB structure,
/// indexing, canonicalization, generations, or source types — those stay
/// internal to the Phase 1 orchestration layer this screen calls into.
class SetUpMyLibraryScreen extends StatelessWidget {
  const SetUpMyLibraryScreen({
    super.key,
    this.onExistingToolsRequested,
    this.dismissible = true,
  });

  /// Optional link to the existing technical screens (Utilities), shown so
  /// nothing is deleted or hidden without a path back to it.
  final VoidCallback? onExistingToolsRequested;

  /// When true, "Skip for Now" and the back button both close this screen.
  /// When opened later from Utilities (setup already resolved once), this
  /// still works the same way — reopening never re-shows the first-run
  /// invitation logic, it just lets the user run a flow again.
  final bool dismissible;

  Future<void> _skipForNow(BuildContext context) async {
    await LibrarySetupInvitationService.instance.markSkipped();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Up My Library')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;
            final choices = <_SetupChoice>[
              _SetupChoice(
                icon: Icons.cloud_download_outlined,
                title: 'Download Ellen White Library',
                subtitle: 'Get the official writings, ready to read.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DownloadEllenWhiteLibraryScreen(),
                  ),
                ),
              ),
              _SetupChoice(
                icon: Icons.collections_bookmark_outlined,
                title: 'Pioneer Library',
                subtitle:
                    'Bring in a Pioneer collection or book you already have.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ImportPioneerLibraryScreen(),
                  ),
                ),
              ),
              _SetupChoice(
                icon: Icons.menu_book_outlined,
                title: 'Add My Own EPUB',
                subtitle: 'Choose a single EPUB file from this device.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AddMyOwnEpubScreen(),
                  ),
                ),
              ),
              _SetupChoice(
                icon: Icons.skip_next_outlined,
                title: 'Skip for Now',
                subtitle: 'You can always come back to this later.',
                onTap: () => _skipForNow(context),
              ),
            ];

            final content = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: wide
                  ? GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      childAspectRatio: 2.6,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      children: choices,
                    )
                  : Column(
                      children: [
                        for (final choice in choices) ...[
                          choice,
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Text(
                        'Choose how you would like to get books into your '
                        'library. You can always add more later.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    content,
                    if (onExistingToolsRequested != null) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: TextButton(
                          onPressed: onExistingToolsRequested,
                          child: const Text('Existing Setup Tools'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SetupChoice extends StatelessWidget {
  const _SetupChoice({
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
