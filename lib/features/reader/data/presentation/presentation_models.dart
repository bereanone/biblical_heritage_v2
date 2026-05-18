enum PresentationLayoutType {
  fullWidth,
  twoColumns,
  mainSidebar,
  topBottom,
  backgroundOverlay,
}

enum PresentationLayoutPreference {
  auto,
  textOnly,
  imageOnly,
  textLeftImageRight,
  imageLeftTextRight,
  textTopImageBottom,
  imageTopTextBottom,
  textLeftTwoThirdsImageRightOneThird,
  textLeftThreeQuarterImageRightOneQuarter,
  imageBackgroundTextOverlay,
  fullWidth,
  textLeftNotesRight,
  noteQuote,
}

const List<PresentationLayoutPreference> presentationLayoutPreferenceOptions =
    <PresentationLayoutPreference>[
  PresentationLayoutPreference.auto,
  PresentationLayoutPreference.textOnly,
  PresentationLayoutPreference.imageOnly,
  PresentationLayoutPreference.textLeftImageRight,
  PresentationLayoutPreference.imageLeftTextRight,
  PresentationLayoutPreference.textTopImageBottom,
  PresentationLayoutPreference.imageTopTextBottom,
  PresentationLayoutPreference.textLeftTwoThirdsImageRightOneThird,
  PresentationLayoutPreference.textLeftThreeQuarterImageRightOneQuarter,
  PresentationLayoutPreference.imageBackgroundTextOverlay,
];

String presentationLayoutPreferenceToJson(PresentationLayoutPreference value) {
  return switch (value) {
    PresentationLayoutPreference.auto => 'auto',
    PresentationLayoutPreference.textOnly => 'textOnly',
    PresentationLayoutPreference.imageOnly => 'imageOnly',
    PresentationLayoutPreference.textLeftImageRight => 'textLeftImageRight',
    PresentationLayoutPreference.imageLeftTextRight => 'imageLeftTextRight',
    PresentationLayoutPreference.textTopImageBottom => 'textTopImageBottom',
    PresentationLayoutPreference.imageTopTextBottom => 'imageTopTextBottom',
    PresentationLayoutPreference.textLeftTwoThirdsImageRightOneThird =>
      'textLeftTwoThirdsImageRightOneThird',
    PresentationLayoutPreference.textLeftThreeQuarterImageRightOneQuarter =>
      'textLeftThreeQuarterImageRightOneQuarter',
    PresentationLayoutPreference.imageBackgroundTextOverlay =>
      'imageBackgroundTextOverlay',
    PresentationLayoutPreference.fullWidth => 'fullWidth',
    PresentationLayoutPreference.textLeftNotesRight => 'textLeftNotesRight',
    PresentationLayoutPreference.noteQuote => 'noteQuote',
  };
}

PresentationLayoutPreference presentationLayoutPreferenceFromJson(
  String? value, {
  PresentationLayoutPreference fallback = PresentationLayoutPreference.auto,
}) {
  return switch (value) {
    'textOnly' => PresentationLayoutPreference.textOnly,
    'imageOnly' => PresentationLayoutPreference.imageOnly,
    'textLeftImageRight' => PresentationLayoutPreference.textLeftImageRight,
    'imageLeftTextRight' => PresentationLayoutPreference.imageLeftTextRight,
    'textTopImageBottom' => PresentationLayoutPreference.textTopImageBottom,
    'imageTopTextBottom' => PresentationLayoutPreference.imageTopTextBottom,
    'textLeftTwoThirdsImageRightOneThird' =>
      PresentationLayoutPreference.textLeftTwoThirdsImageRightOneThird,
    'textLeftThreeQuarterImageRightOneQuarter' =>
      PresentationLayoutPreference.textLeftThreeQuarterImageRightOneQuarter,
    'imageBackgroundTextOverlay' =>
      PresentationLayoutPreference.imageBackgroundTextOverlay,
    'fullWidth' => PresentationLayoutPreference.textOnly,
    'textLeftNotesRight' => PresentationLayoutPreference.textLeftImageRight,
    'noteQuote' => PresentationLayoutPreference.textOnly,
    'auto' => PresentationLayoutPreference.auto,
    _ => fallback,
  };
}

