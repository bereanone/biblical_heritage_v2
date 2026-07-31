import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import 'reader_tilt_motion_source.dart';
import 'reader_tilt_preferences.dart';

enum ReaderTiltAutoScrollState {
  inactive,
  calibrating,
  forward,
  backward,
  paused,
  unavailable,
  error,
}

enum ReaderChapterTiltDirection { next, previous }

bool readerScrollNotificationIsManual(ScrollNotification notification) =>
    notification is ScrollStartNotification && notification.dragDetails != null;

ReaderChapterTiltDirection? readerManualBoundaryDirection(
  double overscroll, {
  double threshold = 0.5,
}) {
  if (overscroll.abs() < threshold) return null;
  return overscroll > 0
      ? ReaderChapterTiltDirection.next
      : ReaderChapterTiltDirection.previous;
}

ReaderChapterTiltDirection? readerManualBoundaryDirectionForUpdate({
  required double pixels,
  required double minScrollExtent,
  required double maxScrollExtent,
  required double scrollDelta,
  double boundaryTolerance = 0.5,
  double deltaThreshold = 0.5,
}) {
  if (scrollDelta.abs() < deltaThreshold) return null;
  if (scrollDelta > 0 && pixels >= maxScrollExtent - boundaryTolerance) {
    return ReaderChapterTiltDirection.next;
  }
  if (scrollDelta < 0 && pixels <= minScrollExtent + boundaryTolerance) {
    return ReaderChapterTiltDirection.previous;
  }
  return null;
}

double readerCarriedManualScrollOffset({
  required double currentOffset,
  required double minScrollExtent,
  required double maxScrollExtent,
  required double velocity,
}) {
  final carriedDelta = (velocity.clamp(-3000, 3000) * 0.12).clamp(-96, 96);
  return (currentOffset + carriedDelta).clamp(minScrollExtent, maxScrollExtent);
}

class ReaderChapterBoundaryTransitionGate {
  bool transitionInProgress = false;
  bool manualBoundaryLatched = false;

  bool tryBegin({required bool fromTilt}) {
    if (transitionInProgress || (!fromTilt && manualBoundaryLatched)) {
      return false;
    }
    transitionInProgress = true;
    manualBoundaryLatched = !fromTilt;
    return true;
  }

  void complete({required bool fromTilt}) {
    transitionInProgress = false;
    manualBoundaryLatched = !fromTilt;
  }

  void markBookBoundary({required bool fromTilt}) {
    transitionInProgress = false;
    manualBoundaryLatched = !fromTilt;
  }

  void rearmManualInsideSection() {
    if (!transitionInProgress) manualBoundaryLatched = false;
  }
}

@immutable
class ReaderSectionBoundaryState {
  const ReaderSectionBoundaryState({
    required this.atTop,
    required this.atBottom,
  });
  final bool atTop;
  final bool atBottom;
}

ReaderSectionBoundaryState readerSectionBoundaryState({
  required double pixels,
  required double minScrollExtent,
  required double maxScrollExtent,
  double tolerance = 48,
}) => ReaderSectionBoundaryState(
  atTop: pixels - minScrollExtent <= tolerance,
  atBottom: maxScrollExtent - pixels <= tolerance,
);

class ReaderHorizontalChapterGesture {
  ReaderHorizontalChapterGesture({
    this.holdDuration = const Duration(milliseconds: 550),
    this.cooldown = const Duration(seconds: 1),
  });

  final Duration holdDuration;
  final Duration cooldown;
  ReaderChapterTiltDirection? _pendingDirection;
  DateTime? _pendingSince;
  DateTime? _cooldownUntil;
  bool _latched = false;
  bool _returnedToNeutral = true;
  bool get isLatched => _latched;
  int? pendingMilliseconds(DateTime now) => _pendingSince == null
      ? null
      : now.difference(_pendingSince!).inMilliseconds;

