import 'package:flutter/material.dart';

import 'viewer_strongs_page_one.dart';
import 'viewer_strongs_page_two.dart';
import 'viewer_strongs_repository.dart';

Future<void> showViewerStrongsPageOne(
  BuildContext context, {
  required String strongsId,
  List<String> alternateStrongsIds = const [],
  ValueChanged<String>? onStrongsChanged,
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
  var canonical = normalizeStrongsCanonical(strongsId);
  if (canonical == null) return;
  var selected = canonical;

  final openPageTwo = startOnOccurrences
      ? true
      : await showDialog<bool>(
          context: context,
          builder: (sheetContext) {
            return Dialog(
              clipBehavior: Clip.antiAlias,
              insetPadding: const EdgeInsets.all(20),
              child: SizedBox(
                width: 640,
                height: MediaQuery.sizeOf(sheetContext).height * 0.85,
                child: StatefulBuilder(builder: (context, setState) => Column(
                  children: [
                    if (alternateStrongsIds.length > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selected,
                          items: alternateStrongsIds.toSet().map((id) =>
                            DropdownMenuItem(value: id, child: Text('Source: $id'))).toList(),
                          onChanged: (id) {
                            if (id == null) return;
                            setState(() => selected = id);
                            onStrongsChanged?.call(id);
                          },
                        ),
                      ),
                    Expanded(child: ViewerStrongsPageOne(
                  key: ValueKey(selected),
                  strongsId: selected,
                  mappedPhrase: mappedPhrase,
                  morphologyTag: morphologyTag,
                  initialScrollOffset: initialPanelScrollOffset,
                  onSelectCitation: onSelectCitation,
                  repository: repository,
                  onOpenPageTwo: () {
                    Navigator.of(sheetContext).pop(true);
                  },
                )),
                  ],
                )),
              ),
            );
          },
        );

  if (!context.mounted || openPageTwo != true) return;
  await showViewerStrongsPageTwo(
    context,
    strongsId: selected,
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

  return showDialog<void>(
    context: context,
    builder: (sheetContext) {
      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 760,
          height: MediaQuery.sizeOf(sheetContext).height * 0.85,
          child: ViewerStrongsPageTwo(
            strongsId: canonical,
            onSelectBlockId: onSelectBlockId,
            onSelectOccurrence: onSelectOccurrence,
            initialViewState: initialViewState,
            repository: repository,
            dataOverride: dataOverride,
          ),
        ),
      );
    },
  );
}