String presentationLayoutPreferenceLabel(PresentationLayoutPreference value) {
  return switch (value) {
    PresentationLayoutPreference.auto => 'Auto',
    PresentationLayoutPreference.textOnly => 'Text Only',
    PresentationLayoutPreference.imageOnly => 'Image Only',
    PresentationLayoutPreference.textLeftImageRight => 'Text Left / Image Right',
    PresentationLayoutPreference.imageLeftTextRight => 'Image Left / Text Right',
    PresentationLayoutPreference.textTopImageBottom => 'Text Top / Image Bottom',
    PresentationLayoutPreference.imageTopTextBottom => 'Image Top / Text Bottom',
    PresentationLayoutPreference.textLeftTwoThirdsImageRightOneThird =>
      'Text 2/3 Left + Image 1/3 Right',
    PresentationLayoutPreference.textLeftThreeQuarterImageRightOneQuarter =>
      'Text 3/4 Left + Image 1/4 Right',
    PresentationLayoutPreference.imageBackgroundTextOverlay =>
      'Image Background + Text Overlay',
    PresentationLayoutPreference.fullWidth => 'Text Only (Legacy)',
    PresentationLayoutPreference.textLeftNotesRight =>
      'Text Left / Notes Right (Legacy)',
    PresentationLayoutPreference.noteQuote => 'Note / Quote (Legacy)',
  };
}

enum PresentationItemPlacement {
  auto,
  full,
  left,
  right,
  top,
  bottom,
  center,
  background,
  notes,
  citation,
}

const List<PresentationItemPlacement> presentationItemPlacementOptions =
    <PresentationItemPlacement>[
  PresentationItemPlacement.auto,
  PresentationItemPlacement.full,
  PresentationItemPlacement.left,
  PresentationItemPlacement.right,
  PresentationItemPlacement.top,
  PresentationItemPlacement.bottom,
  PresentationItemPlacement.center,
  PresentationItemPlacement.background,
  PresentationItemPlacement.notes,
  PresentationItemPlacement.citation,
];

String presentationItemPlacementToJson(PresentationItemPlacement value) {
  return switch (value) {
    PresentationItemPlacement.auto => 'auto',
    PresentationItemPlacement.full => 'full',
    PresentationItemPlacement.left => 'left',
    PresentationItemPlacement.right => 'right',
    PresentationItemPlacement.top => 'top',
    PresentationItemPlacement.bottom => 'bottom',
    PresentationItemPlacement.center => 'center',
    PresentationItemPlacement.background => 'background',
    PresentationItemPlacement.notes => 'notes',
    PresentationItemPlacement.citation => 'citation',
  };
}

PresentationItemPlacement presentationItemPlacementFromJson(
  String? value, {
  PresentationItemPlacement fallback = PresentationItemPlacement.auto,
}) {
  return switch (value) {
    'full' => PresentationItemPlacement.full,
    'left' => PresentationItemPlacement.left,
    'right' => PresentationItemPlacement.right,
    'top' => PresentationItemPlacement.top,
    'bottom' => PresentationItemPlacement.bottom,
    'center' => PresentationItemPlacement.center,
    'background' => PresentationItemPlacement.background,
    'notes' => PresentationItemPlacement.notes,
    'citation' => PresentationItemPlacement.citation,
    'auto' => PresentationItemPlacement.auto,
    _ => fallback,
  };
}

String presentationItemPlacementLabel(PresentationItemPlacement value) {
  return switch (value) {
    PresentationItemPlacement.auto => 'Auto',
    PresentationItemPlacement.full => 'Full Slide',
    PresentationItemPlacement.left => 'Left',
    PresentationItemPlacement.right => 'Right',
    PresentationItemPlacement.top => 'Top',
    PresentationItemPlacement.bottom => 'Bottom',
    PresentationItemPlacement.center => 'Center',
    PresentationItemPlacement.background => 'Background',
    PresentationItemPlacement.notes => 'Notes Area',
    PresentationItemPlacement.citation => 'Citation Area',
  };
}

PresentationLayoutRegion presentationItemPlacementToLayoutRegion(
  PresentationItemPlacement value,
) {
  return switch (value) {
    PresentationItemPlacement.auto => PresentationLayoutRegion.full,
    PresentationItemPlacement.full => PresentationLayoutRegion.full,
    PresentationItemPlacement.left => PresentationLayoutRegion.left,
    PresentationItemPlacement.right => PresentationLayoutRegion.right,
    PresentationItemPlacement.top => PresentationLayoutRegion.top,
    PresentationItemPlacement.bottom => PresentationLayoutRegion.bottom,
    PresentationItemPlacement.center => PresentationLayoutRegion.main,
    PresentationItemPlacement.background => PresentationLayoutRegion.background,
    PresentationItemPlacement.notes => PresentationLayoutRegion.sidebar,
    PresentationItemPlacement.citation => PresentationLayoutRegion.caption,
  };
}

enum PresentationLayoutRegion {
  full,
  left,
  right,
  main,
  sidebar,
  top,
  bottom,
  background,
  overlay,
  footer,
  caption,
}

enum PresentationItemKind { verse, note }

String presentationLayoutTypeToJson(PresentationLayoutType value) {
  return switch (value) {
    PresentationLayoutType.fullWidth => 'fullWidth',
    PresentationLayoutType.twoColumns => 'twoColumns',
    PresentationLayoutType.mainSidebar => 'mainSidebar',
    PresentationLayoutType.topBottom => 'topBottom',
    PresentationLayoutType.backgroundOverlay => 'backgroundOverlay',
  };
}

