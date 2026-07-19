import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'reader_tilt_autoscroll_controller.dart';

const double defaultMacAutoscrollBaseSpeed = 18;
const int defaultMacAutoscrollMaximumStep = 60;
const List<int> macAutoscrollSpeedSteps = <int>[1, 2, 3, 5, 15, 30, 60];
const int _boundaryConfirmationFrames = 8;

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
  });

  factory MacAutoscrollPreferences.fromStoredValues({
    String? baseSpeed,
    String? lastNonzeroStep,
    String? maximumStep,
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
    );
  }

  final double baseSpeed;
  final int lastNonzeroStep;
  final int maximumStep;
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
       _tickerFactory = tickerFactory ?? Ticker.new;

  final ReaderAutoScrollTarget scrollTarget;
  @visibleForTesting
  final bool driveFrames;
  final Ticker Function(TickerCallback callback) _tickerFactory;
  Ticker? _ticker;
  Duration? _lastElapsed;
  bool _disposed = false;
  int _signedStep = 0;
  int _lastNonzeroStep;
  int _maximumStep;
  double _baseSpeed;
  int statusRevision = 0;
  int _consecutiveBlockedFrames = 0;
  bool _hasMovedSinceStart = false;

  int get signedStep => _signedStep;
  int get lastNonzeroStep => _lastNonzeroStep;
  int get maximumStep => _maximumStep;
  double get baseSpeed => _baseSpeed;
  bool get isActive => _signedStep != 0;
  bool get hasFrameDriver => _ticker != null;
  double get pixelsPerSecond => _signedStep * _baseSpeed;

  String get statusLabel {
    if (_signedStep == 0) return 'Autoscroll Stopped';
    return _signedStep > 0
        ? 'Autoscroll ↓ $_signedStep×'
        : 'Autoscroll ↑ ${_signedStep.abs()}×';
  }

  void increaseStep() => setSignedStep(_nextStep(towardDown: true));
  void decreaseStep() => setSignedStep(_nextStep(towardDown: false));

  int _nextStep({required bool towardDown}) {
    if (_signedStep == 0) return towardDown ? 1 : -1;
    if (towardDown && _signedStep < 0) {
      return -_nextMagnitude(_signedStep.abs(), increasing: false);
    }
    if (!towardDown && _signedStep > 0) {
      return _nextMagnitude(_signedStep, increasing: false);
    }
    final magnitude = _nextMagnitude(_signedStep.abs(), increasing: true);
    return towardDown ? magnitude : -magnitude;
  }

  int _nextMagnitude(int current, {required bool increasing}) {
    final levels = <int>{
      ...macAutoscrollSpeedSteps.where((value) => value <= _maximumStep),
      _maximumStep,
    }.toList()..sort();
    if (increasing) {
      return levels.firstWhere(
        (value) => value > current,
        orElse: () => _maximumStep,
      );
    }
    final lower = levels.where((value) => value < current);
    return lower.isEmpty ? 0 : lower.last;
  }

  void setSignedStep(int value) {
    if (_disposed) return;
    final next = value.clamp(-_maximumStep, _maximumStep);
    if (next == _signedStep) {
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
    final rememberedBefore = _lastNonzeroStep;
    final resumeStep = normalizeMacAutoscrollRememberedStep(
      rememberedBefore,
      _maximumStep,
    );
    if (isActive) {
      setSignedStep(0);
    } else {
      setSignedStep(resumeStep);
    }
  }

  void stopForManualInteraction() {
    if (_disposed || !isActive) return;
    setSignedStep(0);
  }

  void stopWithoutNotification() {
    if (_disposed || _signedStep == 0) return;
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
    if (_signedStep != 0) {
      _signedStep = _signedStep.clamp(-_maximumStep, _maximumStep);
    }
    notifyListeners();
  }

  @visibleForTesting
  void tick(Duration elapsed) {
    if (!isActive || elapsed <= Duration.zero || !scrollTarget.isAttached) {
      return;
    }
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final delta = pixelsPerSecond * seconds;
    if (scrollTarget.scrollBy(delta)) {
      _consecutiveBlockedFrames = 0;
      _hasMovedSinceStart = true;
      return;
    }
    _consecutiveBlockedFrames++;
    if (_hasMovedSinceStart &&
        _consecutiveBlockedFrames >= _boundaryConfirmationFrames) {
      setSignedStep(0);
    }
  }

  void _ensureTicker() {
    if (!driveFrames) return;
    if (_ticker != null) return;
    _lastElapsed = null;
    _ticker = _tickerFactory((elapsed) {
      final previous = _lastElapsed;
      _lastElapsed = elapsed;
      if (previous != null) tick(elapsed - previous);
    })..start();
  }

  void _disposeTicker() {
    _ticker?.dispose();
    _ticker = null;
    _lastElapsed = null;
  }

  void _showStatus() {
    statusRevision++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeTicker();
    super.dispose();
  }
}
