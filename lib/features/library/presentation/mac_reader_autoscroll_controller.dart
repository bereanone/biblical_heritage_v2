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
const Duration macAutoscrollMaximumFrameElapsed = Duration(milliseconds: 50);
const double macAutoscrollMaximumFrameDeltaPixels = 48;

double cappedMacAutoscrollFrameDelta({
  required double pixelsPerSecond,
  required Duration elapsed,
}) {
  final cappedMicroseconds = elapsed.inMicroseconds.clamp(
    0,
    macAutoscrollMaximumFrameElapsed.inMicroseconds,
  );
  final delta =
      pixelsPerSecond * cappedMicroseconds / Duration.microsecondsPerSecond;
  return delta
      .clamp(
        -macAutoscrollMaximumFrameDeltaPixels,
        macAutoscrollMaximumFrameDeltaPixels,
      )
      .toDouble();
}

int normalizeMacAutoscrollRememberedStep(int? value, int maximumStep) {
  final maximum = maximumStep.clamp(1, defaultMacAutoscrollMaximumStep);
  final candidate = value ?? 1;
  if (candidate == 0) return 1;
  return candidate.clamp(-maximum, maximum);
}

class MacAutoscrollPreferences {
  const MacAutoscrollPreferences({
    this.baseSpeed = defaultMacAutoscrollBaseSpeed,
    this.lastNonzeroStep = 1,
    this.maximumStep = defaultMacAutoscrollMaximumStep,
    this.statusBannerMode = ReaderTiltStatusBannerMode.autoHide,
  });

  factory MacAutoscrollPreferences.fromStoredValues({
    String? baseSpeed,
    String? lastNonzeroStep,
    String? maximumStep,
    ReaderTiltStatusBannerMode statusBannerMode =
        ReaderTiltStatusBannerMode.autoHide,
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
      lastNonzeroStep: step,
      maximumStep: maximum,
      statusBannerMode: statusBannerMode,
    );
  }

  final double baseSpeed;
  final int lastNonzeroStep;
  final int maximumStep;
  final ReaderTiltStatusBannerMode statusBannerMode;
}

class MacReaderAutoScrollController extends ChangeNotifier {
  MacReaderAutoScrollController({
    required this.scrollTarget,
    MacAutoscrollPreferences preferences = const MacAutoscrollPreferences(),
    Ticker Function(TickerCallback callback)? tickerFactory,
    this.driveFrames = true,
  }) : _baseSpeed = preferences.baseSpeed,
       _lastNonzeroStep = normalizeMacAutoscrollRememberedStep(
         preferences.lastNonzeroStep,
         preferences.maximumStep,
       ),
       _maximumStep = preferences.maximumStep.clamp(
         1,
         defaultMacAutoscrollMaximumStep,
       ),
       _statusBannerMode = preferences.statusBannerMode,
       _tickerFactory = tickerFactory ?? Ticker.new;

  final ReaderAutoScrollTarget scrollTarget;
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
  double _baseSpeed;
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
  double get pixelsPerSecond => _signedStep * _baseSpeed;

  String get statusLabel {
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
    setSignedStep(_adjacentSignedStep(1));
  }

  void advanceUpward() {
    if (!_enabled) return;
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
    if (_signedStep != 0) {
      _signedStep = _signedStep.clamp(-_maximumStep, _maximumStep);
    }
    notifyListeners();
  }

  @visibleForTesting
  void tick(Duration elapsed, {bool enforceFrameSafetyCap = false}) {
    if (!isScrolling || elapsed <= Duration.zero || !scrollTarget.isAttached) {
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
    if (!driveFrames) return;
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
