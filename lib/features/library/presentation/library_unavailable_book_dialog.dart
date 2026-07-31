import 'package:flutter/material.dart';

import '../data/library_catalog_service.dart';
import '../data/library_item_availability.dart';

enum LibraryUnavailableBookDialogAction { retryDownload, dismissed }

/// Shown instead of opening the reader for a book
/// [libraryItemAvailability] has flagged unavailable, so tapping it explains
/// why a readable copy isn't available yet rather than opening an empty
/// reader. The `library_items` row, its cover, and its title are never
/// touched by this — it is a read-only presentation of existing status.
Future<LibraryUnavailableBookDialogAction> showLibraryUnavailableBookDialog(
  BuildContext context, {
  required LibraryCatalogItem item,
  required LibraryItemAvailability availability,
  required bool canRetry,
}) async {
  final action = await showDialog<LibraryUnavailableBookDialogAction>(
    context: context,
    builder: (context) => _LibraryUnavailableBookDialog(
      item: item,
      availability: availability,
      canRetry: canRetry,
    ),
  );
  return action ?? LibraryUnavailableBookDialogAction.dismissed;
}

class _LibraryUnavailableBookDialog extends StatelessWidget {
  const _LibraryUnavailableBookDialog({
    required this.item,
    required this.availability,
    required this.canRetry,
  });

  final LibraryCatalogItem item;
  final LibraryItemAvailability availability;
  final bool canRetry;

  String get _headline {
    switch (availability.category) {
      case LibraryItemUnavailableCategory.sourceHasNoReadableEdition:
        return 'No Readable Copy Available';
      case LibraryItemUnavailableCategory.downloadFailedValidation:
        return 'Download Needs to Be Retried';
      case LibraryItemUnavailableCategory.unknown:
      case null:
        return 'Book Unavailable';
    }
  }

  String get _explanation {
    final title = item.displayTitle;
    switch (availability.category) {
      case LibraryItemUnavailableCategory.sourceHasNoReadableEdition:
        return 'The source does not currently provide a complete, readable '
            'EPUB for "$title" — only a placeholder/teaser package. Your '
            'library entry and cover are kept, and this will resolve '
            'automatically if a full edition becomes available.';
      case LibraryItemUnavailableCategory.downloadFailedValidation:
        return 'The downloaded file for "$title" failed validation, most '
            'likely from an interrupted or corrupted transfer. Retrying '
            'the download should fix this.';
      case LibraryItemUnavailableCategory.unknown:
      case null:
        return 'A readable EPUB is not currently available for "$title" '
            'from the source.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.cloud_off_outlined),
      title: Text(_headline),
      content: Text(_explanation),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(LibraryUnavailableBookDialogAction.dismissed),
          child: const Text('Close'),
        ),
        if (canRetry)
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(LibraryUnavailableBookDialogAction.retryDownload),
            child: const Text('Retry Download'),
          ),
      ],
    );
  }
}
