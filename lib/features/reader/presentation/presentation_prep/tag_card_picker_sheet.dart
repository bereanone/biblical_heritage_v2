import 'package:flutter/material.dart';

import '../../../../core/bootstrap/library_root_service.dart';
import '../../data/tags/unified_tag_models.dart';
import 'tag_card_picker_item_tile.dart';

Future<UnifiedTagChainItem?> showTagCardPickerSheet(
  BuildContext context, {
  required List<UnifiedTagChainItem> items,
  required String zoneLabel,
}) {
  return showModalBottomSheet<UnifiedTagChainItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _TagCardPickerSheet(
        items: items,
        zoneLabel: zoneLabel,
      );
    },
  );
}

class _TagCardPickerSheet extends StatefulWidget {
  const _TagCardPickerSheet({
    required this.items,
    required this.zoneLabel,
  });

  final List<UnifiedTagChainItem> items;
  final String zoneLabel;

  @override
  State<_TagCardPickerSheet> createState() => _TagCardPickerSheetState();
}

class _TagCardPickerSheetState extends State<_TagCardPickerSheet> {
  String? _mediaRootPath;

  @override
  void initState() {
    super.initState();
    _loadMediaRootPath();
  }

  Future<void> _loadMediaRootPath() async {
    final rootPath =
        await LibraryRootService.instance.accessibleLibraryRootPath();
    if (!mounted) return;
    setState(() {
      _mediaRootPath = rootPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final zoneLabel = widget.zoneLabel;
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 20,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.84,
            minChildSize: 0.52,
            maxChildSize: 0.96,
            builder: (context, scrollController) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Choose Card',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Select a card to place in $zoneLabel.',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${items.length} available card${items.length == 1 ? '' : 's'}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.outline,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Cancel',
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'No available cards right now.',
                                style: theme.textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: items.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return TagCardPickerItemTile(
                                item: item,
                                mediaRootPath: _mediaRootPath,
                                onTap: () {
                                  Navigator.of(context).pop(item);
                                },
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
