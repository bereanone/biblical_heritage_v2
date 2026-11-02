import '../../library/presentation/mac_reader_autoscroll_controller.dart';

/// Apply the confirmed Android silence workaround once per app process.
/// Later reader openings and manual speed changes retain the user's choice.
class BibleAudioStartupPreferences {
  static final currentProcess = BibleAudioStartupPreferences();
  bool _applied = false;

  MacAutoscrollPreferences apply(
    MacAutoscrollPreferences saved, {
    required bool android,
  }) {
    if (!android || _applied) return saved;
    _applied = true;
    return MacAutoscrollPreferences(
      baseSpeed: saved.baseSpeed,
      lastNonzeroStep: saved.lastNonzeroStep,
      maximumStep: saved.maximumStep,
      statusBannerMode: saved.statusBannerMode,
      audioEnabled: saved.audioEnabled,
      announceChapter: saved.announceChapter,
      announceVerseNumbers: saved.announceVerseNumbers,
      speechRate: 1.05,
    );
  }
}
