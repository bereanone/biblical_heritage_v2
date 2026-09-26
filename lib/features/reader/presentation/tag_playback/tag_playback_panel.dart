import 'package:flutter/material.dart';

import '../tag_dialog_styles.dart';
import 'tag_playback_controller.dart';
import 'tag_playback_models.dart';
import 'tag_playback_settings_panel.dart';

/// Transport controls, position read-out and the entry list for one
/// [TagPlaybackController]. Pure presentation: it never owns the controller.
class TagPlaybackPanel extends StatefulWidget {
  const TagPlaybackPanel({
    super.key,
    required this.controller,
    this.fontScale = 1,
  });

  final TagPlaybackController controller;
  final double fontScale;

  @override
  State<TagPlaybackPanel> createState() => _TagPlaybackPanelState();
}

class _TagPlaybackPanelState extends State<TagPlaybackPanel> {
  static const double _rowExtent = 68;
  final ScrollController _scroll = ScrollController();
  int _lastRevealed = -1;
  bool _showSettings = false;

  TagPlaybackController get _c => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealCurrent() {
    final index = _c.currentIndex;
    if (index == _lastRevealed) return;
    _lastRevealed = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final target =
          (index * _rowExtent - position.viewportDimension / 2 + _rowExtent / 2)
              .clamp(0.0, position.maxScrollExtent);
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _statusText() => switch (_c.status) {
    TagPlaybackStatus.idle => 'Ready',
    TagPlaybackStatus.loading => 'Preparing audio…',
    TagPlaybackStatus.playing => 'Playing',
    TagPlaybackStatus.paused => 'Paused',
    TagPlaybackStatus.finished => 'Finished',
    TagPlaybackStatus.error => _c.errorMessage ?? 'Playback stopped',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        _revealCurrent();
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _position(theme),
            _transport(theme),
            _toggles(theme),
            if (_showSettings)
              TagPlaybackSettingsPanel(
                controller: _c,
                fontScale: widget.fontScale,
              ),
            const Divider(height: 1),
            Expanded(child: _list(theme)),
          ],
        );
      },
    );
  }

  Widget _position(ThemeData theme) {
    if (_c.entryCount == 0) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'This tag has no entries to read.',
          key: const Key('tag_playback_empty'),
          textAlign: TextAlign.center,
          style: TagDialogStyles.bodyTextStyle(theme, widget.fontScale),
        ),
      );
    }
    final item = _c.currentItem;
    final failed = _c.status == TagPlaybackStatus.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Entry ${_c.currentIndex + 1} of ${_c.entryCount}',
            key: const Key('tag_playback_position'),
            style: TagDialogStyles.labelTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.body(theme),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item?.label ?? '',
            key: const Key('tag_playback_reference'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TagDialogStyles.titleTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.title(theme),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (_c.status == TagPlaybackStatus.loading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Expanded(
                child: Text(
                  _statusText(),
                  key: const Key('tag_playback_status'),
                  style: TagDialogStyles.bodyTextStyle(
                    theme,
                    widget.fontScale,
                    color: failed
                        ? theme.colorScheme.error
                        : TagDialogStyles.body(theme),
                  ),
                ),
              ),
            ],
          ),
          if (!_c.canPlay)
            Text(
              'Nothing to read in this mode.',
              key: const Key('tag_playback_nothing'),
              style: TagDialogStyles.bodyTextStyle(theme, widget.fontScale),
            ),
        ],
      ),
    );
  }

  Widget _transport(ThemeData theme) {
    final canPlay = _c.canPlay;
    final busy =
        _c.status == TagPlaybackStatus.playing ||
        _c.status == TagPlaybackStatus.loading;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('tag_playback_previous'),
            tooltip: 'Previous entry',
            iconSize: 32,
            onPressed: canPlay ? _c.previous : null,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            key: const Key('tag_playback_play_pause'),
            tooltip: busy ? 'Pause' : 'Play',
            iconSize: 40,
            onPressed: canPlay ? _c.togglePlayPause : null,
            icon: Icon(busy ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: const Key('tag_playback_stop'),
            tooltip: 'Stop',
            iconSize: 32,
            onPressed: canPlay ? _c.stop : null,
            icon: const Icon(Icons.stop_rounded),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: const Key('tag_playback_next'),
            tooltip: 'Next entry',
            iconSize: 32,
            onPressed: canPlay ? _c.next : null,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
    );
  }

  Widget _toggles(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          IconButton(
            key: const Key('tag_playback_loop'),
            tooltip: _c.loop ? 'Loop on: repeat the tag' : 'Loop off: play once',
            isSelected: _c.loop,
            style: IconButton.styleFrom(
              backgroundColor: _c.loop
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: _c.loop
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
            ),
            icon: const Icon(Icons.repeat_rounded),
            selectedIcon: const Icon(Icons.repeat_on_rounded),
            onPressed: () => _c.setLoop(!_c.loop),
          ),
          IconButton(
            key: const Key('tag_playback_settings'),
            tooltip: 'Playback settings',
            isSelected: _showSettings,
            onPressed: () => setState(() => _showSettings = !_showSettings),
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
    );
  }

  Widget _list(ThemeData theme) {
    final current = _c.currentIndex;
    final active = _c.status != TagPlaybackStatus.idle;
    final body = TagDialogStyles.bodyTextStyle(theme, widget.fontScale);
    return ListView.builder(
      controller: _scroll,
      itemExtent: _rowExtent,
      itemCount: _c.entryCount,
      itemBuilder: (context, index) {
        final item = _c.items[index];
        final isCurrent = index == current;
        final silent = item
            .clipsFor(
              includeNotes: _c.includeNotes,
              speakReference: _c.speakReference,
            )
            .isEmpty;
        return Container(
          key: Key('tag_playback_row_$index'),
          decoration: BoxDecoration(
            color: isCurrent
                ? TagDialogStyles.accent(theme).withValues(alpha: 0.16)
                : null,
            border: Border(
              left: BorderSide(
                width: 4,
                color: isCurrent && active
                    ? TagDialogStyles.accent(theme)
                    : Colors.transparent,
              ),
            ),
          ),
          child: ListTile(
            dense: true,
            selected: isCurrent,
            onTap: silent ? null : () => _c.playFromEntry(index),
            leading: SizedBox(
              width: 28,
              child: isCurrent && _c.isPlaying
                  ? const Icon(Icons.volume_up_rounded, size: 20)
                  : Text('${index + 1}', style: body),
            ),
            title: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body.copyWith(
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            subtitle: Text(
              silent
                  ? 'Nothing to read'
                  : (item.hasNote && _c.includeNotes
                        ? '${item.preview}  ·  + note'
                        : item.preview),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body.copyWith(
                fontSize: (body.fontSize ?? 15) - 1,
                fontStyle: silent ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}
