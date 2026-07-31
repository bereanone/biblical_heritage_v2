class PresentationGroupRecord {
  const PresentationGroupRecord({
    required this.id,
    required this.name,
    this.sourceTagId,
    this.sourceTagKey,
    this.sourceTagName,
    this.defaultDisplayTarget,
    required this.createdAt,
    required this.updatedAt,
    this.slideCount = 0,
  });

  final int id;
  final String name;
  final String? sourceTagId;
  final String? sourceTagKey;
  final String? sourceTagName;
  final String? defaultDisplayTarget;
  final String createdAt;
  final String updatedAt;
  final int slideCount;

  factory PresentationGroupRecord.fromRow(Map<String, Object?> row) {
    return PresentationGroupRecord(
      id: (row['id'] as int?) ?? 0,
      name: row['name']?.toString() ?? '',
      sourceTagId: row['source_tag_id']?.toString(),
      sourceTagKey: row['source_tag_key']?.toString(),
      sourceTagName: row['source_tag_name']?.toString(),
      defaultDisplayTarget: row['default_display_target']?.toString(),
      createdAt: row['created_at']?.toString() ?? '',
      updatedAt: row['updated_at']?.toString() ?? '',
      slideCount: (row['slide_count'] as int?) ?? 0,
    );
  }
}

class PresentationSlideRecord {
  const PresentationSlideRecord({
    required this.id,
    required this.presentationId,
    required this.slideOrder,
    required this.title,
    this.topHeaderText,
    this.bottomFooterText,
    required this.updatedAt,
  });

  final int id;
  final int presentationId;
  final int slideOrder;
  final String title;
  final String? topHeaderText;
  final String? bottomFooterText;
  final String updatedAt;

  factory PresentationSlideRecord.fromRow(Map<String, Object?> row) {
    return PresentationSlideRecord(
      id: (row['id'] as int?) ?? 0,
      presentationId: (row['presentation_id'] as int?) ?? 0,
      slideOrder: (row['slide_order'] as int?) ?? 0,
      title: row['title']?.toString() ?? '',
      topHeaderText: row['top_header_text']?.toString(),
      bottomFooterText: row['bottom_footer_text']?.toString(),
      updatedAt: row['updated_at']?.toString() ?? '',
    );
  }
}

class PresentationProfileRecord {
  const PresentationProfileRecord({
    required this.id,
    required this.slideId,
    required this.displayTarget,
    required this.aspectRatioPreset,
    required this.aspectRatioValue,
    required this.rows,
    required this.columns,
  });

  final int id;
  final int slideId;
  final String displayTarget;
  final String aspectRatioPreset;
  final double aspectRatioValue;
  final int rows;
  final int columns;

  factory PresentationProfileRecord.fromRow(Map<String, Object?> row) {
    return PresentationProfileRecord(
      id: (row['id'] as int?) ?? 0,
      slideId: (row['slide_id'] as int?) ?? 0,
      displayTarget: row['display_target']?.toString() ?? '',
      aspectRatioPreset:
          row['aspect_ratio_preset']?.toString() ?? 'sixteenByNine',
      aspectRatioValue:
          (row['aspect_ratio_value'] as num?)?.toDouble() ?? (16 / 9),
      rows: (row['rows'] as int?) ?? 2,
      columns: (row['columns'] as int?) ?? 2,
    );
  }
}

class PresentationZoneRecord {
  const PresentationZoneRecord({
    required this.id,
    required this.profileId,
    required this.zoneKey,
    required this.zoneType,
    required this.startRow,
    required this.startColumn,
    required this.rowSpan,
    required this.columnSpan,
  });

  final int id;
  final int profileId;
  final String zoneKey;
  final String zoneType;
  final int startRow;
  final int startColumn;
  final int rowSpan;
  final int columnSpan;

  factory PresentationZoneRecord.fromRow(Map<String, Object?> row) {
    return PresentationZoneRecord(
      id: (row['id'] as int?) ?? 0,
      profileId: (row['profile_id'] as int?) ?? 0,
      zoneKey: row['zone_key']?.toString() ?? '',
      zoneType: row['zone_type']?.toString() ?? 'cell',
      startRow: (row['start_row'] as int?) ?? 0,
      startColumn: (row['start_column'] as int?) ?? 0,
      rowSpan: (row['row_span'] as int?) ?? 1,
      columnSpan: (row['column_span'] as int?) ?? 1,
    );
  }
}

class PresentationItemRecord {
  const PresentationItemRecord({
    required this.id,
    required this.slideId,
    required this.zoneKey,
    required this.itemOrder,
    this.sourceItemId,
    this.itemType,
    this.titleOverride,
    this.bodyOverride,
    this.mediaPath,
    this.mediaCaption,
  });

  final int id;
  final int slideId;
  final String zoneKey;
  final int itemOrder;
  final String? sourceItemId;
  final String? itemType;
  final String? titleOverride;
  final String? bodyOverride;
  final String? mediaPath;
  final String? mediaCaption;

  factory PresentationItemRecord.fromRow(Map<String, Object?> row) {
    return PresentationItemRecord(
      id: (row['id'] as int?) ?? 0,
      slideId: (row['slide_id'] as int?) ?? 0,
      zoneKey: row['zone_key']?.toString() ?? '',
      itemOrder: (row['item_order'] as int?) ?? 0,
      sourceItemId: row['source_item_id']?.toString(),
      itemType: row['item_type']?.toString(),
      titleOverride: row['title_override']?.toString(),
      bodyOverride: row['body_override']?.toString(),
      mediaPath: row['media_path']?.toString(),
      mediaCaption: row['media_caption']?.toString(),
    );
  }
}

class PresentationLoadedSlide {
  const PresentationLoadedSlide({
    required this.slide,
    this.profile,
    required this.zones,
    required this.items,
  });

  final PresentationSlideRecord slide;
  final PresentationProfileRecord? profile;
  final List<PresentationZoneRecord> zones;
  final List<PresentationItemRecord> items;
}

class PresentationLoadedGroup {
  const PresentationLoadedGroup({required this.group, required this.slides});

  final PresentationGroupRecord group;
  final List<PresentationLoadedSlide> slides;
}
