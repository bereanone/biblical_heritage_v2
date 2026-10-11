import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps the sentence being narrated on screen inside a long paragraph.
///
/// The speech queue reveals a paragraph once, when its first slice starts.
/// Slices are at most ~320 characters, so a long paragraph is spoken across
/// many slices while the view stays put and the voice drifts off the bottom.
/// This estimates where each later slice sits in the paragraph (character
/// offset over paragraph length) and scrolls only once it passes mid-screen.

/// A slice whose top is inside this band (fractions of the viewport height)
/// is already comfortably visible and is left alone.
const double librarySpeechComfortTop = .06;
const double librarySpeechComfortBottom = .5;

/// Where a followed slice is placed when the view does scroll.
const double librarySpeechAnchor = .2;

/// Pixels to scroll so the slice returns to the anchor, or null if the slice
/// is already inside the comfort band. [sliceTop] is measured from the top of
/// the viewport.
double? librarySpeechFollowDelta({
  required double sliceTop,
  required double viewportHeight,
}) {
  if (viewportHeight <= 0) return null;
  final fraction = sliceTop / viewportHeight;
  if (fraction >= librarySpeechComfortTop &&
      fraction <= librarySpeechComfortBottom) {
    return null;
  }
  return sliceTop - librarySpeechAnchor * viewportHeight;
}

/// Fraction of a paragraph that precedes a slice, clamped to 0..1.
double librarySpeechProgress(int startOffset, int? sourceLength) {
  if (sourceLength == null || sourceLength <= 0) return 0;
  return (startOffset / sourceLength).clamp(0.0, 1.0);
}

const _followDuration = Duration(milliseconds: 280);

/// Follows narration inside a paragraph rendered by [blockContext], for a
/// reader that can resolve the paragraph's own element. Returns whether the
/// view scrolled.
Future<bool> followSpeechInBlock({
  required BuildContext blockContext,
  required double progress,
}) async {
  if (!blockContext.mounted) return false;
  final scrollable = Scrollable.maybeOf(blockContext, axis: Axis.vertical);
  final box = blockContext.findRenderObject();
  final viewport = scrollable?.context.findRenderObject();
  if (scrollable == null ||
      box is! RenderBox ||
      viewport is! RenderBox ||
      !box.attached ||
      !viewport.attached ||
      !box.hasSize ||
      !viewport.hasSize) {
    return false;
  }
  final blockTop = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
  final delta = librarySpeechFollowDelta(
    sliceTop: blockTop + progress * box.size.height,
    viewportHeight: viewport.size.height,
  );
  if (delta == null) return false;
  return animateSpeechFollow(scrollable.position, delta);
}

/// Scrolls [position] by [delta] pixels, clamped to its extent.
Future<bool> animateSpeechFollow(
  ScrollPosition position,
  double delta, {
  Duration duration = _followDuration,
  Curve curve = Curves.easeOutCubic,
}) async {
  if (!position.hasPixels) return false;
  final target = (position.pixels + delta).clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  if ((target - position.pixels).abs() <= 1) return false;
  await position.animateTo(target, duration: duration, curve: curve);
  return true;
}

/// Lets a reader's reveal callback reach the list state that owns the item
/// positions, without the reader having to hold that state.
class LibrarySpeechFollowHandle {
  Future<bool> Function(int order, double progress)? _follow;

  bool get isAttached => _follow != null;

  Future<bool> follow(int order, double progress) async =>
      await _follow?.call(order, progress) ?? false;

  void attach(Future<bool> Function(int order, double progress) callback) =>
      _follow = callback;

  void detach() => _follow = null;
}
