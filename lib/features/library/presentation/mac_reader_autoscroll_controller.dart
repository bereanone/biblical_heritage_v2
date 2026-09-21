import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'reader_tilt_autoscroll_controller.dart';
import 'reader_tilt_preferences.dart';

const double defaultMacAutoscrollBaseSpeed = 18;
const int defaultMacAutoscrollMaximumStep = 50;
const List<int> macAutoscrollSpeedSteps = <int>[1, 2, 3, 5, 10, 25, 50];
const List<int> macAutoscrollSignedSpeedSteps = <int>[
  -50,
  -25,
  -10,
  -5,
  -3,
  -2,
  -1,
  0,
  1,
  2,
  3,
  5,
  10,
  25,
  50,
];
const int _boundaryConfirmationFrames = 8;
const Duration macAutoscrollMaximumFrameElapsed = Duration(milliseconds: 100);
const double macAutoscrollMaximumFrameDeltaPixels = 200;
const double _audioNarrationScrollScale = 1 / 3;
const double _maximumAudioNarrationPixelsPerSecond = 18;

double cappedMacAutoscrollFrameDelta({
  required double pixelsPerSecond,
  required Duration elapsed,
}) {
  // Clamp elapsed time to avoid huge jumps on resumed/backgrounded apps.
  // Cap is much higher than typical frame intervals to preserve smooth motion
  // across variable frame timing without visible stepping.
  final cappedMicroseconds = elapsed.inMicroseconds.clamp(
    0,
    macAutoscrollMaximumFrameElapsed.inMicroseconds,
  );
  final delta =
      pixelsPerSecond * cappedMicroseconds / Duration.microsecondsPerSecond;
  // Only clamp if delta is pathologically large (app was suspended).
  // For normal operation at 60Hz, a 200px/s speed at 16.67ms = ~3.3px per frame,
  // which is well under the 200px cap. Higher speeds at higher frame rates
  // stay smooth without arbitrary capping.
  return delta.clamp(
    -macAutoscrollMaximumFrameDeltaPixels,
    macAutoscrollMaximumFrameDeltaPixels,
  );
}

int normalizeMacAutoscrollRememberedStep(int? value, int maximumStep) {
  final maximum = maximumStep.clamp(1, defaultMacAutoscrollMaximumStep);
  final candidate = value ?? 1;
  if (candidate == 0) return 1;
  return candidate.clamp(-maximum, maximum);
}

double normalizeSpeechRate(double value) =>
    value.isFinite ? (value.clamp(0.75, 1.5) * 20).round() / 20 : 1.0;

class MacAutoscrollPreferences {
  const MacAutoscrollPreferences({
    this.baseSpeed = defaultMacAutoscrollBaseSpeed,
    this.lastNonzeroStep = 1,
    this.maximumStep = defaultMacAutoscrollMaximumStep,
    this.statusBannerMode = ReaderTiltStatusBannerMode.autoHide,
    this.audioEnabled = false,
    this.announceChapter = false,
    this.announceVerseNumbers = false,
    this.speechRate = 1.0,
  });

  factory MacAutoscrollPreferences.fromStoredValues({
    String? baseSpeed,
    String? speechRate,
    String? lastNonzeroStep,
    String? maximumStep,
    ReaderTiltStatusBannerMode statusBannerMode =
        ReaderTiltStatusBannerMode.autoHide,
    bool audioEnabled = false,
    bool announceChapter = false,
    bool announceVerseNumbers = false,
  }) {
    final parsedMaximum = int.tryParse(maximumStep ?? '');
    final maximum = parsedMaximum != null && parsedMaximum >= 1
        ? parsedMaximum.clamp(1, defaultMacAutoscrollMaximumStep)
        : defaultMacAutoscrollMaximumStep;
    final parsedBase = double.tryParse(baseSpeed ?? '');
    final base = parsedBase != null && parsedBase.isFinite && parsedBase > 0
        ? parsedBase.clamp(6, 60).toDouble()
        : defaultMacAutoscrollBaseSpeed;
    final parsedStep = int.tryParse(lastNonzeroStep ?? '');
    final step = normalizeMacAutoscrollRememberedStep(parsedStep, maximum);
    return MacAutoscrollPreferences(
      baseSpeed: base,
      speechRate: normalizeSpeechRate(double.tryParse(speechRate ?? '') ?? 1),
      lastNonzeroStep: step,
      maximumStep: maximum,
      statusBannerMode: statusBannerMode,
      audioEnabled: audioEnabled,
      announceChapter: announceChapter,
      announceVerseNumbers: announceVerseNumbers,
    );
  }

  final double speechRate;
  final double baseSpeed;
  final int lastNonzeroStep;
  final int maximumStep;
  final ReaderTiltStatusBannerMode statusBannerMode;
  final bool audioEnabled;
  final bool announceChapter;
  final bool announceVerseNumbers;
}

