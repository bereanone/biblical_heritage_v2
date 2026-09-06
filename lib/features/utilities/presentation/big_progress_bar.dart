import 'package:flutter/material.dart';

/// A large, high-contrast progress bar for long-running acquisition/indexing
/// flows. Deliberately thicker than the default [LinearProgressIndicator],
/// with a neutral track color independent of the app's accent color so the
/// filled portion stays legible against it regardless of theme.
///
/// When [value] is null (the real total isn't known yet — e.g. still
/// discovering candidate files), this deliberately does NOT fall back to
/// Flutter's default indeterminate animation, which sweeps a segment back
/// and forth and reads as "stuck" or "scanning" rather than "making
/// progress." Instead it simulates a smooth fill that eases up to ~85% and
/// holds there, so the bar always visibly grows left-to-right; once a real
/// [value] arrives it snaps straight to that.
class BigProgressBar extends StatefulWidget {
  const BigProgressBar({super.key, required this.value, this.height = 22});

  /// 0.0-1.0 for a determinate bar, or null while the total is still
  /// unknown (shows a simulated growing fill instead of spinning).
  final double? value;
  final double height;

  @override
  State<BigProgressBar> createState() => _BigProgressBarState();
}

class _BigProgressBarState extends State<BigProgressBar>
    with SingleTickerProviderStateMixin {
  static const _simulatedCeiling = 0.85;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.value == null) _controller.forward();
  }

  @override
  void didUpdateWidget(BigProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && oldWidget.value != null) {
      _controller
        ..reset()
        ..forward();
    } else if (widget.value != null && oldWidget.value == null) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget bar(double v) => ClipRRect(
      borderRadius: BorderRadius.circular(widget.height / 2),
      child: SizedBox(
        height: widget.height,
        child: LinearProgressIndicator(
          value: v,
          minHeight: widget.height,
          backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
        ),
      ),
    );

    final value = widget.value;
    if (value != null) return bar(value);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          bar(_simulatedCeiling * Curves.easeOut.transform(_controller.value)),
    );
  }
}

/// The single shared "N of Total" progress display for every indexing entry
/// point in the app (auto-indexing after a download, the standalone "Index
/// New/Changed Books" action wherever it appears, and any other manual
/// re-index trigger). Every screen that shows indexing progress renders this
/// widget instead of re-implementing its own bar/percentage text, so a fix
/// or style change here applies everywhere at once.
class IndexingProgressStatus extends StatelessWidget {
  const IndexingProgressStatus({
    super.key,
    required this.completed,
    required this.total,
    this.currentTitle,
    this.label = 'Indexing',
  });

  /// Items indexed so far.
  final int completed;

  /// Total candidate items known to need indexing; 0 while still being
  /// discovered (renders an indeterminate bar until then).
  final int total;

  /// Title of the item currently being indexed, if known.
  final String? currentTitle;

  /// Verb shown in the status lines, e.g. "Indexing".
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final double? value = total > 0
        ? (completed / total).clamp(0.0, 1.0)
        : null;
    final int? percent = value == null ? null : (value * 100).round();
    final title = currentTitle?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BigProgressBar(value: value),
        const SizedBox(height: 12),
        Text(
          percent != null ? '$percent%' : '$label…',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          total > 0 ? '$label $completed of $total' : '$label…',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (title != null && title.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Current: $title',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
