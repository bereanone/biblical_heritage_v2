import 'package:flutter/material.dart';

import 'tag_presentation_auto_fit_text.dart';
import 'tag_slide_grid_layout_helper.dart';

class TagPresentationSlideFrame extends StatelessWidget {
  const TagPresentationSlideFrame({
    super.key,
    required this.body,
    this.topTitleText,
    this.bottomTitleText,
    this.topBand,
    this.bottomBand,
    this.topBandHeightOverride,
    this.bottomBandHeightOverride,
  });

  final Widget body;
  final String? topTitleText;
  final String? bottomTitleText;
  final Widget? topBand;
  final Widget? bottomBand;
  final double? topBandHeightOverride;
  final double? bottomBandHeightOverride;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final topText = _cleanText(topTitleText);
        final bottomText = _cleanText(bottomTitleText);
        final availableHeight = constraints.maxHeight;
        final topHeight = topText == null
            ? 0.0
            : topBandHeightOverride ??
                  TagPresentationSlideFrameLayout.bandHeight(
                    availableHeight,
                    topText,
                  );
        final bottomHeight = bottomText == null
            ? 0.0
            : bottomBandHeightOverride ??
                  TagPresentationSlideFrameLayout.bandHeight(
                    availableHeight,
                    bottomText,
                  );
        final layout = TagPresentationSlideFrameLayout(
          slideSize: Size(constraints.maxWidth, constraints.maxHeight),
          topBandHeight: topHeight,
          bottomBandHeight: bottomHeight,
        );

        return TagPresentationSlideLayoutScope(
          layout: layout,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (topBand != null)
                topBand!
              else if (topText != null)
                SizedBox(
                  height: topHeight,
                  child: _TitleBand(text: topText),
                ),
              Expanded(child: body),
              if (bottomBand != null)
                bottomBand!
              else if (bottomText != null)
                SizedBox(
                  height: bottomHeight,
                  child: _TitleBand(text: bottomText),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TitleBand extends StatelessWidget {
  const _TitleBand({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Center(
        child: TagPresentationAutoFitText(
          text: text,
          style:
              theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFFF3EFE4),
              ) ??
              const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF3EFE4),
              ),
          minFontSize: 14,
          maxFontSize: 28,
          maxLines: 2,
          textAlign: TextAlign.center,
          height: 1.0,
        ),
      ),
    );
  }
}

String? _cleanText(String? value) {
  final cleaned = value?.trim() ?? '';
  return cleaned.isEmpty ? null : cleaned;
}
