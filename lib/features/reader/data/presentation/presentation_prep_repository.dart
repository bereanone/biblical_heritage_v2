import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/database/user_database.dart';
import 'presentation_prep_db_models.dart';

// ---------------------------------------------------------------------------
// Save-request DTOs — built by the presentation layer, consumed by repository
// ---------------------------------------------------------------------------

class PresentationSaveRequest {
  const PresentationSaveRequest({
    required this.name,
    this.sourceTagId,
    this.sourceTagKey,
    this.sourceTagName,
    this.defaultDisplayTarget,
    required this.slides,
  });

  final String name;
  final String? sourceTagId;
  final String? sourceTagKey;
  final String? sourceTagName;
  final String? defaultDisplayTarget;
  final List<PresentationSlideSaveRequest> slides;
}

class PresentationSlideSaveRequest {
  const PresentationSlideSaveRequest({
    required this.slideOrder,
    required this.title,
    this.topHeaderText,
    this.bottomFooterText,
    required this.displayTarget,
    required this.aspectRatioPreset,
    required this.aspectRatioValue,
    required this.rows,
    required this.columns,
    required this.zones,
  });

  final int slideOrder;
  final String title;
  final String? topHeaderText;
  final String? bottomFooterText;
  final String displayTarget;
  final String aspectRatioPreset;
  final double aspectRatioValue;
  final int rows;
  final int columns;
  final List<PresentationZoneSaveRequest> zones;
}

class PresentationZoneSaveRequest {
  const PresentationZoneSaveRequest({
    required this.zoneKey,
    required this.zoneType,
    required this.startRow,
    required this.startColumn,
    required this.rowSpan,
    required this.columnSpan,
    required this.items,
  });

  final String zoneKey;
  final String zoneType;
  final int startRow;
  final int startColumn;
  final int rowSpan;
  final int columnSpan;
  final List<PresentationItemSaveRequest> items;
}

class PresentationItemSaveRequest {
  const PresentationItemSaveRequest({
    required this.itemOrder,
    this.sourceItemId,
    this.itemType,
    this.titleOverride,
    this.bodyOverride,
    this.mediaPath,
    this.mediaCaption,
  });

