import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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
    this.maximumTiltRadians = 17 * math.pi / 180,
    this.minimumSpeedPixelsPerSecond = 8,
    this.maximumSpeedPixelsPerSecond = 520,
    this.sampleSmoothingFactor = 0.2,
    this.speedSmoothingFactor = 0.16,
    this.updateInterval = const Duration(milliseconds: 16),
    this.calibrationSampleCount = 12,
  });

  final double deadZoneRadians;
  final double maximumTiltRadians;
  final double minimumSpeedPixelsPerSecond;
  final double maximumSpeedPixelsPerSecond;
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
  final span = settings.maximumTiltRadians - settings.deadZoneRadians;
  final normalized = ((magnitude - settings.deadZoneRadians) / span).clamp(
    0.0,
    1.0,
  );
  final curved = normalized * normalized;
  final speed =
      settings.minimumSpeedPixelsPerSecond +
      (settings.maximumSpeedPixelsPerSecond -
              settings.minimumSpeedPixelsPerSecond) *
          curved;
  return math.min(speed, settings.maximumSpeedPixelsPerSecond) *
      relativeRadians.sign;
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
    maximumSpeedPixelsPerSecond:
        settings.maximumSpeedPixelsPerSecond * preferences.speedMultiplier,
    sampleSmoothingFactor: settings.sampleSmoothingFactor,
    speedSmoothingFactor: settings.speedSmoothingFactor,
    updateInterval: settings.updateInterval,
    calibrationSampleCount: settings.calibrationSampleCount,
  );
  final direction = preferences.reverseVerticalDirection ? -1.0 : 1.0;
  return readerTiltSpeedForAngle(
    relativeRadians * direction,
    effectiveSettings,
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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ReaderTiltMotionSource motionSource;
  final ReaderAutoScrollTarget scrollTarget;
  final ReaderTiltAutoScrollSettings settings;
  ReaderTiltPreferences preferences;
  final bool Function(ReaderChapterTiltDirection direction)? canChangeChapter;
  final void Function(ReaderChapterTiltDirection direction)? onChapterChange;
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
  Timer? _timer;
  double? _smoothedPitch;
  double _targetSpeed = 0;
  DateTime? _verticalPausedUntil;
  bool _disposed = false;

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

  void updatePreferences(ReaderTiltPreferences value) {
    preferences = value;
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
    try {
      _motionSubscription ??= motionSource.start().listen(
        _onSample,
        onError: _onError,
      );
      _timer ??= Timer.periodic(settings.updateInterval, (_) => tick());
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
    speedPixelsPerSecond = 0;
    state = ReaderTiltAutoScrollState.calibrating;
    notifyListeners();
  }

  void recalibrate() {
    if (!isActive) return;
    _beginCalibration();
  }

  void _onSample(ReaderTiltSample sample) {
    if (!isActive) return;
    if (_orientation != null && sample.orientation != _orientation) {
      stop(reason: ReaderTiltAutoScrollState.paused);
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
    _smoothedPitch =
        previous +
        (sample.pitchRadians - previous) * settings.sampleSmoothingFactor;
    final relativePitch = _smoothedPitch! - neutralPitchRadians!;
    final now = _now();
    _targetSpeed =
        _verticalPausedUntil != null && now.isBefore(_verticalPausedUntil!)
        ? 0
        : readerTiltSpeedForPreferences(relativePitch, settings, preferences);

    if (preferences.horizontalChapterTiltEnabled &&
        neutralHorizontalRadians != null &&
        canChangeChapter != null &&
        onChapterChange != null) {
      final relativeHorizontal =
          sample.horizontalRadians - neutralHorizontalRadians!;
      final candidate = relativeHorizontal >= 0
          ? (preferences.reverseHorizontalDirection
                ? ReaderChapterTiltDirection.previous
                : ReaderChapterTiltDirection.next)
          : (preferences.reverseHorizontalDirection
                ? ReaderChapterTiltDirection.next
                : ReaderChapterTiltDirection.previous);
      final boundaryApproved = canChangeChapter!(candidate);
      final verticalSuppressed =
          speedPixelsPerSecond.abs() >
          settings.maximumSpeedPixelsPerSecond * 0.35;
      // A real sideways tilt commonly contains a small pitch component. At
      // the top of a section that pitch could move the scroll position beyond
      // the boundary tolerance during the deliberate hold, making Previous
      // much less reliable than Next (which is clamped at the bottom). Keep
      // the reader pinned while an approved horizontal gesture is developing.
      if (boundaryApproved &&
          relativeHorizontal.abs() >= horizontalThresholdRadians * 0.35) {
        _targetSpeed = 0;
        speedPixelsPerSecond = 0;
      }
      final chapterDirection = _horizontalGesture.update(
        relativeHorizontalRadians: relativeHorizontal,
        thresholdRadians: horizontalThresholdRadians,
        reverseDirection: preferences.reverseHorizontalDirection,
        boundaryApproved: boundaryApproved,
        verticalMovingQuickly: verticalSuppressed,
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
  void tick() {
    if (!isActive || state == ReaderTiltAutoScrollState.calibrating) return;
    speedPixelsPerSecond +=
        (_targetSpeed - speedPixelsPerSecond) * settings.speedSmoothingFactor;
    if (speedPixelsPerSecond.abs() < 0.25 && _targetSpeed == 0) {
      speedPixelsPerSecond = 0;
    }
    state = speedPixelsPerSecond < 0
        ? ReaderTiltAutoScrollState.backward
        : ReaderTiltAutoScrollState.forward;
    if (!scrollTarget.isAttached || speedPixelsPerSecond == 0) {
      notifyListeners();
      return;
    }
    final delta =
        speedPixelsPerSecond *
        settings.updateInterval.inMicroseconds /
        Duration.microsecondsPerSecond;
    if (!scrollTarget.scrollBy(delta)) {
      _targetSpeed = 0;
      speedPixelsPerSecond = 0;
    }
    notifyListeners();
  }

  void _onError(Object _) => stop(reason: ReaderTiltAutoScrollState.error);

  Future<void> stop({
    ReaderTiltAutoScrollState reason = ReaderTiltAutoScrollState.paused,
  }) async {
    _timer?.cancel();
    _timer = null;
    final subscription = _motionSubscription;
    _motionSubscription = null;
    _targetSpeed = 0;
    _horizontalGesture.reset();
    speedPixelsPerSecond = 0;
    if (!_disposed) {
      state = reason;
      notifyListeners();
    }
    unawaited(subscription?.cancel());
    unawaited(motionSource.stop());
  }

  Future<void> stopForManualInteraction() => stop();

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _motionSubscription?.cancel();
    motionSource.stop();
    super.dispose();
  }
}
