import 'package:flutter/material.dart';

class ViewerTopicGraphItem {
  const ViewerTopicGraphItem({
    required this.id,
    required this.label,
    required this.count,
    required this.color,
  });

  final int id;
  final String label;
  final int count;
  final Color color;
}

class ViewerTopicSummaryBar extends StatelessWidget {
  const ViewerTopicSummaryBar({
    super.key,
    required this.total,
    required this.onClose,
    required this.fontScale,
    required this.isFiltered,
    required this.onReset,
  });

  final int total;
  final VoidCallback onClose;
  final double fontScale;
  final bool isFiltered;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleFontSize = (13.0 * fontScale).clamp(12.0, 20.0);
    final rowHeight = resolvedViewerTopicSummaryBarHeight(fontScale);
    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          const SizedBox(width: 6),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Topics · $total',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: titleFontSize,
                ),
              ),
            ),
          ),
          if (isFiltered)
            Flexible(
              fit: FlexFit.loose,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: FilledButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.refresh, size: 15),
                  label: Text(
                    'All Topics',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: (12.0 * fontScale).clamp(11.0, 18.0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minHeight: 24, minWidth: 24),
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class ViewerTopicOverlayGraphArea extends StatelessWidget {
  const ViewerTopicOverlayGraphArea({
    super.key,
    required this.sectionItems,
    required this.selectedBookItems,
    required this.sectionSelected,
    required this.selectedSectionLabel,
    required this.onTapSection,
    required this.onTapBook,
    required this.onBackToSections,
    required this.fontScale,
    required this.maxHeight,
  });

  final List<ViewerTopicGraphItem> sectionItems;
  final List<ViewerTopicGraphItem> selectedBookItems;
  final bool sectionSelected;
  final String? selectedSectionLabel;
  final ValueChanged<int> onTapSection;
  final ValueChanged<int> onTapBook;
  final VoidCallback onBackToSections;
  final double fontScale;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (sectionItems.isEmpty) return const SizedBox.shrink();
    final metrics = _resolvedGraphMetrics(context, fontScale);
    final sectionRows = sectionItems.length.toDouble();
    if (!sectionSelected || selectedBookItems.isEmpty) {
      final rowHeight = _fitRowHeightForMax(
        metrics.rowHeight,
        (maxHeight - 2.0).clamp(0.0, maxHeight),
        sectionRows,
      );
      final graphFontSize = _scaledFontSizeForRow(
        metrics.fontSize,
        metrics.rowHeight,
        rowHeight,
      );
      return ViewerTopicGraphPanel(
        items: sectionItems,
        onTap: onTapSection,
        fontScale: fontScale,
        customRowHeight: rowHeight,
        customFontSize: graphFontSize,
      );
    }

    final bookRows = selectedBookItems.length.toDouble();
    final backRowHeight = (metrics.rowHeight + 2).clamp(26.0, 36.0);
    final availableGraphHeight = (maxHeight - backRowHeight - 4.0).clamp(
      0.0,
      maxHeight,
    );
    final rowHeight = _fitRowHeightForMax(
      metrics.rowHeight,
      availableGraphHeight,
      bookRows,
    );
    final graphFontSize = _scaledFontSizeForRow(
      metrics.fontSize,
      metrics.rowHeight,
      rowHeight,
    );

    return SizedBox(
      width: double.infinity,
      height: backRowHeight + 4.0 + _rowsExtent(rowHeight, bookRows),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onBackToSections,
              child: SizedBox(
                height: backRowHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_back, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        selectedSectionLabel == null
                            ? 'Back to sections'
                            : '${selectedSectionLabel!} books',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          ViewerTopicGraphPanel(
            items: selectedBookItems,
            onTap: onTapBook,
            fontScale: fontScale,
            customRowHeight: rowHeight,
            customFontSize: graphFontSize,
          ),
        ],
      ),
    );
  }
}

class ViewerTopicGraphPanel extends StatelessWidget {
  const ViewerTopicGraphPanel({
    super.key,
    required this.items,
    required this.onTap,
    required this.fontScale,
    this.customRowHeight,
    this.customFontSize,
  });

