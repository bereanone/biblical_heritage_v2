import 'package:flutter/material.dart';

import 'bible_loop_announcement_settings.dart';

class BibleLoopControl extends StatelessWidget {
  const BibleLoopControl({
    super.key,
    required this.active,
    required this.onTap,
    required this.onLongPress,
  });

  final bool active;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: active ? 'Turn off Bible loop' : 'Start Bible loop',
      button: true,
      child: InkWell(
        key: const ValueKey('bible-audio-loop'),
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: IgnorePointer(
          child: IconButton(
            isSelected: active,
            style: IconButton.styleFrom(
              backgroundColor: active
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              foregroundColor: active
                  ? colors.onPrimaryContainer
                  : colors.onSurface,
            ),
            icon: const Icon(Icons.repeat_rounded),
            selectedIcon: const Icon(Icons.repeat_on_rounded),
            onPressed: () {},
          ),
        ),
      ),
    );
  }
}

String bibleLoopTargetLabel(
  BibleLoopUnit? unit, {
  required String bookName,
  required int chapter,
  required int verse,
}) => switch (unit) {
  BibleLoopUnit.book => 'Looping $bookName',
  BibleLoopUnit.chapter => 'Looping $bookName $chapter',
  BibleLoopUnit.verse => 'Looping $bookName $chapter:$verse',
  null => 'Loop off',
};

/// Keeps the action that starts a loop separate from its spoken-label setting.
class BibleLoopPicker extends StatefulWidget {
  const BibleLoopPicker({
    super.key,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.selectedLoop,
    required this.selectedTargetLabel,
    required this.announcements,
    required this.onAnnouncementChanged,
    this.showAnnouncements = true,
  });

  final String bookName;
  final int chapter;
  final int verse;
  final BibleLoopUnit? selectedLoop;
  final String selectedTargetLabel;
  final BibleLoopAnnouncementSettings announcements;
  final bool showAnnouncements;
  final void Function(BibleLoopUnit unit, bool enabled) onAnnouncementChanged;

  @override
  State<BibleLoopPicker> createState() => _BibleLoopPickerState();
}

class _BibleLoopPickerState extends State<BibleLoopPicker> {
  late BibleLoopAnnouncementSettings _announcements = widget.announcements;

  Widget _choice(BibleLoopUnit unit, String reference, IconData icon) {
    final title = switch (unit) {
      BibleLoopUnit.book => 'Book',
      BibleLoopUnit.chapter => 'Chapter',
      BibleLoopUnit.verse => 'Verse',
    };
    return ListTile(
      key: ValueKey('bible_loop_select_${unit.name}'),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(reference),
      trailing: widget.selectedLoop == unit
          ? const Icon(Icons.check_rounded)
          : null,
      selected: widget.selectedLoop == unit,
      onTap: () => Navigator.of(context).pop(unit),
    );
  }

  Widget _announcementChoice(BibleLoopUnit unit) {
    final title = switch (unit) {
      BibleLoopUnit.book => 'Book name',
      BibleLoopUnit.chapter => 'Chapter number',
      BibleLoopUnit.verse => 'Verse number',
    };
    return SwitchListTile.adaptive(
      key: ValueKey('bible_loop_announce_${unit.name}'),
      title: Text(title),
      value: _announcements.enabledFor(unit),
      onChanged: (enabled) {
        setState(() {
          _announcements = _announcements.withValue(unit, enabled);
        });
        widget.onAnnouncementChanged(unit, enabled);
      },
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Loop'),
            subtitle: Text(widget.selectedTargetLabel),
          ),
          _choice(
            BibleLoopUnit.verse,
            '${widget.bookName} ${widget.chapter}:${widget.verse}',
            Icons.repeat_one_rounded,
          ),
          _choice(
            BibleLoopUnit.chapter,
            '${widget.bookName} ${widget.chapter}',
            Icons.repeat_rounded,
          ),
          _choice(
            BibleLoopUnit.book,
            widget.bookName,
            Icons.menu_book_outlined,
          ),
          if (widget.showAnnouncements) ...[
            const Divider(height: 1),
            const ListTile(
              title: Text('Announce'),
              subtitle: Text('Speak labels during reading'),
            ),
            _announcementChoice(BibleLoopUnit.book),
            _announcementChoice(BibleLoopUnit.chapter),
            _announcementChoice(BibleLoopUnit.verse),
          ],
        ],
      ),
    ),
  );
}
