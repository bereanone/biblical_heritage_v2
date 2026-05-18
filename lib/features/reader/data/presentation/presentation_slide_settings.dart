import 'presentation_models.dart';

enum PresentationAlignmentPreference { left, center, right }

String presentationAlignmentPreferenceToJson(
  PresentationAlignmentPreference value,
) {
  return switch (value) {
    PresentationAlignmentPreference.left => 'left',
    PresentationAlignmentPreference.center => 'center',
    PresentationAlignmentPreference.right => 'right',
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
  };
}

class PresentationSlideSettings {
  const PresentationSlideSettings({
    this.fontSizeOverride,
    this.alignmentOverride,
    this.layoutOverride,
    this.allowScroll = true,
    this.autoFitEnabled = true,
  });

  final double? fontSizeOverride;
  final PresentationAlignmentPreference? alignmentOverride;
  final PresentationLayoutPreference? layoutOverride;
  final bool allowScroll;
  final bool autoFitEnabled;

  PresentationSlideSettings copyWith({
    double? fontSizeOverride,
    PresentationAlignmentPreference? alignmentOverride,
    PresentationLayoutPreference? layoutOverride,
    bool? allowScroll,
    bool? autoFitEnabled,
    bool clearFontSizeOverride = false,
    bool clearAlignmentOverride = false,
    bool clearLayoutOverride = false,
  }) {
    return PresentationSlideSettings(
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
