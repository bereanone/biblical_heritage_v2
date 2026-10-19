import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/theme/app_settings_service.dart';

class MemoryAudioTarget {
  const MemoryAudioTarget({
    required this.label,
    this.tag,
    this.category,
    this.isDollar = false,
    this.memoryId,
  });
  final String label;
  final String? tag;
  final String? category;
  final bool isDollar;
  final int? memoryId;
  String get key => memoryId != null
      ? 'memory:$memoryId'
      : '${isDollar ? 'dollar' : 'hash'}:$tag:${category ?? ''}';
  Map<String, Object?> toJson() => {
    'label': label,
    'tag': tag,
    'category': category,
    'dollar': isDollar,
    'memory': memoryId,
  };
  factory MemoryAudioTarget.fromJson(Map<String, dynamic> j) =>
      MemoryAudioTarget(
        label: j['label'] as String,
        tag: j['tag'] as String?,
        category: j['category'] as String?,
        isDollar: j['dollar'] == true,
        memoryId: j['memory'] as int?,
      );
}

class MemoryAudioSchedule {
  const MemoryAudioSchedule({
    required this.target,
    this.enabled = false,
    this.days = const [1, 2, 3, 4, 5, 6, 7],
    this.intervalMode = false,
    this.startMinute = 420,
    this.endMinute = 1260,
    this.intervalMinutes = 120,
    this.times = const [420],
    this.lastShown,
  });
  final MemoryAudioTarget target;
  final bool enabled;
  final List<int> days;
  final bool intervalMode;
  final int startMinute, endMinute, intervalMinutes;
  final List<int> times;
  final String? lastShown;
  List<int> get dailyMinutes {
    if (!intervalMode) return times.toSet().toList()..sort();
    if (intervalMinutes <= 0 || startMinute > endMinute) return const [];
    return [for (var m = startMinute; m <= endMinute; m += intervalMinutes) m];
  }

  String? occurrence(DateTime now) {
    final minute = now.hour * 60 + now.minute;
    if (!enabled ||
        !days.contains(now.weekday) ||
        !dailyMinutes.contains(minute)) {
      return null;
    }
    final stamp = '${now.year}-${now.month}-${now.day}:$minute';
    return stamp == lastShown ? null : stamp;
  }

  MemoryAudioSchedule marked(String stamp) => MemoryAudioSchedule(
    target: target,
    enabled: enabled,
    days: days,
    intervalMode: intervalMode,
    startMinute: startMinute,
    endMinute: endMinute,
    intervalMinutes: intervalMinutes,
    times: times,
    lastShown: stamp,
  );
  Map<String, Object?> toJson() => {
    'target': target.toJson(),
    'enabled': enabled,
    'days': days,
    'intervalMode': intervalMode,
    'start': startMinute,
    'end': endMinute,
    'interval': intervalMinutes,
    'times': times,
    'lastShown': lastShown,
  };
  factory MemoryAudioSchedule.fromJson(Map<String, dynamic> j) =>
      MemoryAudioSchedule(
        target: MemoryAudioTarget.fromJson(j['target'] as Map<String, dynamic>),
        enabled: j['enabled'] == true,
        days: (j['days'] as List).cast<int>(),
        intervalMode: j['intervalMode'] == true,
        startMinute: j['start'] as int,
        endMinute: j['end'] as int,
        intervalMinutes: j['interval'] as int,
        times: (j['times'] as List).cast<int>(),
        lastShown: j['lastShown'] as String?,
      );
}

class MemoryAudioScheduleStore {
  MemoryAudioScheduleStore({
    Future<String?> Function(String)? load,
    Future<void> Function(String, String)? save,
  }) : _load = load ?? AppSettingsService.instance.loadRawSetting,
       _save = save ?? AppSettingsService.instance.saveRawSetting;
  static final instance = MemoryAudioScheduleStore();
  static const key = 'memory_audio.schedules.v1';
  final changes = ValueNotifier<int>(0);
  final Future<String?> Function(String) _load;
  final Future<void> Function(String, String) _save;
  Future<void> _pending = Future.value();

  Future<T> _write<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<List<MemoryAudioSchedule>> load() async {
    final raw = await _load(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((j) => MemoryAudioSchedule.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveAll(List<MemoryAudioSchedule> all) =>
      _save(key, jsonEncode(all.map((s) => s.toJson()).toList()));
  Future<void> save(MemoryAudioSchedule schedule) => _write(() async {
    final all = await load();
    final previous = all
        .where((s) => s.target.key == schedule.target.key)
        .firstOrNull;
    if (previous?.lastShown != null) {
      schedule = schedule.marked(previous!.lastShown!);
    }
    all.removeWhere((s) => s.target.key == schedule.target.key);
    all.add(schedule);
    await _saveAll(all);
    changes.value++;
  });
  Future<MemoryAudioSchedule?> claimDue(String targetKey, DateTime now) =>
      _write(() async {
        final all = await load();
        final i = all.indexWhere((s) => s.target.key == targetKey);
        if (i < 0) return null;
        final stamp = all[i].occurrence(now);
        if (stamp == null) return null;
        final due = all[i];
        all[i] = due.marked(stamp);
        await _saveAll(all);
        return due;
      });
}
