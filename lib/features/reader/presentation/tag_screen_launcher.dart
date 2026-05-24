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
  Future<HashTagQuickApplyResult> Function(String tag)? onApplySelectionOverride,
  Future<void> Function(int blockId)? onSelectBlockId,
}) {
  final resolvedInitialTabIndex = switch (launchMode) {
    HashTagLaunchMode.scriptureOnly => initialTabIndex,
    HashTagLaunchMode.studyChain => 1,
  }.clamp(0, 1).toInt();

  return showGeneralDialog<void>(
    context: navigator.context,
    barrierDismissible: true,
    barrierLabel: 'Close tags',
    barrierColor: Colors.black.withValues(alpha: 0.36),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, animation, secondaryAnimation) {
      final repository = tagSymbol == r'$'
          ? DollarTagRepository()
          : HashTagRepository();
      return SafeArea(
        child: Center(
          child: HashTagDialog(
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
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(fade),
          child: child,
        ),
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
  Future<HashTagQuickApplyResult> Function(String tag)? onApplySelectionOverride,
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
