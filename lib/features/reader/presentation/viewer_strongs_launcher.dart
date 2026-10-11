import 'package:flutter/material.dart';

import 'viewer_strongs_page_one.dart';
import 'viewer_strongs_page_two.dart';
import 'viewer_strongs_repository.dart';

Future<void> showViewerStrongsPageOne(
  BuildContext context, {
  required String strongsId,
  required ValueChanged<int> onSelectBlockId,
  void Function(int blockId, ViewerStrongsOccurrenceViewState viewState)?
  onSelectOccurrence,
  ViewerStrongsOccurrenceViewState occurrenceViewState =
      const ViewerStrongsOccurrenceViewState(),
  bool startOnOccurrences = false,
  String? mappedPhrase,
  String? morphologyTag,
  ViewerStrongsRepository repository = const ViewerStrongsRepository(),
  Future<ViewerStrongsOccurrenceData>? occurrenceDataOverride,
  void Function(int blockId, double panelScrollOffset)? onSelectCitation,
  double initialPanelScrollOffset = 0,
}) async {
  final canonical = normalizeStrongsCanonical(strongsId);
  if (canonical == null) return;

  final openPageTwo = startOnOccurrences
      ? true
      : await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          builder: (sheetContext) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.43,
              minChildSize: 0.32,
              maxChildSize: 0.80,
              builder: (sheetContext, scrollController) => ViewerStrongsPageOne(
                strongsId: canonical,
                mappedPhrase: mappedPhrase,
                morphologyTag: morphologyTag,
                scrollController: scrollController,
                initialScrollOffset: initialPanelScrollOffset,
                onSelectCitation: onSelectCitation,
                repository: repository,
                onOpenPageTwo: () {
                  Navigator.of(sheetContext).pop(true);
                },
              ),
            );
          },
        );

  if (!context.mounted || openPageTwo != true) return;
  await showViewerStrongsPageTwo(
    context,
    strongsId: canonical,
    onSelectBlockId: onSelectBlockId,
    onSelectOccurrence: onSelectOccurrence,
    initialViewState: occurrenceViewState,
    repository: repository,
    dataOverride: occurrenceDataOverride,
  );
}

Future<void> showViewerStrongsPageTwo(
  BuildContext context, {
  required String strongsId,
  required ValueChanged<int> onSelectBlockId,
  void Function(int blockId, ViewerStrongsOccurrenceViewState viewState)?
  onSelectOccurrence,
  ViewerStrongsOccurrenceViewState initialViewState =
      const ViewerStrongsOccurrenceViewState(),
  ViewerStrongsRepository repository = const ViewerStrongsRepository(),
  Future<ViewerStrongsOccurrenceData>? dataOverride,
}) {
  final canonical = normalizeStrongsCanonical(strongsId);
  if (canonical == null) return Future<void>.value();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      return SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.92,
        child: ViewerStrongsPageTwo(
          strongsId: canonical,
          onSelectBlockId: onSelectBlockId,
          onSelectOccurrence: onSelectOccurrence,
          initialViewState: initialViewState,
          repository: repository,
          dataOverride: dataOverride,
        ),
      );
    },
  );
}
