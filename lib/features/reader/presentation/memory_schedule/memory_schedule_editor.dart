import 'package:flutter/material.dart';
import 'memory_schedule.dart';
import '../tag_dialog_styles.dart';

Future<void> showMemoryScheduleEditor(
  BuildContext context,
  MemoryAudioTarget target, {
  required Future<void> Function() preview,
}) async {
  final appTheme = Theme.of(Navigator.of(context, rootNavigator: true).context);
  try {
    final all = await MemoryAudioScheduleStore.instance.load();
    final existing = all.where((s) => s.target.key == target.key).firstOrNull;
    if (!context.mounted) return;
    // Use the app theme for both the tag-list shortcut and player route;
    // otherwise showDialog captures the tag list's local control palette.
    await showDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: appTheme,
        child: _Editor(
          schedule: existing ?? MemoryAudioSchedule(target: target),
          preview: preview,
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the saved schedule. Your existing settings were not changed.',
          ),
        ),
      );
    }
  }
}

class _Editor extends StatefulWidget {
  const _Editor({required this.schedule, required this.preview});
  final MemoryAudioSchedule schedule;
  final Future<void> Function() preview;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late bool enabled = widget.schedule.enabled,
      intervalMode = widget.schedule.intervalMode;
  late int start = widget.schedule.startMinute,
      end = widget.schedule.endMinute,
      interval = widget.schedule.intervalMinutes;
  late Set<int> days = widget.schedule.days.toSet();
  late List<int> times = List.of(widget.schedule.times);
  bool saving = false;
  String? error;
  String clock(int m) =>
      TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);
  Future<int?> pick(int m) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  MemoryAudioSchedule get result => MemoryAudioSchedule(
    target: widget.schedule.target,
    enabled: enabled,
    days: days.toList()..sort(),
    intervalMode: intervalMode,
    startMinute: start,
    endMinute: end,
    intervalMinutes: interval,
    times: times.toSet().toList()..sort(),
    lastShown: widget.schedule.lastShown,
  );
  Future<void> save() async {
    if (days.isEmpty ||
        (intervalMode && end < start) ||
        (!intervalMode && times.isEmpty)) {
      setState(
        () => error =
            'Choose at least one day and time. End time must be after start time.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await MemoryAudioScheduleStore.instance.save(result);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Schedule was not saved. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: TagDialogStyles.card(Theme.of(context)),
    surfaceTintColor: Colors.transparent,
    titleTextStyle: TextStyle(
      color: TagDialogStyles.title(Theme.of(context)),
      fontSize: 24,
      fontWeight: FontWeight.w700,
    ),
    contentTextStyle: TextStyle(
      color: TagDialogStyles.body(Theme.of(context)),
      fontSize: 16,
      height: 1.4,
    ),
    title: Row(
      children: [
        Expanded(child: Text('Schedule · ${widget.schedule.target.label}')),
        IconButton(
          tooltip: 'Schedule instructions',
          icon: const Icon(Icons.help_outline),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (helpContext) => AlertDialog(
              backgroundColor: TagDialogStyles.card(Theme.of(helpContext)),
              surfaceTintColor: Colors.transparent,
              contentTextStyle: TextStyle(
                color: TagDialogStyles.body(Theme.of(helpContext)),
                fontSize: 16,
                height: 1.4,
              ),
              title: const Text('Schedule instructions'),
              content: const SingleChildScrollView(
                child: Text(
                  'Enable reminders and select the days you want.\n\nScheduled times: add each individual reminder time.\n\nRepeat by interval: choose minutes between reminders, a first time, and a last time. Reminders stay within that daily window.\n\nListen opens the saved list audio. Dismiss closes the reminder. Audio looping is controlled separately in the player.\n\nTest reminder previews the choices. Save keeps the schedule; Cancel leaves it unchanged.\n\nMac preview requires the app open and the Mac awake. Missed reminder times are not replayed.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(helpContext).pop(),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mac preview: reminders appear while StudyBible is open and the Mac is awake. Each reminder offers Listen or Dismiss; it never starts audio automatically.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable reminders'),
              value: enabled,
              onChanged: saving ? null : (v) => setState(() => enabled = v),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    selectedColor: Theme.of(context).colorScheme.primary,
                    backgroundColor: TagDialogStyles.surfaceHigh(
                      Theme.of(context),
                    ),
                    checkmarkColor: Theme.of(context).colorScheme.onPrimary,
                    labelStyle: TextStyle(
                      color: days.contains(d)
                          ? Theme.of(context).colorScheme.onPrimary
                          : TagDialogStyles.body(Theme.of(context)),
                      fontWeight: FontWeight.w700,
                    ),
                    label: Text(
                      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1],
                    ),
                    selected: days.contains(d),
                    onSelected: saving
                        ? null
                        : (v) => setState(() {
                            v ? days.add(d) : days.remove(d);
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Theme.of(context).colorScheme.primary
                      : TagDialogStyles.surfaceHigh(Theme.of(context)),
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Theme.of(context).colorScheme.onPrimary
                      : TagDialogStyles.body(Theme.of(context)),
                ),
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('Scheduled times')),
                ButtonSegment(value: true, label: Text('Repeat by interval')),
              ],
              selected: {intervalMode},
              onSelectionChanged: saving
                  ? null
                  : (v) => setState(() => intervalMode = v.first),
            ),
            const SizedBox(height: 12),
            if (intervalMode) ...[
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        final v = await pick(start);
                        if (v != null && mounted) setState(() => start = v);
                      },
                child: Text('First reminder: ${clock(start)}'),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        final v = await pick(end);
                        if (v != null && mounted) setState(() => end = v);
                      },
                child: Text('Last reminder: ${clock(end)}'),
              ),
              DropdownButtonFormField<int>(
                initialValue: interval,
                decoration: const InputDecoration(
                  labelText: 'Repeat reminder every',
                ),
                items:
                    [
                          5,
                          10,
                          15,
                          20,
                          30,
                          45,
                          60,
                          75,
                          90,
                          105,
                          120,
                          135,
                          150,
                          165,
                          180,
                          240,
                        ]
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text('$m minutes'),
                          ),
                        )
                        .toList(),
                onChanged: saving ? null : (v) => setState(() => interval = v!),
              ),
            ] else ...[
              Wrap(
                spacing: 6,
                children: [
                  for (final m in times)
                    InputChip(
                      label: Text(clock(m)),
                      onDeleted: saving
                          ? null
                          : () => setState(() => times.remove(m)),
                    ),
                ],
              ),
              TextButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final v = await pick(420);
                        if (v != null && mounted) {
                          setState(() {
                            if (!times.contains(v)) times.add(v);
                          });
                        }
                      },
                icon: const Icon(Icons.add),
                label: const Text('Add reminder time'),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '${result.dailyMinutes.length} reminders on each selected day. Listening uses the existing audio and loop settings.',
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : widget.preview,
        child: const Text('Test reminder'),
      ),
      TextButton(
        onPressed: saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: saving ? null : save, child: const Text('Save')),
    ],
  );
}
