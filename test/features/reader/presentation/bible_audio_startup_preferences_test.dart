import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/reader/presentation/bible_audio_startup_preferences.dart';

void main() {
  test(
    'each cold Android app session starts at 1.05 even after saving 1.00',
    () {
      const saved = MacAutoscrollPreferences(speechRate: 1.0);
      for (var restart = 0; restart < 3; restart++) {
        final process = BibleAudioStartupPreferences();
        expect(process.apply(saved, android: true).speechRate, 1.05);
      }
    },
  );

  test('reopening reader in same process preserves a manual speed change', () {
    final process = BibleAudioStartupPreferences();
    process.apply(const MacAutoscrollPreferences(), android: true);
    for (final rate in [1.0, 0.85, 1.25]) {
      final manual = MacAutoscrollPreferences(speechRate: rate);
      expect(process.apply(manual, android: true), same(manual));
    }
  });

  test('workaround preserves audio-off and every other saved preference', () {
    const saved = MacAutoscrollPreferences(
      baseSpeed: 23,
      lastNonzeroStep: 2,
      maximumStep: 4,
      audioEnabled: false,
      announceChapter: true,
      announceVerseNumbers: true,
      speechRate: 0.8,
    );
    final result = BibleAudioStartupPreferences().apply(saved, android: true);
    expect(result.audioEnabled, saved.audioEnabled);
    expect(result.baseSpeed, saved.baseSpeed);
    expect(result.lastNonzeroStep, saved.lastNonzeroStep);
    expect(result.maximumStep, saved.maximumStep);
    expect(result.statusBannerMode, saved.statusBannerMode);
    expect(result.announceChapter, saved.announceChapter);
    expect(result.announceVerseNumbers, saved.announceVerseNumbers);
    expect(result.speechRate, 1.05);
  });

  test('other platforms retain their saved speed and preferences', () {
    final process = BibleAudioStartupPreferences();
    const saved = MacAutoscrollPreferences(speechRate: 1.0);
    expect(process.apply(saved, android: false), same(saved));
    expect(process.apply(saved, android: true).speechRate, 1.05);
  });
}