  final List<ViewerTopicGraphItem> items;
  final ValueChanged<int> onTap;
  final double fontScale;
  final double? customRowHeight;
  final double? customFontSize;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final metrics = _resolvedGraphMetrics(context, fontScale);
    final baseStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final graphFontSize = customFontSize ?? metrics.fontSize;
    final rowHeight = customRowHeight ?? metrics.rowHeight;
    final textLineHeight = graphFontSize <= 0
        ? 1.0
        : (rowHeight / graphFontSize).clamp(0.92, 1.15);
    final labelStyle = baseStyle.copyWith(
      fontSize: graphFontSize,
      height: textLineHeight,
    );
    final countStyle = labelStyle.copyWith(
      color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
    );
    final maxCount = items.fold(1, (m, i) => i.count > m ? i.count : m);
    final panelHeight = _rowsExtent(rowHeight, items.length.toDouble());

    return SizedBox(
      width: double.infinity,
      height: panelHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onTap(item.id),
                child: SizedBox(
                  width: double.infinity,
                  height: rowHeight,
                  child: LayoutBuilder(
                    builder: (context, rowConstraints) {
                      const gap = 4.0;
                      const edge = 4.0;
                      final usable =
                          (rowConstraints.maxWidth - ((edge * 2) + (gap * 2)))
                              .clamp(0.0, rowConstraints.maxWidth);
                      final labelWidth = (usable * 0.44).floorToDouble();
                      final barWidth = (usable * 0.36).floorToDouble();
                      final countWidth = (usable - labelWidth - barWidth).clamp(
                        0.0,
                        usable,
                      );
                      final fillWidth = barWidth * (item.count / maxCount);
                      final barHeightPreferred = (graphFontSize * 0.55).clamp(
                        1.0,
                        13.0,
                      );
                      final barHeight = (rowHeight - 2.0).clamp(
                        1.0,
                        barHeightPreferred,
                      );

                      return Row(
                        children: [
                          const SizedBox(width: edge),
                          SizedBox(
                            width: labelWidth,
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: labelStyle,
                            ),
                          ),
                          const SizedBox(width: gap),
                          SizedBox(
                            width: barWidth,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                height: barHeight,
                                child: Stack(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: item.color.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    Container(
                                      width: fillWidth,
                                      decoration: BoxDecoration(
                                        color: item.color.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: gap),
                          SizedBox(
                            width: countWidth,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${item.count}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: countStyle,
                              ),
                            ),
                          ),
                          const SizedBox(width: edge),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GraphMetrics {
  const _GraphMetrics({required this.fontSize, required this.rowHeight});

  final double fontSize;
  final double rowHeight;
}

_GraphMetrics _resolvedGraphMetrics(BuildContext context, double fontScale) {
  final baseStyle = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
  final graphFontSize = ((baseStyle.fontSize ?? 14.0) * fontScale * 0.95).clamp(
    13.0,
    21.0,
  );
  final rowHeight = (graphFontSize * 1.45).clamp(24.0, 34.0);
  return _GraphMetrics(fontSize: graphFontSize, rowHeight: rowHeight);
}

double resolvedViewerTopicSummaryBarHeight(double fontScale) {
  final titleFontSize = (13.0 * fontScale).clamp(12.0, 20.0);
  return (titleFontSize * 2.1).clamp(34.0, 52.0);
}

double _fitRowHeightForMax(
  double preferredRowHeight,
  double maxHeight,
  double effectiveRows,
) {
  if (effectiveRows <= 0 || maxHeight <= 0) return preferredRowHeight;
  final fit = maxHeight.floorToDouble() / effectiveRows;
  return fit.clamp(0.0, preferredRowHeight);
}

double _rowsExtent(double rowHeight, double rows) {
  return (rowHeight * rows).ceilToDouble();
}

double _scaledFontSizeForRow(
  double preferredFontSize,
  double preferredRowHeight,
  double actualRowHeight,
) {
  if (preferredRowHeight <= 0) return preferredFontSize;
  final scaled = preferredFontSize * (actualRowHeight / preferredRowHeight);
  final maxByRow = (actualRowHeight / 1.15).clamp(0.0, preferredFontSize);
  return scaled.clamp(0.0, maxByRow);
}
