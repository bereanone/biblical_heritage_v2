import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/memory_schedule/memory_schedule.dart';

void main() {
  const target = MemoryAudioTarget(label: '#Memory', tag: '#Memory');
  test('schedule indicators refresh only after a successful save', () async {
    String? saved;
    var fail = false;
    final store = MemoryAudioScheduleStore(
      load: (_) async => saved,
      save: (_, value) async {
        if (fail) throw StateError('save failed');
        saved = value;
      },
    );
    var notifications = 0;
    store.changes.addListener(() => notifications++);
    await store.save(const MemoryAudioSchedule(target: target, enabled: true));
    expect(notifications, 1);
    expect((await store.load()).single.enabled, isTrue);
    await store.save(const MemoryAudioSchedule(target: target, enabled: false));
    expect(notifications, 2);
    expect((await store.load()).single.enabled, isFalse);
    fail = true;
    await expectLater(
      store.save(const MemoryAudioSchedule(target: target, enabled: true)),
      throwsStateError,
    );
    expect(notifications, 2);
    expect((await store.load()).single.enabled, isFalse);
  });

  test(
    'new schedules default to scheduled times and saved modes survive reopening',
    () async {
      expect(const MemoryAudioSchedule(target: target).intervalMode, isFalse);
      String? saved;
      final store = MemoryAudioScheduleStore(
        load: (_) async => saved,
        save: (_, value) async {
          saved = value;
        },
      );
      for (final mode in [true, false]) {
        await store.save(
          MemoryAudioSchedule(target: target, intervalMode: mode),
        );
        expect((await store.load()).single.intervalMode, mode);
      }
    },
  );
  test(
    'interval window includes endpoints and does not spill into sleep hours',
    () {
      const s = MemoryAudioSchedule(
        target: target,
        enabled: true,
        intervalMode: true,
      );
      expect(s.dailyMinutes, [420, 540, 660, 780, 900, 1020, 1140, 1260]);
      expect(s.occurrence(DateTime(2026, 10, 12, 7)), isNotNull);
      expect(s.occurrence(DateTime(2026, 10, 12, 6, 59)), isNull);
      expect(s.occurrence(DateTime(2026, 10, 12, 21, 1)), isNull);
    },
  );
  test('specific times obey enabled switch and selected weekdays', () {
    const s = MemoryAudioSchedule(
      target: target,
      enabled: true,
      intervalMode: false,
      days: [1, 2, 3, 4],
      times: [390, 450, 390],
    );
    expect(s.dailyMinutes, [390, 450]);
    expect(s.occurrence(DateTime(2026, 10, 12, 6, 30)), isNotNull);
    expect(s.occurrence(DateTime(2026, 10, 16, 6, 30)), isNull);
    expect(
      const MemoryAudioSchedule(
        target: target,
      ).occurrence(DateTime(2026, 10, 12, 7)),
      isNull,
    );
  });
  test(
    'restart and saving edits cannot repeat an acknowledged occurrence',
    () async {
      String? saved;
      final store = MemoryAudioScheduleStore(
        load: (_) async => saved,
        save: (_, value) async {
          saved = value;
        },
      );
      const s = MemoryAudioSchedule(target: target, enabled: true);
      await store.save(s);
      final now = DateTime(2026, 10, 12, 7);
      expect(await store.claimDue(target.key, now), isNotNull);
      expect(await store.claimDue(target.key, now), isNull);
      await store.save(s);
      final restarted = MemoryAudioScheduleStore(
        load: (_) async => saved,
        save: (_, value) async {
          saved = value;
        },
      );
      expect(await restarted.claimDue(target.key, now), isNull);
      expect(
        await restarted.claimDue(target.key, DateTime(2026, 10, 13, 7)),
        isNotNull,
      );
    },
  );
  test(
    'concurrent saves preserve both lists and one reminder claim wins',
    () async {
      String? saved;
      final store = MemoryAudioScheduleStore(
        load: (_) async => saved,
        save: (_, value) async {
          saved = value;
        },
      );
      const other = MemoryAudioTarget(label: 'Romans 6:1-5', memoryId: 1);
      await Future.wait([
        store.save(const MemoryAudioSchedule(target: target, enabled: true)),
        store.save(const MemoryAudioSchedule(target: other, enabled: true)),
      ]);
      expect((await store.load()).length, 2);
      final claims = await Future.wait([
        store.claimDue(target.key, DateTime(2026, 10, 12, 7)),
        store.claimDue(target.key, DateTime(2026, 10, 12, 7)),
      ]);
      expect(claims.where((s) => s != null).length, 1);
    },
  );
  test('corrupt saved data is reported without being overwritten', () async {
    var saved = 'broken';
    final store = MemoryAudioScheduleStore(
      load: (_) async => saved,
      save: (_, value) async {
        saved = value;
      },
    );
    await expectLater(
      store.save(const MemoryAudioSchedule(target: target)),
      throwsFormatException,
    );
    expect(saved, 'broken');
  });
}
