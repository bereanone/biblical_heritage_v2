import 'package:flutter/material.dart';

import '../data/library_catalog_service.dart';
import '../data/library_item_availability.dart';
import '../data/library_item_retry_download_service.dart';
import 'library_unavailable_book_dialog.dart';

/// Shared gate for every route that can push `LibraryBookReaderScreen`
/// outside the primary Library shelf tap handler (search dialogs, tag
/// jumps, commentary/research cross-references, etc.), so a `needs_attention`
/// item can never reach the reader and render its placeholder body as if it
/// were a real book. Returns `true` when [item] is readable and the caller
/// may proceed to navigate; shows the existing unavailable-book dialog and
/// returns `false` otherwise.
///
/// [canRetry] uses the same single authoritative decision
/// ([libraryItemSupportsRetryDownload]) the main Library shelf already uses
/// (see `library_screen_state.dart`'s `_handleUnavailableBookSelected`), so
/// "Retry Download" is offered consistently no matter which launch path
/// (shelf tap, search, tag jump, or a commentary/cross-reference link)
/// reached this same unavailable book — previously every non-shelf path
/// hard-coded `canRetry: false`, so the same unavailable book silently lost
/// its retry option depending on how the user reached it. When the button
/// is shown and tapped, the retry actually runs here (mirroring
/// `library_screen_state.dart`'s `_retryUnavailableBookDownload`) rather
/// than only closing the dialog, so every launch path offers a retry that
/// really retries.
Future<bool> ensureLibraryItemOpenable(
  BuildContext context,
  LibraryCatalogItem item,
) async {
  final availability = libraryItemAvailability(item);
  if (availability.isAvailable) return true;
  final action = await showLibraryUnavailableBookDialog(
    context,
    item: item,
    availability: availability,
    canRetry: libraryItemSupportsRetryDownload(item),
  );
  if (!context.mounted) return false;
  if (action == LibraryUnavailableBookDialogAction.retryDownload) {
    await _retryDownloadAndNotify(context, item);
  }
  return false;
}

Future<void> _retryDownloadAndNotify(
  BuildContext context,
  LibraryCatalogItem item,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(content: Text('Retrying download for "${item.displayTitle}"…')),
  );
  final LibraryItemRetryDownloadResult result;
  try {
    result = await LibraryItemRetryDownloadService.instance.retry(
      libraryItemId: item.id,
      collectionName: item.collectionName ?? '',
      relativePath: item.relativePath,
    );
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('Retry failed: $error')));
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.succeeded
            ? '"${item.displayTitle}" is now available. Open it again to read.'
            : 'A readable edition is still not available for '
                  '"${item.displayTitle}".',
      ),
    ),
  );
}
