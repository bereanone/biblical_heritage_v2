import 'package:flutter/material.dart';

import '../data/history_log_service.dart';

class ViewerHistorySheet extends StatelessWidget {
  const ViewerHistorySheet({
    super.key,
    required this.entries,
    required this.referencesByBlockId,
    required this.fontScale,
    required this.onSelectBlockId,
  });

  final List<HistoryLogEntry> entries;
  final Map<int, String> referencesByBlockId;
  final double fontScale;
  final ValueChanged<int> onSelectBlockId;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: (16 * fontScale).clamp(14.0, 22.0),
    );

    return SafeArea(
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final when = DateTime.fromMillisecondsSinceEpoch(entry.timestamp);
          final ref =
              referencesByBlockId[entry.blockId] ?? 'Block ${entry.blockId}';
          final stamp =
              '${when.month.toString().padLeft(2, '0')}/${when.day.toString().padLeft(2, '0')}/${(when.year % 100).toString().padLeft(2, '0')} ${_formatHour(when.hour)}:${when.minute.toString().padLeft(2, '0')} ${when.hour >= 12 ? 'PM' : 'AM'}';

          return ListTile(
            title: Text(
              '$ref · $stamp',
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onSelectBlockId(entry.blockId),
          );
        },
      ),
    );
  }

  String _formatHour(int hour) {
    final value = hour % 12;
    return (value == 0 ? 12 : value).toString().padLeft(2, '0');
  }
}
