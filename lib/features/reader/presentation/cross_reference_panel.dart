import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import '../data/cross_reference_repository.dart';

class CrossReferenceListItem {
  const CrossReferenceListItem({
    required this.targetVerseId,
    required this.reference,
    required this.text,
  });

  final int targetVerseId;
  final String reference;
  final String text;
}

typedef CrossReferenceItemLoader =
    Future<List<CrossReferenceListItem>> Function(int sourceVerseId);

bool crossReferenceTapStopsAutoscroll({
  required bool tiltAutoscrollActive,
  required bool steadyAutoscrollActive,
}) => tiltAutoscrollActive || steadyAutoscrollActive;

Future<List<CrossReferenceListItem>> loadCrossReferenceItems(
  int sourceVerseId,
) async {
  final repository = CrossReferenceRepository();
  try {
    final references = await repository.forVerse(sourceVerseId);
    final verses = await StudyBibleDatabase.instance
        .loadVerseRecordsForBlockIds(
          references.map((item) => item.targetVerseId).toList(growable: false),
        );
    return [
      for (final relationship in references)
        CrossReferenceListItem(
          targetVerseId: relationship.targetVerseId,
          reference:
              verses[relationship.targetVerseId]?.reference ??
              (relationship.targetReference.trim().isEmpty
                  ? 'Reference unavailable'
                  : relationship.targetReference),
          text:
              verses[relationship.targetVerseId]?.text.trim().isNotEmpty == true
              ? verses[relationship.targetVerseId]!.text
              : 'Verse text unavailable in the selected Bible.',
        ),
    ];
  } finally {
    await repository.close();
  }
}

Future<int?> showCrossReferencePanel({
  required BuildContext context,
  required int sourceVerseId,
  required String sourceReference,
  CrossReferenceItemLoader loadItems = loadCrossReferenceItems,
}) {
  final panel = CrossReferencePanel(
    sourceVerseId: sourceVerseId,
    sourceReference: sourceReference,
    loadItems: loadItems,
    onSelect: (targetVerseId) => Navigator.of(context).pop(targetVerseId),
  );
  final platform = Theme.of(context).platform;
  final desktop =
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
  if (desktop) {
    return showDialog<int>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: panel,
        ),
      ),
    );
  }
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.82, child: panel),
  );
}

class CrossReferencePanel extends StatefulWidget {
  const CrossReferencePanel({
    super.key,
    required this.sourceVerseId,
    required this.sourceReference,
    required this.loadItems,
    required this.onSelect,
  });

  final int sourceVerseId;
  final String sourceReference;
  final CrossReferenceItemLoader loadItems;
  final ValueChanged<int> onSelect;

  @override
  State<CrossReferencePanel> createState() => _CrossReferencePanelState();
}

class _CrossReferencePanelState extends State<CrossReferencePanel> {
  late Future<List<CrossReferenceListItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.loadItems(widget.sourceVerseId);
  }

  void _retry() {
    final nextItems = widget.loadItems(widget.sourceVerseId);
    setState(() {
      _items = nextItems;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cross References', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      widget.sourceReference,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<CrossReferenceListItem>>(
            future: _items,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _PanelMessage(
                  message: 'Cross references could not be loaded.',
                  actionLabel: 'Try again',
                  onAction: _retry,
                );
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return const _PanelMessage(
                  message: 'No cross references available for this verse.',
                );
              }
              return ListView.separated(
                key: const Key('cross-reference-list'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    key: ValueKey('cross-reference-${item.targetVerseId}'),
                    title: Text(
                      item.reference,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(item.text),
                    ),
                    onTap: item.targetVerseId > 0
                        ? () => widget.onSelect(item.targetVerseId)
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
