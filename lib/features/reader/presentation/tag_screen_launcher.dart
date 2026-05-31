import 'package:flutter/material.dart';

import 'tag_quick_apply_helper.dart';
import 'tag_screen_dialog.dart';
import 'viewer_passage_models.dart';
import 'viewer_range_selection.dart';

enum HashTagLaunchMode { scriptureOnly, studyChain }

Future<void> showHashTagScreen(
  NavigatorState navigator, {
  required PassageData passage,
  required ViewerRangeSelection selection,
  required List<HashTagTarget> selectionTargets,
  required double fontScale,
  int initialTabIndex = 0,
  String tagSymbol = '#',
  HashTagLaunchMode launchMode = HashTagLaunchMode.scriptureOnly,
  ValueChanged<int>? onTagTabChanged,
  String? initialTag,
  String? selectionLabelOverride,
  Future<HashTagQuickApplyResult> Function(String tag)?
  onApplySelectionOverride,
  Future<void> Function(int blockId)? onSelectBlockId,
}) {
  final resolvedInitialTabIndex = switch (launchMode) {
    HashTagLaunchMode.scriptureOnly => initialTabIndex,
    HashTagLaunchMode.studyChain => 1,
  }.clamp(0, 1).toInt();

  final rootNavigator = Navigator.of(navigator.context, rootNavigator: true);
  return showDialog<void>(
    context: rootNavigator.context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (context) {
      final repository = tagSymbol == r'$'
          ? DollarTagRepository()
          : HashTagRepository();
      return HashTagDialog(
        repository: repository,
        passage: passage,
        selection: selection,
        selectionTargets: selectionTargets,
        fontScale: fontScale,
        initialTabIndex: resolvedInitialTabIndex,
        tagSymbol: tagSymbol,
        onTagTabChanged: onTagTabChanged,
        initialTag: initialTag,
        selectionLabelOverride: selectionLabelOverride,
        onApplySelectionOverride: onApplySelectionOverride,
        onSelectBlockId: onSelectBlockId,
        fullScreen: false,
      );
    },
  );
}

Future<void> showDollarTagScreen(
  NavigatorState navigator, {
  required PassageData passage,
  required ViewerRangeSelection selection,
  required List<HashTagTarget> selectionTargets,
  required double fontScale,
  int initialTabIndex = 0,
  HashTagLaunchMode launchMode = HashTagLaunchMode.scriptureOnly,
  ValueChanged<int>? onTagTabChanged,
  String? initialTag,
  String? selectionLabelOverride,
  Future<HashTagQuickApplyResult> Function(String tag)?
  onApplySelectionOverride,
  Future<void> Function(int blockId)? onSelectBlockId,
}) {
  return showHashTagScreen(
    navigator,
    passage: passage,
    selection: selection,
    selectionTargets: selectionTargets,
    fontScale: fontScale,
    initialTabIndex: initialTabIndex,
    tagSymbol: r'$',
    launchMode: launchMode,
    onTagTabChanged: onTagTabChanged,
    initialTag: initialTag,
    selectionLabelOverride: selectionLabelOverride,
    onApplySelectionOverride: onApplySelectionOverride,
    onSelectBlockId: onSelectBlockId,
  );
}
