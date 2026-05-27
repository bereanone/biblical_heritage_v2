import '../../data/tags/unified_tag_models.dart';
import 'tag_slide_grid_models.dart';

enum TagPresentationAspectRatioPreset {
  sixteenByNine,
  fourByThree,
  sixteenByTen,
  nineBySixteen,
  custom,
}

class TagPresentationAspectRatio {
  const TagPresentationAspectRatio._({
    required this.preset,
    required this.customAspectRatio,
  });

  const TagPresentationAspectRatio.sixteenByNine()
    : this._(
        preset: TagPresentationAspectRatioPreset.sixteenByNine,
        customAspectRatio: 16 / 9,
      );

  const TagPresentationAspectRatio.fourByThree()
    : this._(
        preset: TagPresentationAspectRatioPreset.fourByThree,
        customAspectRatio: 4 / 3,
      );

  const TagPresentationAspectRatio.sixteenByTen()
    : this._(
        preset: TagPresentationAspectRatioPreset.sixteenByTen,
        customAspectRatio: 16 / 10,
      );

  const TagPresentationAspectRatio.nineBySixteen()
    : this._(
        preset: TagPresentationAspectRatioPreset.nineBySixteen,
        customAspectRatio: 9 / 16,
      );

  const TagPresentationAspectRatio.custom(double aspectRatio)
    : this._(
        preset: TagPresentationAspectRatioPreset.custom,
        customAspectRatio: aspectRatio,
      );

  final TagPresentationAspectRatioPreset preset;
  final double customAspectRatio;

  double get aspectRatio {
    final ratio = switch (preset) {
      TagPresentationAspectRatioPreset.sixteenByNine => 16 / 9,
      TagPresentationAspectRatioPreset.fourByThree => 4 / 3,
      TagPresentationAspectRatioPreset.sixteenByTen => 16 / 10,
      TagPresentationAspectRatioPreset.nineBySixteen => 9 / 16,
      TagPresentationAspectRatioPreset.custom => customAspectRatio,
    };
    return ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
  }

  String get label {
    return switch (preset) {
      TagPresentationAspectRatioPreset.sixteenByNine => '16:9 Widescreen',
      TagPresentationAspectRatioPreset.fourByThree => '4:3 Projector',
      TagPresentationAspectRatioPreset.sixteenByTen => '16:10',
      TagPresentationAspectRatioPreset.nineBySixteen => '9:16 Phone Portrait',
      TagPresentationAspectRatioPreset.custom => 'Custom',
    };
  }

  TagPresentationAspectRatio copyWith({
    TagPresentationAspectRatioPreset? preset,
    double? customAspectRatio,
  }) {
    return TagPresentationAspectRatio._(
      preset: preset ?? this.preset,
      customAspectRatio: customAspectRatio ?? this.customAspectRatio,
    );
  }
}

enum TagPresentationPrepZone {
  fullWidth,
  leftPane,
  rightPane,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  caption,
  overlay,
}

extension TagPresentationPrepZoneLabel on TagPresentationPrepZone {
  String get label {
    return switch (this) {
      TagPresentationPrepZone.fullWidth => 'Full Width',
      TagPresentationPrepZone.leftPane => 'Left',
      TagPresentationPrepZone.rightPane => 'Right',
      TagPresentationPrepZone.topLeft => 'Top Left',
      TagPresentationPrepZone.topRight => 'Top Right',
      TagPresentationPrepZone.bottomLeft => 'Bottom Left',
      TagPresentationPrepZone.bottomRight => 'Bottom Right',
      TagPresentationPrepZone.caption => 'Caption',
      TagPresentationPrepZone.overlay => 'Overlay',
    };
  }
}

enum TagPresentationLayoutPreset {
  fullWidth,
  textLeftNotesRight,
  textLeftImageRight,
  imageRight,
}

extension TagPresentationLayoutPresetLabel on TagPresentationLayoutPreset {
  String get label {
    return switch (this) {
      TagPresentationLayoutPreset.fullWidth => 'Full Width',
      TagPresentationLayoutPreset.textLeftNotesRight =>
        'Text Left / Notes Right',
      TagPresentationLayoutPreset.textLeftImageRight =>
        'Text Left / Image Right',
      TagPresentationLayoutPreset.imageRight => 'Image Right',
    };
  }
}

class TagPresentationPrepRequest {
  const TagPresentationPrepRequest({
    this.chainId,
    this.tagName,
    this.titleOverride,
    this.preferredStorageKinds = const [
      UnifiedTagStorageKind.unified,
      UnifiedTagStorageKind.hash,
    ],
  });

  final String? chainId;
  final String? tagName;
  final String? titleOverride;
  final List<UnifiedTagStorageKind> preferredStorageKinds;

  String get displayTitle {
    final override = titleOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
    final tag = tagName?.trim() ?? '';
    if (tag.isNotEmpty) return tag;
    return 'Presentation Preparation';
  }
}

class TagPresentationPrepPreview {
  const TagPresentationPrepPreview({
    required this.requestedTagName,
    required this.sourceSummary,
    required this.resolvedChains,
    required this.items,
    required this.slides,
  });

  final String requestedTagName;
  final String sourceSummary;
  final List<UnifiedTagChain> resolvedChains;
  final List<UnifiedTagChainItem> items;
  final List<TagPresentationPrepSlide> slides;

  bool get hasItems => items.isNotEmpty;
}

class TagPresentationCardDragData {
  const TagPresentationCardDragData({
    required this.itemId,
    this.sourceSlideIndex,
  });

  final String itemId;
  final int? sourceSlideIndex;
}

class TagPresentationPlacedCard {
  const TagPresentationPlacedCard({
    required this.itemId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.zOrder,
  });

  final String itemId;
  final double x;
  final double y;
  final double width;
  final double height;
  final int zOrder;

  TagPresentationPlacedCard copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    int? zOrder,
  }) {
    return TagPresentationPlacedCard(
      itemId: itemId,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      zOrder: zOrder ?? this.zOrder,
    );
  }
}

class TagPresentationPrepSlide {
  TagPresentationPrepSlide({
    required this.slideNumber,
    required this.label,
    required this.gridLayout,
    required this.isDraft,
    required this.aspectRatio,
    this.sourcePresentationSlideNumber,
    this.topHeaderText,
    this.bottomFooterText,
  });

  int slideNumber;
  String label;
  TagPresentationGridLayout gridLayout;
  bool isDraft;
  TagPresentationAspectRatio aspectRatio;
  final int? sourcePresentationSlideNumber;
  String? topHeaderText;
  String? bottomFooterText;

  List<TagPresentationGridCell> get sortedCells => gridLayout.sortedCells;

  bool get isBlank => gridLayout.isEmpty;
  int get placedCardCount => gridLayout.itemCount;

  List<String> get assignedItemIds => gridLayout.assignedItemIds;

  bool get hasTopHeader => (topHeaderText ?? '').trim().isNotEmpty;
  bool get hasBottomFooter => (bottomFooterText ?? '').trim().isNotEmpty;

  double get aspectRatioValue => aspectRatio.aspectRatio;

  TagPresentationGridCell? cellForItem(String itemId) {
    return gridLayout.cellForItem(itemId);
  }
}

extension TagPresentationPrepItemPresentation on UnifiedTagChainItem {
  bool get isPresentationTitle {
    final role = rawFields['presentation_role']
        ?.toString()
        .trim()
        .toLowerCase();
    return role == 'title';
  }
}
