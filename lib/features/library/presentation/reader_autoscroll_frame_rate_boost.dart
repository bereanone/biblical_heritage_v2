import 'dart:io';

import 'package:flutter/services.dart';

/// Requests Android's high frame-rate category for the duration of
/// programmatic reader autoscroll.
///
/// Autoscroll drives the view via `ScrollPosition.jumpTo()`, which produces
/// no touch input. Android's adaptive refresh rate only sustains its
/// touch-boosted high refresh rate for ~3s after the last touch; once that
/// expires, ticker frames arrive at an irregular ~26-29Hz on affected
/// devices instead of the display's native rate, which is visible as
/// stall/lurch stepping even when the underlying scroll math is correct.
/// Manual finger-drag scrolling keeps the boost alive on its own and does
/// not need this.
abstract interface class ReaderAutoScrollFrameRateBoost {
  Future<void> setActive(bool active);
}

class PlatformReaderAutoScrollFrameRateBoost
    implements ReaderAutoScrollFrameRateBoost {
  PlatformReaderAutoScrollFrameRateBoost({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('studybible/reader_autoscroll_frame_rate');

  final MethodChannel _channel;
  bool _active = false;

  @override
  Future<void> setActive(bool active) async {
    if (!Platform.isAndroid) return;
    if (_active == active) return;
    _active = active;
    try {
      await _channel.invokeMethod<void>('setActive', {'active': active});
    } on PlatformException {
      // Best-effort only: autoscroll must keep working even if the platform
      // call fails (e.g. unsupported API level on the native side).
    } on MissingPluginException {
      // No native handler (e.g. running on a platform/test harness without
      // MainActivity wired up); autoscroll must still work without it.
    }
  }
}