PresentationLayoutType presentationLayoutTypeFromJson(
  String? value, {
  PresentationLayoutType fallback = PresentationLayoutType.fullWidth,
}) {
  return switch (value) {
    'twoColumns' => PresentationLayoutType.twoColumns,
    'mainSidebar' => PresentationLayoutType.mainSidebar,
    'topBottom' => PresentationLayoutType.topBottom,
    'backgroundOverlay' => PresentationLayoutType.backgroundOverlay,
    'fullWidth' => PresentationLayoutType.fullWidth,
    _ => fallback,
  };
}

String presentationLayoutRegionToJson(PresentationLayoutRegion value) {
  return switch (value) {
    PresentationLayoutRegion.full => 'full',
    PresentationLayoutRegion.left => 'left',
    PresentationLayoutRegion.right => 'right',
    PresentationLayoutRegion.main => 'main',
    PresentationLayoutRegion.sidebar => 'sidebar',
    PresentationLayoutRegion.top => 'top',
    PresentationLayoutRegion.bottom => 'bottom',
    PresentationLayoutRegion.background => 'background',
    PresentationLayoutRegion.overlay => 'overlay',
    PresentationLayoutRegion.footer => 'footer',
    PresentationLayoutRegion.caption => 'caption',
  };
}

PresentationLayoutRegion presentationLayoutRegionFromJson(
  String? value, {
  PresentationLayoutRegion fallback = PresentationLayoutRegion.full,
}) {
  return switch (value) {
    'left' => PresentationLayoutRegion.left,
    'right' => PresentationLayoutRegion.right,
    'main' => PresentationLayoutRegion.main,
    'sidebar' => PresentationLayoutRegion.sidebar,
    'top' => PresentationLayoutRegion.top,
    'bottom' => PresentationLayoutRegion.bottom,
    'background' => PresentationLayoutRegion.background,
    'overlay' => PresentationLayoutRegion.overlay,
    'footer' => PresentationLayoutRegion.footer,
    'caption' => PresentationLayoutRegion.caption,
    'full' => PresentationLayoutRegion.full,
    _ => fallback,
  };
}

String presentationItemKindToJson(PresentationItemKind value) {
  return switch (value) {
    PresentationItemKind.verse => 'verse',
    PresentationItemKind.note => 'note',
  };
}

PresentationItemKind presentationItemKindFromJson(
  String? value, {
  PresentationItemKind fallback = PresentationItemKind.verse,
}) {
  return switch (value) {
    'note' => PresentationItemKind.note,
    'verse' => PresentationItemKind.verse,
    _ => fallback,
  };
}

class PresentationSlide {
  PresentationSlide({
    required this.id,
    required this.settingsKey,
    required this.slideNumber,
    required this.layoutType,
    this.slideTitle,
    this.slideTitleFormatJson,
    this.legacyGroupKey,
    this.customLayoutJson,
    List<PresentationSlideItem> items = const <PresentationSlideItem>[],
  }) : items = List.unmodifiable(items);

  final String id;
  final String settingsKey;
  final String? slideTitle;
  final String? slideTitleFormatJson;
  final String? legacyGroupKey;
  final int slideNumber;
  final PresentationLayoutType layoutType;
  final String? customLayoutJson;
  final List<PresentationSlideItem> items;
}

class PresentationSlideItem {
  PresentationSlideItem({
    required this.id,
    required this.presentationSlideId,
    required this.sourceType,
    required this.sourceId,
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.verseEnd,
    required this.layoutRegion,
    required this.layoutOrder,
    required this.itemKind,
    required this.displayTitle,
    required this.displayText,
    this.itemPlacement = PresentationItemPlacement.auto,
    this.citationText,
    this.legacyItemId,
    this.noteText,
    this.noteFormatJson,
    this.displayTextFormatJson,
    List<String>? mediaRefs,
  }) : mediaRefs = mediaRefs == null ? null : List.unmodifiable(mediaRefs);

  final String id;
  final String presentationSlideId;
  final String sourceType;
  final String sourceId;
  final String? legacyItemId;
  final int bookNumber;
  final int chapter;
  final int verse;
  final int verseEnd;
  final PresentationLayoutRegion layoutRegion;
  final int layoutOrder;
  final PresentationItemKind itemKind;
  final String displayTitle;
  final String displayText;
  final PresentationItemPlacement itemPlacement;
  final String? citationText;
  final String? noteText;
  final String? noteFormatJson;
  final String? displayTextFormatJson;
  final List<String>? mediaRefs;

  String get stableSourceKey => '$sourceType:$sourceId';
}