  ReaderChapterTiltDirection? update({
    required double relativeHorizontalRadians,
    required double thresholdRadians,
    required bool reverseDirection,
    required bool boundaryApproved,
    required bool verticalMovingQuickly,
    required DateTime now,
  }) {
    final magnitude = relativeHorizontalRadians.abs();
    if (magnitude <= thresholdRadians * 0.35) {
      _pendingDirection = null;
      _pendingSince = null;
      _returnedToNeutral = true;
      if (_cooldownUntil == null || !now.isBefore(_cooldownUntil!)) {
        _latched = false;
      }
      return null;
    }
    if (magnitude < thresholdRadians || verticalMovingQuickly) {
      _pendingDirection = null;
      _pendingSince = null;
      return null;
    }
    if (_latched ||
        !_returnedToNeutral ||
        (_cooldownUntil != null && now.isBefore(_cooldownUntil!))) {
      return null;
    }
    var direction = relativeHorizontalRadians > 0
        ? ReaderChapterTiltDirection.next
        : ReaderChapterTiltDirection.previous;
    if (reverseDirection) {
      direction = direction == ReaderChapterTiltDirection.next
          ? ReaderChapterTiltDirection.previous
          : ReaderChapterTiltDirection.next;
    }
    if (!boundaryApproved) {
      _pendingDirection = null;
      _pendingSince = null;
      return null;
    }
    if (_pendingDirection != direction) {
      _pendingDirection = direction;
      _pendingSince = now;
      return null;
    }
    if (now.difference(_pendingSince!) < holdDuration) return null;
    _latched = true;
    _returnedToNeutral = false;
    _cooldownUntil = now.add(cooldown);
    _pendingDirection = null;
    _pendingSince = null;
    return direction;
  }

  void reset() {
    _pendingDirection = null;
    _pendingSince = null;
    _cooldownUntil = null;
    _latched = false;
    _returnedToNeutral = true;
  }
}

abstract interface class ReaderAutoScrollTarget {
  bool get isAttached;
  bool scrollBy(double delta);
}

class ScrollControllerReaderAutoScrollTarget implements ReaderAutoScrollTarget {
  ScrollControllerReaderAutoScrollTarget(this.controller);

  final ScrollController controller;
  @override
  bool get isAttached => controller.hasClients;

  @override
  bool scrollBy(double delta) {
    if (!controller.hasClients) return false;
    final position = controller.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() > 0.01) {
      controller.jumpTo(target);
      return true;
    }
    return false;
  }
}

class CallbackReaderAutoScrollTarget implements ReaderAutoScrollTarget {
  bool Function(double)? _callback;

  @override
  bool get isAttached => _callback != null;

  void attach(bool Function(double) callback) => _callback = callback;
  void detach() => _callback = null;

  @override
  bool scrollBy(double delta) => _callback?.call(delta) ?? false;
}

@immutable
class ReaderTiltAutoScrollSettings {
  const ReaderTiltAutoScrollSettings({
    this.deadZoneRadians = 3 * math.pi / 180,
    this.maximumTiltRadians = 28 * math.pi / 180,
    this.minimumSpeedPixelsPerSecond = 8,
    this.maximumSpeedPixelsPerSecond = 420,
    this.hardSafetyCapPixelsPerSecond = 900,
    this.sampleSmoothingFactor = 0.2,
    this.speedSmoothingFactor = 0.16,
    this.updateInterval = const Duration(milliseconds: 16),
    this.calibrationSampleCount = 12,
  });

  final double deadZoneRadians;
  final double maximumTiltRadians;
  final double minimumSpeedPixelsPerSecond;
  final double maximumSpeedPixelsPerSecond;
  final double hardSafetyCapPixelsPerSecond;
  final double sampleSmoothingFactor;
  final double speedSmoothingFactor;
  final Duration updateInterval;
  final int calibrationSampleCount;
}

double readerTiltSpeedForAngle(
  double relativeRadians,
  ReaderTiltAutoScrollSettings settings,
) {
  final magnitude = relativeRadians.abs();
  if (magnitude <= settings.deadZoneRadians) return 0;
  final normalized = readerTiltNormalizedMagnitude(relativeRadians, settings);
  // Retain fine control near neutral while preserving a strong, perceptible
  // rise through the upper half of the physical tilt range. Unlike an easing
  // curve, this blend never flattens as it approaches maximum tilt.
  final curved = (0.2 * normalized) + (0.8 * normalized * normalized);
  return curved * settings.maximumSpeedPixelsPerSecond * relativeRadians.sign;
}

