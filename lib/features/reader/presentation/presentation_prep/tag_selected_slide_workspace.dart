import 'package:flutter/material.dart';

@Deprecated('Use TagWorkingSlideCanvas and TagSlideNavigatorPanel instead.')
class TagSelectedSlideWorkspace extends StatelessWidget {
  const TagSelectedSlideWorkspace({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return child ?? const SizedBox.shrink();
  }
}
