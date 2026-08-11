import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// One rendered autoscroll frame, captured for the physical-pixel
/// quantization investigation. All offsets are in the same coordinate
/// space as [ScrollPosition.pixels] unless noted otherwise.
@immutable
class ReaderAutoScrollDiagnosticSample {
  const ReaderAutoScrollDiagnosticSample({
    required this.elapsedMicros,
    required this.requestedDeltaLogical,
    required this.cumulativeRequestedOffsetLogical,
    required this.pixelsBeforeLogical,
    required this.pixelsAfterLogical,
    required this.devicePixelRatio,
  });

  final int elapsedMicros;

  /// The unclamped per-frame delta the autoscroll controller asked for,
  /// before the shared 48px leap guard (macAutoscrollMaximumFrameDeltaPixels).
  final double requestedDeltaLogical;

  /// Running sum of [requestedDeltaLogical] since capture start: the
  /// high-precision target offset the controller would reach with no
  /// clamping, boundary stops, or physical-pixel effects.
  final double cumulativeRequestedOffsetLogical;
  final double pixelsBeforeLogical;
  final double pixelsAfterLogical;
  final double devicePixelRatio;

  double get appliedDeltaLogical => pixelsAfterLogical - pixelsBeforeLogical;
  double get appliedDeltaPhysical => appliedDeltaLogical * devicePixelRatio;
  double get pixelsAfterPhysical => pixelsAfterLogical * devicePixelRatio;
}

/// Bounded, in-memory capture of autoscroll frame data for offline analysis.
/// Not wired into any user-visible flow; started and exported only from a
/// debug-only trigger during the Android scrolling-smoothness investigation.
class ReaderAutoScrollDiagnosticsRecorder {
  static const int _maxSamples = 2000;
  static const int _maxEvents = 1000;

  final List<ReaderAutoScrollDiagnosticSample> _samples = [];
  final List<(int, String)> _events = [];
  Stopwatch? _stopwatch;
  double _cumulativeRequested = 0;

  bool get isCapturing => _stopwatch != null;
  int get sampleCount => _samples.length;

  void start() {
    _samples.clear();
    _events.clear();
    _cumulativeRequested = 0;
    _stopwatch = Stopwatch()..start();
  }

  /// Marks a named instant on the same clock as [record] — e.g. a
  /// window-extension fetch starting, the loaded-window notifyListeners
  /// firing, a cache-fill setState firing, or how long a rebuild-time cache
  /// rebuild took. Lets the exported timeline be correlated against the
  /// per-frame displacement gaps in the main CSV without changing any
  /// production scroll behavior.
  void recordEvent(String label) {
    final stopwatch = _stopwatch;
    if (stopwatch == null) return;
    if (_events.length >= _maxEvents) return;
    _events.add((stopwatch.elapsedMicroseconds, label));
  }

  void record({
    required double requestedDeltaLogical,
    required double pixelsBeforeLogical,
    required double pixelsAfterLogical,
    required double devicePixelRatio,
  }) {
    final stopwatch = _stopwatch;
    if (stopwatch == null) return;
    if (_samples.length >= _maxSamples) return;
    _cumulativeRequested += requestedDeltaLogical;
    _samples.add(
      ReaderAutoScrollDiagnosticSample(
        elapsedMicros: stopwatch.elapsedMicroseconds,
        requestedDeltaLogical: requestedDeltaLogical,
        cumulativeRequestedOffsetLogical: _cumulativeRequested,
        pixelsBeforeLogical: pixelsBeforeLogical,
        pixelsAfterLogical: pixelsAfterLogical,
        devicePixelRatio: devicePixelRatio,
      ),
    );
  }

  /// Stops capture and writes the buffered samples to a CSV file in the
  /// temporary directory (never the user's library data). Returns the
  /// written file, or null if nothing was captured.
  Future<File?> stopAndExport({String label = 'autoscroll_diagnostic'}) async {
    _stopwatch?.stop();
    _stopwatch = null;
    if (_samples.isEmpty) {
      _events.clear();
      return null;
    }
    final buffer = StringBuffer(
      'elapsedMicros,requestedDeltaLogical,cumulativeRequestedOffsetLogical,'
      'pixelsBeforeLogical,pixelsAfterLogical,appliedDeltaLogical,'
      'appliedDeltaPhysical,pixelsAfterPhysical,devicePixelRatio\n',
    );
    for (final sample in _samples) {
      buffer.writeln(
        '${sample.elapsedMicros},'
        '${sample.requestedDeltaLogical},'
        '${sample.cumulativeRequestedOffsetLogical},'
        '${sample.pixelsBeforeLogical},'
        '${sample.pixelsAfterLogical},'
        '${sample.appliedDeltaLogical},'
        '${sample.appliedDeltaPhysical},'
        '${sample.pixelsAfterPhysical},'
        '${sample.devicePixelRatio}',
      );
    }
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${label}_$timestamp.csv');
    await file.writeAsString(buffer.toString());
    debugPrint(
      'ReaderAutoScrollDiagnostics: wrote ${_samples.length} samples to '
      '${file.path}',
    );
    _samples.clear();
    if (_events.isNotEmpty) {
      final eventsBuffer = StringBuffer('elapsedMicros,label\n');
      for (final event in _events) {
        eventsBuffer.writeln('${event.$1},${event.$2}');
      }
      final eventsFile = File('${dir.path}/${label}_events_$timestamp.csv');
      await eventsFile.writeAsString(eventsBuffer.toString());
      debugPrint(
        'ReaderAutoScrollDiagnostics: wrote ${_events.length} events to '
        '${eventsFile.path}',
      );
      _events.clear();
    }
    return file;
  }
}

/// Module-level singleton so the capture point (inside [ViewerBody]) and the
/// debug trigger can share state without threading a new dependency through
/// the widget tree for a temporary investigation.
final readerAutoScrollDiagnostics = ReaderAutoScrollDiagnosticsRecorder();