double readerTiltNormalizedMagnitude(
  double relativeRadians,
  ReaderTiltAutoScrollSettings settings,
) {
  final span = settings.maximumTiltRadians - settings.deadZoneRadians;
  if (span <= 0) return 0;
  return ((relativeRadians.abs() - settings.deadZoneRadians) / span).clamp(
    0.0,
    1.0,
  );
}

double readerTiltSpeedForPreferences(
  double relativeRadians,
  ReaderTiltAutoScrollSettings settings,
  ReaderTiltPreferences preferences,
) {
  final effectiveSettings = ReaderTiltAutoScrollSettings(
    deadZoneRadians:
        settings.maximumTiltRadians * preferences.neutralZoneFraction,
    maximumTiltRadians: settings.maximumTiltRadians,
    minimumSpeedPixelsPerSecond:
        settings.minimumSpeedPixelsPerSecond * preferences.speedMultiplier,
    maximumSpeedPixelsPerSecond: settings.maximumSpeedPixelsPerSecond,
    hardSafetyCapPixelsPerSecond: settings.hardSafetyCapPixelsPerSecond,
    sampleSmoothingFactor: settings.sampleSmoothingFactor,
    speedSmoothingFactor: settings.speedSmoothingFactor,
    updateInterval: settings.updateInterval,
    calibrationSampleCount: settings.calibrationSampleCount,
  );
  final direction = preferences.reverseVerticalDirection ? -1.0 : 1.0;
  final baseSpeed = readerTiltSpeedForAngle(
    relativeRadians * direction,
    effectiveSettings,
  );
  return (baseSpeed * preferences.speedMultiplier).clamp(
    -settings.hardSafetyCapPixelsPerSecond,
    settings.hardSafetyCapPixelsPerSecond,
  );
}