class MacReaderAutoScrollController extends ChangeNotifier {
  MacReaderAutoScrollController({
    required this.scrollTarget,
    MacAutoscrollPreferences preferences = const MacAutoscrollPreferences(),
    Ticker Function(TickerCallback callback)? tickerFactory,
    this.driveFrames = true,
    this.narrationControlsPacing = false,
  }) : _speechRate = normalizeSpeechRate(preferences.speechRate),
       _baseSpeed = preferences.baseSpeed,
       _lastNonzeroStep = normalizeMacAutoscrollRememberedStep(
         preferences.lastNonzeroStep,
         preferences.maximumStep,
       ),
       _maximumStep = preferences.maximumStep.clamp(
         1,
         defaultMacAutoscrollMaximumStep,
       ),
       _statusBannerMode = preferences.statusBannerMode,
       _audioEnabled = preferences.audioEnabled,
       _announceChapter = preferences.announceChapter,
       _announceVerseNumbers = preferences.announceVerseNumbers,
       _tickerFactory = tickerFactory ?? Ticker.new;

  final ReaderAutoScrollTarget scrollTarget;

  /// The Bible narrator holds the page during speech; motion is only the
  /// brief transition to the next verse, independent of spoken-word speed.
  final bool narrationControlsPacing;
  @visibleForTesting
  final bool driveFrames;
  final Ticker Function(TickerCallback callback) _tickerFactory;
  Ticker? _ticker;
  Duration? _lastElapsed;
  bool _disposed = false;
  bool _enabled = false;
  int _signedStep = 0;
  int _lastNonzeroStep;
  int _maximumStep;
  ReaderTiltStatusBannerMode _statusBannerMode;
  bool _audioEnabled;
  bool _announceChapter;
  bool _announceVerseNumbers;
  double _baseSpeed;
  double _speechRate;
  double get speechRate => _speechRate;
  bool get isNarrationMode => narrationControlsPacing && _audioEnabled;

  void setSpeechRate(double value) {
    final next = normalizeSpeechRate(value);
    if (_disposed || next == _speechRate) return;
    _speechRate = next;
    _showStatus();
  }

  bool get audioEnabled => _audioEnabled;
  bool get announceChapter => _announceChapter;
  bool get announceVerseNumbers => _announceVerseNumbers;
  int statusRevision = 0;
  int keyboardStatusRevision = 0;
  int _consecutiveBlockedFrames = 0;
  bool _hasMovedSinceStart = false;

  int get signedStep => _signedStep;
  int get lastNonzeroStep => _lastNonzeroStep;
  int get maximumStep => _maximumStep;
  double get baseSpeed => _baseSpeed;
  ReaderTiltStatusBannerMode get statusBannerMode => _statusBannerMode;
  bool get isActive => _enabled;
  bool get isScrolling => _enabled && _signedStep != 0;
  bool get hasFrameDriver => _ticker != null;
  bool get isPixelScrolling => isScrolling && !isNarrationMode;

  /// Pause audio without consuming the pointer sequence used to select text.
  void pauseNarrationForInteraction() {
    if (isNarrationMode && isScrolling) stopForManualInteraction();
  }

  // Offline narration needs longer on each verse than plain screen reading.
  // Keep the user's step ladder intact, but slow the visual rate only while
  // Audio is On so the centered text can stay with the spoken text.
  double get pixelsPerSecond {
    if (!_audioEnabled) return _signedStep * _baseSpeed;
    if (narrationControlsPacing) {
      return 0;
    }
    final requestedMagnitude =
        _signedStep.abs() * _baseSpeed * _audioNarrationScrollScale;
    final permittedMagnitude = requestedMagnitude.clamp(
      0.0,
      _maximumAudioNarrationPixelsPerSecond,
    );
    return _signedStep.isNegative ? -permittedMagnitude : permittedMagnitude;
  }

  String get statusLabel {
    if (isNarrationMode) {
      return '${isScrolling ? 'Reading' : 'Speech paused'} ${_speechRate.toStringAsFixed(2)}×';
    }
    if (!_enabled) return 'Autoscroll stopped';
    if (_signedStep == 0) return 'Autoscroll paused';
    return _signedStep > 0
        ? 'Autoscroll ↓ $_signedStep×'
        : 'Autoscroll ↑ ${_signedStep.abs()}×';
  }

  void increaseStep() => advanceDownward();
  void decreaseStep() => advanceUpward();

  void advanceDownward() {
    if (!_enabled) return;
    if (isNarrationMode) {
      if (_signedStep == 0) {
        setSignedStep(1);
      } else {
        setSpeechRate(_speechRate + 0.05);
      }
      return;
    }
    setSignedStep(_adjacentSignedStep(1));
  }

