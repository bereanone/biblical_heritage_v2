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
  bool continuous = false,
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
  final sliceTop = blockTop + progress.clamp(0.0, 1.0) * box.size.height;
  final bandDelta = librarySpeechFollowDelta(
    sliceTop: sliceTop,
    viewportHeight: viewport.size.height,
  );
  // A tall recorded paragraph moves gradually with playback instead of
  // waiting for a large jump at the next paragraph or comfort-band edge.
  final forwardDelta = sliceTop - viewport.size.height * .35;
  final delta = continuous && box.size.height > viewport.size.height
      ? (forwardDelta > 1
            ? forwardDelta
            : (bandDelta != null && bandDelta < 0 ? bandDelta : null))
      : bandDelta;
  if (delta == null) return false;
  return animateSpeechFollow(
    scrollable.position,
    delta,
    duration: continuous ? const Duration(milliseconds: 400) : _followDuration,
    curve: continuous ? Curves.linear : Curves.easeOutCubic,
  );
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
  final animation = position.animateTo(
    target,
    duration: duration,
    curve: curve,
  );
  // Driven scrolling normally absorbs hits on the text. Narration must remain
  // interruptible by a word press, even when follow animations are continuous.
  position.context.setIgnorePointer(false);
  await animation;
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

/// Forward playback never pulls text back down after revealing a paragraph.
/// Tall paragraphs advance continuously; short paragraphs stay in place while
/// their spoken text is comfortably visible. Explicit seeks are handled by
/// the reader before applying this correction.
double? recordedSpeechFollowDelta({
  required double spokenTop,
  required double paragraphHeight,
  required double viewportHeight,
}) {
  if (viewportHeight <= 0) return null;
  if (paragraphHeight <= viewportHeight &&
      spokenTop <= viewportHeight * librarySpeechComfortBottom) {
    return null;
  }
  final delta = spokenTop - viewportHeight * .5;
  return delta > 1 ? delta : null;
}
