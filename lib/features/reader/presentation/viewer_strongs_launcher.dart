import 'package:flutter/material.dart';

import 'viewer_strongs_page_one.dart';
import 'viewer_strongs_page_two.dart';
import 'viewer_strongs_repository.dart';

Future<void> showViewerStrongsPageOne(
  BuildContext context, {
  required String strongsId,
  required ValueChanged<int> onSelectBlockId,
}) async {
  final canonical = normalizeStrongsCanonical(strongsId);
  if (canonical == null) return;

  final openPageTwo = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.92,
            child: ViewerStrongsPageOne(
              strongsId: canonical,
              onOpenPageTwo: () {
                Navigator.of(sheetContext).pop(true);
              },
            ),
          ),
        ),
      );
    },
  );

  if (!context.mounted || openPageTwo != true) return;
  await showViewerStrongsPageTwo(
    context,
    strongsId: canonical,
    onSelectBlockId: onSelectBlockId,
  );
}

Future<void> showViewerStrongsPageTwo(
  BuildContext context, {
  required String strongsId,
  required ValueChanged<int> onSelectBlockId,
}) {
  final canonical = normalizeStrongsCanonical(strongsId);
  if (canonical == null) return Future<void>.value();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.92,
            child: ViewerStrongsPageTwo(
              strongsId: canonical,
              onSelectBlockId: onSelectBlockId,
            ),
          ),
        ),
      );
    },
  );
}