  void advanceUpward() {
    if (!_enabled) return;
    if (isNarrationMode) {
      setSpeechRate(_speechRate - 0.05);
      return;
    }
    setSignedStep(_adjacentSignedStep(-1));
  }

  int _adjacentSignedStep(int direction) {
    final ladder = macAutoscrollSignedSpeedSteps
        .where((value) => value.abs() <= _maximumStep)
        .toList(growable: false);
    final index = ladder.indexOf(_signedStep);
    if (index < 0) return _signedStep.clamp(-_maximumStep, _maximumStep);
    return ladder[(index + direction).clamp(0, ladder.length - 1)];
  }

  void setSignedStep(int value) {
    if (_disposed) return;
    final next = value.clamp(-_maximumStep, _maximumStep);
    final wasEnabled = _enabled;
    _enabled = true;
    if (next == _signedStep && wasEnabled) {
      _showStatus();
      return;
    }
    final wasActive = _signedStep != 0;
    _signedStep = next;
    _consecutiveBlockedFrames = 0;
    if (next != 0 && !wasActive) _hasMovedSinceStart = false;
    if (next != 0) _lastNonzeroStep = next;
    if (next == 0) {
      _disposeTicker();
    } else {
      _ensureTicker();
    }
    _showStatus();
  }

  void toggle() {
    if (_disposed) return;
    if (_enabled) {
      _disable(showStatus: true);
      return;
    }
    _enabled = true;
    _signedStep = 0;
    _consecutiveBlockedFrames = 0;
    _disposeTicker();
    _showStatus();
  }

  void stopForManualInteraction() {
    if (_disposed || !_enabled) return;
    _disable(showStatus: true);
  }

  void stopWithoutNotification() {
    if (_disposed || !_enabled) return;
    _enabled = false;
    _signedStep = 0;
    _consecutiveBlockedFrames = 0;
    _disposeTicker();
  }

  void updatePreferences(MacAutoscrollPreferences preferences) {
    _speechRate = normalizeSpeechRate(preferences.speechRate);
    _baseSpeed = preferences.baseSpeed;
    _maximumStep = preferences.maximumStep.clamp(
      1,
      defaultMacAutoscrollMaximumStep,
    );
    _lastNonzeroStep = normalizeMacAutoscrollRememberedStep(
      preferences.lastNonzeroStep,
      _maximumStep,
    );
    _statusBannerMode = preferences.statusBannerMode;
    _audioEnabled = preferences.audioEnabled;
    _announceChapter = preferences.announceChapter;
    _announceVerseNumbers = preferences.announceVerseNumbers;
    if (_signedStep != 0) {
      _signedStep = _signedStep.clamp(-_maximumStep, _maximumStep);
    }
    if (isNarrationMode) {
      _disposeTicker();
    } else if (isScrolling) {
      _ensureTicker();
    }
    notifyListeners();
  }

  @visibleForTesting
  void tick(Duration elapsed, {bool enforceFrameSafetyCap = false}) {
    if (isNarrationMode ||
        !isScrolling ||
        elapsed <= Duration.zero ||
        !scrollTarget.isAttached) {
      return;
    }
    final delta = enforceFrameSafetyCap
        ? cappedMacAutoscrollFrameDelta(
            pixelsPerSecond: pixelsPerSecond,
            elapsed: elapsed,
          )
        : pixelsPerSecond *
              elapsed.inMicroseconds /
              Duration.microsecondsPerSecond;
    if (scrollTarget.scrollBy(delta)) {
      _consecutiveBlockedFrames = 0;
      _hasMovedSinceStart = true;
      return;
    }
    _consecutiveBlockedFrames++;
    if (_hasMovedSinceStart &&
        _consecutiveBlockedFrames >= _boundaryConfirmationFrames) {
      _disable(showStatus: true);
    }
  }

  void _ensureTicker() {
    if (!driveFrames || isNarrationMode) return;
    if (_ticker != null) return;
    _lastElapsed = null;
    _ticker = _tickerFactory((elapsed) {
      final previous = _lastElapsed;
      _lastElapsed = elapsed;
      if (previous != null) {
        tick(elapsed - previous, enforceFrameSafetyCap: true);
      }
    })..start();
  }

  void _disposeTicker() {
    _ticker?.dispose();
    _ticker = null;
    _lastElapsed = null;
  }

  void _disable({required bool showStatus}) {
    _enabled = false;
    _signedStep = 0;
    _consecutiveBlockedFrames = 0;
    _disposeTicker();
    if (showStatus) _showStatus();
  }

  void _showStatus() {
    statusRevision++;
    notifyListeners();
  }

  /// Requests a short status flash even when the persistent banner preference
  /// is Always Hidden. Used only for desktop arrow-key speed changes.
  void showKeyboardStatus() {
    if (_disposed) return;
    keyboardStatusRevision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeTicker();
    super.dispose();
  }
}
