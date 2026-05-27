import 'package:flutter/material.dart';

import '../../data/tags/unified_tag_read_adapter.dart';
import 'tag_presentation_prep_models.dart';
import 'tag_presentation_prep_screen.dart';

Future<void> openTagPresentationPrep(
  BuildContext context, {
  required TagPresentationPrepRequest request,
  UnifiedTagReadAdapter? adapter,
  bool dismissSourceRoute = false,
}) async {
  if (!context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  if (dismissSourceRoute && Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
  }
  if (!navigator.mounted) return;
  await navigator.push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => TagPresentationPrepScreen(
        request: request,
        adapter: adapter ?? UnifiedTagReadAdapter(),
      ),
    ),
  );
}
