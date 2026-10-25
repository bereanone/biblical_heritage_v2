import 'package:flutter/painting.dart';
import 'presentation_models.dart';
import 'note_image_layout.dart';

enum PresentationAlignmentPreference { left, center, right, justify }

String presentationAlignmentPreferenceToJson(
  PresentationAlignmentPreference value,
) {
  return switch (value) {
    PresentationAlignmentPreference.left => 'left',
    PresentationAlignmentPreference.center => 'center',
    PresentationAlignmentPreference.right => 'right',
    PresentationAlignmentPreference.justify => 'justify',
  };
}

PresentationAlignmentPreference presentationAlignmentPreferenceFromJson(
  String? value, {
  PresentationAlignmentPreference fallback =
      PresentationAlignmentPreference.left,
}) {
  return switch (value) {
    'center' => PresentationAlignmentPreference.center,
    'right' => PresentationAlignmentPreference.right,
    'left' => PresentationAlignmentPreference.left,
    'justify' => PresentationAlignmentPreference.justify,
    _ => fallback,
  };
}

String presentationAlignmentPreferenceLabel(
  PresentationAlignmentPreference value,
) {
  return switch (value) {
    PresentationAlignmentPreference.left => 'Left',
    PresentationAlignmentPreference.center => 'Center',
    PresentationAlignmentPreference.right => 'Right',
    PresentationAlignmentPreference.justify => 'Justify',
  };
}

TextAlign presentationAlignmentTextAlign(
  PresentationAlignmentPreference alignment,
) => switch (alignment) {
  PresentationAlignmentPreference.left => TextAlign.left,
  PresentationAlignmentPreference.center => TextAlign.center,
  PresentationAlignmentPreference.right => TextAlign.right,
  PresentationAlignmentPreference.justify => TextAlign.justify,
};

class PresentationSlideSettings {
  const PresentationSlideSettings({
    this.fontSizeOverride,
    this.elementFontSizes = const {},
    this.imageLayouts = const {},
    this.elementAlignments = const {},
    this.alignmentOverride,
    this.layoutOverride,
    this.allowScroll = true,
    this.autoFitEnabled = true,
  });

  final double? fontSizeOverride;
  final Map<String, double> elementFontSizes;
  final Map<String, NoteImageLayout> imageLayouts;
  final Map<String, PresentationAlignmentPreference> elementAlignments;
  TextAlign alignmentFor(String key, TextAlign fallback) =>
      elementAlignments[key] == null
      ? fallback
      : presentationAlignmentTextAlign(elementAlignments[key]!);

  double fontSizeFor(String element, double fallback) =>
      elementFontSizes[element] ?? fallback;
  final PresentationAlignmentPreference? alignmentOverride;
  final PresentationLayoutPreference? layoutOverride;
  final bool allowScroll;
  final bool autoFitEnabled;

  PresentationSlideSettings copyWith({
    double? fontSizeOverride,
    Map<String, double>? elementFontSizes,
    Map<String, NoteImageLayout>? imageLayouts,
    Map<String, PresentationAlignmentPreference>? elementAlignments,
    PresentationAlignmentPreference? alignmentOverride,
    PresentationLayoutPreference? layoutOverride,
    bool? allowScroll,
    bool? autoFitEnabled,
    bool clearFontSizeOverride = false,
    bool clearAlignmentOverride = false,
    bool clearLayoutOverride = false,
  }) {
    return PresentationSlideSettings(
      imageLayouts: Map.unmodifiable(imageLayouts ?? this.imageLayouts),
      elementAlignments: Map.unmodifiable(
        elementAlignments ?? this.elementAlignments,
      ),
      elementFontSizes: Map.unmodifiable(
        elementFontSizes ?? this.elementFontSizes,
      ),
      fontSizeOverride: clearFontSizeOverride
          ? null
          : (fontSizeOverride ?? this.fontSizeOverride),
      alignmentOverride: clearAlignmentOverride
          ? null
          : (alignmentOverride ?? this.alignmentOverride),
      layoutOverride: clearLayoutOverride
          ? null
          : (layoutOverride ?? this.layoutOverride),
      allowScroll: allowScroll ?? this.allowScroll,
      autoFitEnabled: autoFitEnabled ?? this.autoFitEnabled,
    );
  }

  factory PresentationSlideSettings.defaults() {
    return const PresentationSlideSettings(
      fontSizeOverride: null,
      alignmentOverride: null,
      layoutOverride: null,
      allowScroll: true,
      autoFitEnabled: true,
    );
  }
}
