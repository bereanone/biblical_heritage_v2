import 'package:flutter/material.dart';

import '../../../core/bootstrap/library_root_native.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../data/library_setup_invitation_service.dart';
import 'library_access_required_screen.dart';
import 'set_up_my_library_screen.dart';

/// Shows the one-time "Set Up My Library" invitation from the idle Entry
/// screen, if [LibrarySetupInvitationService.shouldShowInvitation] says it
/// hasn't already been resolved. Dismissing without choosing (tapping
/// outside) does not record a skip — only an explicit "Skip for Now" does
/// — and never blocks using the Bible, which remains reachable underneath
/// and after this dialog closes either way.
Future<void> maybeShowSetUpMyLibraryInvitation(BuildContext context) async {
  if (LibraryRootNative.usesAndroidDocumentTree) {
    final authorization = await LibraryRootService.instance
        .validateAndroidAuthorization(refresh: true);
    if (!authorization.isAuthorized && context.mounted) {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => const LibraryAccessRequiredScreen(),
        ),
      );
      if (!context.mounted) return;
    }
  }
  final should = await LibrarySetupInvitationService.instance
      .shouldShowInvitation();
  if (!should || !context.mounted) return;

  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Set Up My Library'),
      content: const Text(
        'Would you like to set up your library now? You can download the '
        'Ellen White writings, import a Pioneer collection, or add your '
        'own EPUB. You can always do this later from Utilities.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('skip'),
          child: const Text('Skip for Now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('setup'),
          child: const Text('Set Up My Library'),
        ),
      ],
    ),
  );

  if (choice == 'skip') {
    await LibrarySetupInvitationService.instance.markSkipped();
    return;
  }
  if (choice == 'setup' && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SetUpMyLibraryScreen()),
    );
  }
}
