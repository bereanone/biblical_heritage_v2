import 'package:flutter/widgets.dart';

/// Caps only the momentum after a finger is lifted. Direct dragging is left
/// untouched, and this is scoped to the Bible reader's list.
class ReaderBoundedFlingPhysics extends BouncingScrollPhysics {
  const ReaderBoundedFlingPhysics({super.parent});

  static const double maximumFlingPixelsPerSecond = 1400;

  @override
  ReaderBoundedFlingPhysics applyTo(ScrollPhysics? ancestor) =>
      ReaderBoundedFlingPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => super.createBallisticSimulation(
    position,
    velocity.clamp(-maximumFlingPixelsPerSecond, maximumFlingPixelsPerSecond),
  );
}