class ReaderTiltAutoScrollController extends ChangeNotifier {
  ReaderTiltAutoScrollController({
    required this.motionSource,
    required this.scrollTarget,
    this.settings = const ReaderTiltAutoScrollSettings(),
    this.preferences = ReaderTiltPreferences.defaults,
    this.canChangeChapter,
    this.onChapterChange,
    this.onVerticalBoundary,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ReaderTiltMotionSource motionSource;
  final ReaderAutoScrollTarget scrollTarget;
  final ReaderTiltAutoScrollSettings settings;
  ReaderTiltPreferences preferences;
  final bool Function(ReaderChapterTiltDirection direction)? canChangeChapter;
  final void Function(ReaderChapterTiltDirection direction)? onChapterChange;
  final bool Function(ReaderChapterTiltDirection direction)? onVerticalBoundary;
  final DateTime Function() _now;
  final ReaderHorizontalChapterGesture _horizontalGesture =
      ReaderHorizontalChapterGesture();
  ReaderTiltAutoScrollState state = ReaderTiltAutoScrollState.inactive;
  double speedPixelsPerSecond = 0;
  double? neutralPitchRadians;
  double? neutralHorizontalRadians;
  ReaderDeviceOrientation? _orientation;
  final List<double> _calibration = [];
  final List<double> _horizontalCalibration = [];
  StreamSubscription<ReaderTiltSample>? _motionSubscription;
  Ticker? _ticker;
  Duration? _lastFrameElapsed;
  double? _smoothedPitch;
  double _targetSpeed = 0;
  DateTime? _verticalPausedUntil;
  bool _disposed = false;
  bool _verticalBoundaryTransitionInProgress = false;
  int _sessionGeneration = 0;
  int statusBannerRevision = 0;
  int diagnosticListenerCount = 0;
  int diagnosticMotionSamples = 0;
  int diagnosticFrameTicks = 0;
  int diagnosticBoundaryChecks = 0;
  double diagnosticAppliedPixels = 0;

  @override
  void addListener(VoidCallback listener) {
    diagnosticListenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (diagnosticListenerCount > 0) diagnosticListenerCount -= 1;
    super.removeListener(listener);
  }

  @visibleForTesting
  bool get hasFrameDriver => _ticker != null;
  bool get diagnosticHasFrameDriver => _ticker != null;
  int get diagnosticSessionGeneration => _sessionGeneration;
  bool get diagnosticHasMotionSubscription => _motionSubscription != null;
  bool get verticalBoundaryTransitionInProgress =>
      _verticalBoundaryTransitionInProgress;
  int diagnosticStopCalls = 0;
  String? diagnosticLastStopCause;
  double diagnosticRawPitchRadians = 0;
  double diagnosticRawHorizontalRadians = 0;
  double diagnosticRelativePitchRadians = 0;
  double diagnosticRelativeHorizontalRadians = 0;

  bool get isActive =>
      state == ReaderTiltAutoScrollState.calibrating ||
      state == ReaderTiltAutoScrollState.forward ||
      state == ReaderTiltAutoScrollState.backward;
  int get speedPercent =>
      ((speedPixelsPerSecond.abs() / settings.maximumSpeedPixelsPerSecond) *
              100)
          .round()
          .clamp(0, 100);

  double get horizontalThresholdRadians =>
      (18 - 6 * preferences.horizontalSensitivity) * math.pi / 180;

  void updatePreferences(
    ReaderTiltPreferences value, {
    bool showBanner = true,
  }) {
    preferences = value;
    if (showBanner) {
      showStatusBanner();
    } else {
      notifyListeners();
    }
  }

  void showStatusBanner() {
    statusBannerRevision += 1;
    notifyListeners();
  }

  Future<void> activate() async {
    if (_disposed || isActive) return;
    if (!motionSource.isSupported) {
      state = ReaderTiltAutoScrollState.unavailable;
      notifyListeners();
      return;
    }
    _beginCalibration();
    final generation = ++_sessionGeneration;
    try {
      _motionSubscription ??= motionSource.start().listen(
        (sample) {
          if (generation == _sessionGeneration) _onSample(sample);
        },
        onError: (Object error) {
          if (generation == _sessionGeneration) _onError(error);
        },
      );
      _ticker ??= Ticker((elapsed) => _onFrame(elapsed, generation))..start();
    } catch (_) {
      _onError(Object());
    }
  }

  void _beginCalibration() {
    _calibration.clear();
    _horizontalCalibration.clear();
    neutralPitchRadians = null;
    neutralHorizontalRadians = null;
    _orientation = null;
    _smoothedPitch = null;
    _targetSpeed = 0;
    _verticalPausedUntil = null;
    _horizontalGesture.reset();
    _verticalBoundaryTransitionInProgress = false;
    speedPixelsPerSecond = 0;
    state = ReaderTiltAutoScrollState.calibrating;
    statusBannerRevision += 1;
    notifyListeners();
  }

  void recalibrate() {
    if (!isActive) return;
    _beginCalibration();
  }

  void _onSample(ReaderTiltSample sample) {
    assert(() {
      diagnosticMotionSamples += 1;
      return true;
    }());
    if (!isActive) return;
    diagnosticRawPitchRadians = sample.pitchRadians;
    diagnosticRawHorizontalRadians = sample.horizontalRadians;
    if (_orientation != null && sample.orientation != _orientation) {
      stop(
        reason: ReaderTiltAutoScrollState.paused,
        diagnosticCause: 'orientation-change',
      );
      return;
    }
    if (state == ReaderTiltAutoScrollState.calibrating) {
      _orientation ??= sample.orientation;
      _calibration.add(sample.pitchRadians);
      _horizontalCalibration.add(sample.horizontalRadians);
      if (_calibration.length < settings.calibrationSampleCount) return;
      final sorted = [..._calibration]..sort();
      neutralPitchRadians = sorted[sorted.length ~/ 2];
      final sortedHorizontal = [..._horizontalCalibration]..sort();
      neutralHorizontalRadians = sortedHorizontal[sortedHorizontal.length ~/ 2];
      _smoothedPitch = neutralPitchRadians;
      state = ReaderTiltAutoScrollState.paused;
      // Paused here means calibrated and still; the sensor/timer remain active.
      state = ReaderTiltAutoScrollState.forward;
      _targetSpeed = 0;
      speedPixelsPerSecond = 0;
      notifyListeners();
      return;
    }
    final previous = _smoothedPitch ?? sample.pitchRadians;
    final sampleSmoothing = settings.sampleSmoothingFactor;
    _smoothedPitch =
        previous + (sample.pitchRadians - previous) * sampleSmoothing;
    final relativePitch = _smoothedPitch! - neutralPitchRadians!;
    diagnosticRelativePitchRadians = relativePitch;
    final now = _now();
    _targetSpeed =
        _verticalPausedUntil != null && now.isBefore(_verticalPausedUntil!)
        ? 0
        : readerTiltSpeedForPreferences(relativePitch, settings, preferences);

    if (!_verticalBoundaryTransitionInProgress &&
        preferences.horizontalChapterTiltEnabled &&
        neutralHorizontalRadians != null &&
        canChangeChapter != null &&
        onChapterChange != null) {
      final relativeHorizontal =
          sample.horizontalRadians - neutralHorizontalRadians!;
      diagnosticRelativeHorizontalRadians = relativeHorizontal;
      final candidate = relativeHorizontal >= 0
          ? (preferences.reverseHorizontalDirection
                ? ReaderChapterTiltDirection.previous
                : ReaderChapterTiltDirection.next)
          : (preferences.reverseHorizontalDirection
                ? ReaderChapterTiltDirection.next
                : ReaderChapterTiltDirection.previous);
      final boundaryApproved = canChangeChapter!(candidate);
      assert(() {
        diagnosticBoundaryChecks += 1;
        return true;
      }());
      final verticalNearNeutral =
          _targetSpeed.abs() <= settings.maximumSpeedPixelsPerSecond * 0.05;
      final horizontalDominant =
          relativeHorizontal.abs() >= relativePitch.abs() * 1.5;
      final horizontalEligible = verticalNearNeutral && horizontalDominant;
      // A real sideways tilt commonly contains a small pitch component. At
      // the top of a section that pitch could move the scroll position beyond
      // the boundary tolerance during the deliberate hold, making Previous
      // much less reliable than Next (which is clamped at the bottom). Keep
      // the reader pinned while an approved horizontal gesture is developing.
      if (horizontalEligible &&
          boundaryApproved &&
          relativeHorizontal.abs() >= horizontalThresholdRadians * 0.35) {
        _targetSpeed = 0;
        speedPixelsPerSecond = 0;
      }
      final chapterDirection = _horizontalGesture.update(
        relativeHorizontalRadians: relativeHorizontal,
        thresholdRadians: horizontalThresholdRadians,
        reverseDirection: preferences.reverseHorizontalDirection,
        boundaryApproved: boundaryApproved,
        verticalMovingQuickly: !horizontalEligible,
        now: now,
      );
      if (chapterDirection != null) {
        _targetSpeed = 0;
        speedPixelsPerSecond = 0;
        _verticalPausedUntil = now.add(const Duration(seconds: 1));
        onChapterChange!(chapterDirection);
        notifyListeners();
      }
    }
  }

  @visibleForTesting
  void tick({Duration? elapsed}) {
    assert(() {
      diagnosticFrameTicks += 1;
      return true;
    }());
    if (!isActive || state == ReaderTiltAutoScrollState.calibrating) return;
    final seconds =
        (elapsed ?? settings.updateInterval).inMicroseconds /
        Duration.microsecondsPerSecond;
    if (seconds <= 0) return;
    // Preserve the former response at 60 Hz while making smoothing independent
    // of both sensor cadence and display refresh rate.
    final referenceSeconds =
        settings.updateInterval.inMicroseconds / Duration.microsecondsPerSecond;
    final smoothing =
        1 -
        math.pow(1 - settings.speedSmoothingFactor, seconds / referenceSeconds);
    speedPixelsPerSecond += (_targetSpeed - speedPixelsPerSecond) * smoothing;
    if (speedPixelsPerSecond.abs() < 0.25 && _targetSpeed == 0) {
      speedPixelsPerSecond = 0;
    }
    final previousState = state;
    final nextState = speedPixelsPerSecond < 0
        ? ReaderTiltAutoScrollState.backward
        : ReaderTiltAutoScrollState.forward;
    state = nextState;
    if ((previousState == ReaderTiltAutoScrollState.forward &&
            state == ReaderTiltAutoScrollState.backward) ||
        (previousState == ReaderTiltAutoScrollState.backward &&
            state == ReaderTiltAutoScrollState.forward)) {
      statusBannerRevision += 1;
    }
    if (!scrollTarget.isAttached || speedPixelsPerSecond == 0) {
      return;
    }
    final delta = speedPixelsPerSecond * seconds;
    if (!scrollTarget.scrollBy(delta)) {
      if (_verticalBoundaryTransitionInProgress) return;
      final direction = delta > 0
          ? ReaderChapterTiltDirection.next
          : ReaderChapterTiltDirection.previous;
      if (onVerticalBoundary?.call(direction) ?? false) {
        if (isActive) {
          _verticalBoundaryTransitionInProgress = true;
        }
        return;
      }
      _targetSpeed = 0;
      speedPixelsPerSecond = 0;
    } else {
      assert(() {
        diagnosticAppliedPixels += delta.abs();
        return true;
      }());
    }
    if (previousState != nextState) notifyListeners();
  }

  /// Runs the same production frame calculation without a wall-clock delay.
  /// Used only by the standalone deterministic runtime proof.
  void tickForDeterministicDevelopmentProof(Duration elapsed) {
    tick(elapsed: elapsed);
  }

  void _onFrame(Duration elapsed, int generation) {
    if (generation != _sessionGeneration) return;
    final previous = _lastFrameElapsed;
    _lastFrameElapsed = elapsed;
    if (previous == null) return;
    tick(elapsed: elapsed - previous);
  }

  void _onError(Object _) => stop(
    reason: ReaderTiltAutoScrollState.error,
    diagnosticCause: 'motion-source-error',
  );

  /// Rearms automatic boundary detection after the replacement section has
  /// laid out and its scroll position has been placed at the requested edge.
  void completeVerticalBoundaryTransition() {
    if (!_verticalBoundaryTransitionInProgress) return;
    _verticalBoundaryTransitionInProgress = false;
    _lastFrameElapsed = null;
  }

  void stopSynchronously({
    ReaderTiltAutoScrollState reason = ReaderTiltAutoScrollState.paused,
    bool notify = true,
    String diagnosticCause = 'explicit-stop',
  }) {
    diagnosticStopCalls += 1;
    diagnosticLastStopCause = diagnosticCause;
    _sessionGeneration += 1;
    _ticker?.dispose();
    _ticker = null;
    _lastFrameElapsed = null;
    final subscription = _motionSubscription;
    _motionSubscription = null;
    _targetSpeed = 0;
    _smoothedPitch = null;
    _verticalPausedUntil = null;
    _horizontalGesture.reset();
    _verticalBoundaryTransitionInProgress = false;
    speedPixelsPerSecond = 0;
    if (!_disposed) {
      state = reason;
      if (notify) {
        statusBannerRevision += 1;
        notifyListeners();
      }
    }
    unawaited(subscription?.cancel());
    unawaited(motionSource.stop());
  }

  Future<void> stop({
    ReaderTiltAutoScrollState reason = ReaderTiltAutoScrollState.paused,
    bool notify = true,
    String diagnosticCause = 'explicit-stop',
  }) async => stopSynchronously(
    reason: reason,
    notify: notify,
    diagnosticCause: diagnosticCause,
  );

  Future<void> stopForManualInteraction() =>
      stop(diagnosticCause: 'manual-interaction');

  @override
  void dispose() {
    _disposed = true;
    _sessionGeneration += 1;
    _ticker?.dispose();
    _ticker = null;
    _lastFrameElapsed = null;
    _motionSubscription?.cancel();
    motionSource.stop();
    super.dispose();
  }
}