  final int itemOrder;
  final String? sourceItemId;
  final String? itemType;
  final String? titleOverride;
  final String? bodyOverride;
  final String? mediaPath;
  final String? mediaCaption;
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class PresentationPrepRepository {
  PresentationPrepRepository._();

  static final PresentationPrepRepository instance =
      PresentationPrepRepository._();

  /// Saves the presentation. If a group with the same name already exists
  /// (case-insensitive), its slides are replaced. Returns the group id.
  ///
  /// The entire operation (locate existing, delete old children, upsert group,
  /// insert slides/profiles/zones/items) runs inside a single SQLite
  /// transaction so a mid-save crash cannot leave the database in a partial
  /// state.
  Future<int> savePresentation(PresentationSaveRequest request) async {
    final db = await UserDatabase.instance.database;
    final now = _utcNow();
    final trimmedName = request.name.trim();

    return db.transaction((txn) async {
      int groupId;
      final existing = await txn.query(
        'presentation_groups',
        columns: ['id'],
        where: 'LOWER(name) = LOWER(?) AND deleted_at IS NULL',
        whereArgs: [trimmedName],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        groupId = (existing.first['id'] as int?) ?? 0;
        await _deleteChildRecords(txn, groupId);
        await txn.update(
          'presentation_groups',
          {
            'source_tag_id': request.sourceTagId,
            'source_tag_key': request.sourceTagKey,
            'source_tag_name': request.sourceTagName,
            'default_display_target': request.defaultDisplayTarget,
            'updated_at': now,
            'deleted_at': null,
          },
          where: 'id = ?',
          whereArgs: [groupId],
        );
      } else {
        groupId = await txn.insert('presentation_groups', {
          'name': trimmedName,
          'source_tag_id': request.sourceTagId,
          'source_tag_key': request.sourceTagKey,
          'source_tag_name': request.sourceTagName,
          'default_display_target': request.defaultDisplayTarget,
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
        });
      }

      for (final slide in request.slides) {
        await _saveSlide(db: txn, groupId: groupId, slide: slide, now: now);
      }

      return groupId;
    });
  }

  /// Lists all saved presentation groups (newest first), including slide count.
  Future<List<PresentationGroupRecord>> listPresentations() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT g.id, g.name, g.source_tag_id, g.source_tag_key, g.source_tag_name,
             g.default_display_target, g.created_at, g.updated_at,
             COUNT(s.id) AS slide_count
      FROM presentation_groups g
      LEFT JOIN presentation_prep_slides s
        ON s.presentation_id = g.id AND s.deleted_at IS NULL
      WHERE g.deleted_at IS NULL
      GROUP BY g.id
      ORDER BY g.updated_at DESC
    ''');
    return [for (final row in rows) PresentationGroupRecord.fromRow(row)];
  }

  /// Loads a single presentation with all its slides, profiles, zones, and items.
  /// Returns null if the presentation does not exist or is deleted.
  Future<PresentationLoadedGroup?> loadPresentation(int presentationId) async {
    final db = await UserDatabase.instance.database;

    final groupRows = await db.query(
      'presentation_groups',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [presentationId],
      limit: 1,
    );
    if (groupRows.isEmpty) return null;
    final group = PresentationGroupRecord.fromRow(groupRows.first);

    final slideRows = await db.query(
      'presentation_prep_slides',
      where: 'presentation_id = ? AND deleted_at IS NULL',
      whereArgs: [presentationId],
      orderBy: 'slide_order ASC',
    );

    final loadedSlides = <PresentationLoadedSlide>[];
    for (final slideRow in slideRows) {
      final slide = PresentationSlideRecord.fromRow(slideRow);

      final profileRows = await db.query(
        'presentation_prep_profiles',
        where: 'slide_id = ?',
        whereArgs: [slide.id],
        limit: 1,
      );
      final profile = profileRows.isNotEmpty
          ? PresentationProfileRecord.fromRow(profileRows.first)
          : null;

      final zones = <PresentationZoneRecord>[];
      if (profile != null) {
        final zoneRows = await db.query(
          'presentation_prep_zones',
          where: 'profile_id = ?',
          whereArgs: [profile.id],
        );
        zones.addAll(zoneRows.map(PresentationZoneRecord.fromRow));
      }

      final itemRows = await db.query(
        'presentation_prep_items',
        where: 'slide_id = ?',
        whereArgs: [slide.id],
        orderBy: 'item_order ASC',
      );
      final items = itemRows.map(PresentationItemRecord.fromRow).toList();

      loadedSlides.add(PresentationLoadedSlide(
        slide: slide,
        profile: profile,
        zones: zones,
        items: items,
      ));
    }

    return PresentationLoadedGroup(group: group, slides: loadedSlides);
  }

  /// Renames a presentation. Throws [ArgumentError] for empty names.
  /// Throws [StateError] if another presentation with that name already exists.
  Future<void> renamePresentation(int presentationId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw ArgumentError('Presentation name cannot be empty.');

    final db = await UserDatabase.instance.database;

    final conflict = await db.query(
      'presentation_groups',
      columns: ['id'],
      where: 'LOWER(name) = LOWER(?) AND deleted_at IS NULL AND id != ?',
      whereArgs: [trimmed, presentationId],
      limit: 1,
    );
    if (conflict.isNotEmpty) {
      throw StateError('A presentation named "$trimmed" already exists.');
    }

    await db.update(
      'presentation_groups',
      {'name': trimmed, 'updated_at': _utcNow()},
      where: 'id = ?',
      whereArgs: [presentationId],
    );
  }

  /// Soft-deletes a presentation by setting deleted_at. The presentation will
  /// no longer appear in [listPresentations].
  Future<void> deletePresentation(int presentationId) async {
    final db = await UserDatabase.instance.database;
    final now = _utcNow();
    await db.update(
      'presentation_groups',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [presentationId],
    );
  }

  /// Returns ordered slide records for a presentation.
  Future<List<PresentationSlideRecord>> listSlidesForPresentation(
    int presentationId,
  ) async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'presentation_prep_slides',
      where: 'presentation_id = ? AND deleted_at IS NULL',
      whereArgs: [presentationId],
      orderBy: 'slide_order ASC',
    );
    return rows.map(PresentationSlideRecord.fromRow).toList();
  }

  /// Moves a slide one position earlier in the presentation. No-op if first.
  Future<void> moveSlideUp({
    required int presentationId,
    required int slideId,
  }) =>
      _swapSlideOrder(
        presentationId: presentationId,
        slideId: slideId,
        direction: -1,
      );

  /// Moves a slide one position later in the presentation. No-op if last.
  Future<void> moveSlideDown({
    required int presentationId,
    required int slideId,
  }) =>
      _swapSlideOrder(
        presentationId: presentationId,
        slideId: slideId,
        direction: 1,
      );

  Future<void> _swapSlideOrder({
    required int presentationId,
    required int slideId,
    required int direction,
  }) async {
    final db = await UserDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'presentation_prep_slides',
        columns: ['id', 'slide_order'],
        where: 'presentation_id = ? AND deleted_at IS NULL',
        whereArgs: [presentationId],
        orderBy: 'slide_order ASC',
      );
      if (rows.length < 2) return;

      final ids = rows.map((r) => r['id'] as int).toList();
      final orders = rows.map((r) => r['slide_order'] as int).toList();

      final pos = ids.indexOf(slideId);
      if (pos < 0) return;
      final targetPos = pos + direction;
      if (targetPos < 0 || targetPos >= ids.length) return;

      final now = _utcNow();
      await txn.update(
        'presentation_prep_slides',
        {'slide_order': orders[targetPos], 'updated_at': now},
        where: 'id = ?',
        whereArgs: [ids[pos]],
      );
      await txn.update(
        'presentation_prep_slides',
        {'slide_order': orders[pos], 'updated_at': now},
        where: 'id = ?',
        whereArgs: [ids[targetPos]],
      );
    });
  }

  /// Copies a slide (profile, zones, and items) into [targetPresentationId].
  /// The copy is appended after the last existing slide. Media paths are
  /// preserved by reference; no files are duplicated. Uses a transaction so
  /// partial copies cannot occur.
  Future<void> duplicateSlideToPresentation({
    required int sourceSlideId,
    required int targetPresentationId,
  }) async {
    final db = await UserDatabase.instance.database;
    final now = _utcNow();

    await db.transaction((txn) async {
      final slideRows = await txn.query(
        'presentation_prep_slides',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [sourceSlideId],
        limit: 1,
      );
      if (slideRows.isEmpty) {
        throw StateError('Source slide not found or deleted.');
      }
      final src = slideRows.first;

      final orderRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(slide_order), -1) + 1 AS next_order '
        'FROM presentation_prep_slides '
        'WHERE presentation_id = ? AND deleted_at IS NULL',
        [targetPresentationId],
      );
      final nextOrder = (orderRows.first['next_order'] as int?) ?? 0;

      final newSlideId = await txn.insert('presentation_prep_slides', {
        'presentation_id': targetPresentationId,
        'slide_order': nextOrder,
        'title': src['title'],
        'top_header_text': src['top_header_text'],
        'bottom_footer_text': src['bottom_footer_text'],
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      });

      final profileRows = await txn.query(
        'presentation_prep_profiles',
        where: 'slide_id = ?',
        whereArgs: [sourceSlideId],
        limit: 1,
      );
      if (profileRows.isNotEmpty) {
        final srcProfile = profileRows.first;
        final newProfileId = await txn.insert('presentation_prep_profiles', {
          'slide_id': newSlideId,
          'display_target': srcProfile['display_target'],
          'aspect_ratio_preset': srcProfile['aspect_ratio_preset'],
          'aspect_ratio_value': srcProfile['aspect_ratio_value'],
          'rows': srcProfile['rows'],
          'columns': srcProfile['columns'],
          'created_at': now,
          'updated_at': now,
        });
        final zoneRows = await txn.query(
          'presentation_prep_zones',
          where: 'profile_id = ?',
          whereArgs: [srcProfile['id'] as int],
        );
        for (final zone in zoneRows) {
          await txn.insert('presentation_prep_zones', {
            'profile_id': newProfileId,
            'zone_key': zone['zone_key'],
            'zone_type': zone['zone_type'],
            'start_row': zone['start_row'],
            'start_column': zone['start_column'],
            'row_span': zone['row_span'],
            'column_span': zone['column_span'],
            'created_at': now,
            'updated_at': now,
          });
        }
      }

      final itemRows = await txn.query(
        'presentation_prep_items',
        where: 'slide_id = ?',
        whereArgs: [sourceSlideId],
        orderBy: 'item_order ASC',
      );
      for (final item in itemRows) {
        await txn.insert('presentation_prep_items', {
          'slide_id': newSlideId,
          'zone_key': item['zone_key'],
          'item_order': item['item_order'],
          'source_item_id': item['source_item_id'],
          'item_type': item['item_type'],
          'title_override': item['title_override'],
          'body_override': item['body_override'],
          'media_path': item['media_path'],
          'media_caption': item['media_caption'],
          'style_overrides_json': item['style_overrides_json'],
          'created_at': now,
          'updated_at': now,
        });
      }

      await txn.update(
        'presentation_groups',
        {'updated_at': now},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [targetPresentationId],
      );
    });
  }

  // ---------------------------------------------------------------------------

  Future<void> _deleteChildRecords(DatabaseExecutor db, int groupId) async {
    final slideRows = await db.query(
      'presentation_prep_slides',
      columns: ['id'],
      where: 'presentation_id = ?',
      whereArgs: [groupId],
    );
    for (final slideRow in slideRows) {
      final slideId = (slideRow['id'] as int?) ?? 0;
      await db.delete(
        'presentation_prep_items',
        where: 'slide_id = ?',
        whereArgs: [slideId],
      );
      final profileRows = await db.query(
        'presentation_prep_profiles',
        columns: ['id'],
        where: 'slide_id = ?',
        whereArgs: [slideId],
      );
      for (final profileRow in profileRows) {
        final profileId = (profileRow['id'] as int?) ?? 0;
        await db.delete(
          'presentation_prep_zones',
          where: 'profile_id = ?',
          whereArgs: [profileId],
        );
      }
      await db.delete(
        'presentation_prep_profiles',
        where: 'slide_id = ?',
        whereArgs: [slideId],
      );
    }
    await db.delete(
      'presentation_prep_slides',
      where: 'presentation_id = ?',
      whereArgs: [groupId],
    );
  }

  Future<void> _saveSlide({
    required DatabaseExecutor db,
    required int groupId,
    required PresentationSlideSaveRequest slide,
    required String now,
  }) async {
    final slideId = await db.insert('presentation_prep_slides', {
      'presentation_id': groupId,
      'slide_order': slide.slideOrder,
      'title': slide.title,
      'top_header_text': slide.topHeaderText,
      'bottom_footer_text': slide.bottomFooterText,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    });

    final profileId = await db.insert('presentation_prep_profiles', {
      'slide_id': slideId,
      'display_target': slide.displayTarget,
      'aspect_ratio_preset': slide.aspectRatioPreset,
      'aspect_ratio_value': slide.aspectRatioValue,
      'rows': slide.rows,
      'columns': slide.columns,
      'created_at': now,
      'updated_at': now,
    });

    for (final zone in slide.zones) {
      await db.insert('presentation_prep_zones', {
        'profile_id': profileId,
        'zone_key': zone.zoneKey,
        'zone_type': zone.zoneType,
        'start_row': zone.startRow,
        'start_column': zone.startColumn,
        'row_span': zone.rowSpan,
        'column_span': zone.columnSpan,
        'created_at': now,
        'updated_at': now,
      });

      for (final item in zone.items) {
        await db.insert('presentation_prep_items', {
          'slide_id': slideId,
          'zone_key': zone.zoneKey,
          'item_order': item.itemOrder,
          'source_item_id': item.sourceItemId,
          'item_type': item.itemType,
          'title_override': item.titleOverride,
          'body_override': item.bodyOverride,
          'media_path': item.mediaPath,
          'media_caption': item.mediaCaption,
          'style_overrides_json': null,
          'created_at': now,
          'updated_at': now,
        });
      }
    }
  }

  String _utcNow() {
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    return iso.contains('.')
        ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z')
        : iso;
  }
}
