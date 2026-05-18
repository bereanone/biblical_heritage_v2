import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/database/user_database.dart';
import 'presentation_models.dart';
import 'presentation_slide_settings.dart';

class PresentationItemSettingsRepository {
  PresentationItemSettingsRepository._();

  static final PresentationItemSettingsRepository instance =
      PresentationItemSettingsRepository._();

  static const _sourceTypeSlide = 'tag_slide';

  Future<Map<String, PresentationSlideSettings>> loadSlideSettingsForTag({
    required String tagFamily,
    required String tag,
  }) async {
    final db = await UserDatabase.instance.database;
    final tagId = _tagIdentityHash(tagFamily: tagFamily, tag: tag);
    final rows = await db.query(
      'presentation_item_settings',
      columns: [
        'source_id',
        'font_size_override',
        'alignment',
        'layout',
        'allow_scroll',
        'auto_fit',
      ],
      where: 'source_type = ? AND tag_id = ?',
      whereArgs: [_sourceTypeSlide, tagId],
      orderBy: 'updated_at DESC, id DESC',
    );
    final result = <String, PresentationSlideSettings>{};
    for (final row in rows) {
      final sourceId = row['source_id']?.toString().trim() ?? '';
      if (sourceId.isEmpty) continue;
      result[sourceId] = _settingsFromRow(row);
    }
    return result;
  }

  Future<void> saveSlideSettingsForTag({
    required String tagFamily,
    required String tag,
    required PresentationSlide slide,
    required PresentationSlideSettings settings,
  }) async {
    await saveSettingsForSource(
      tagFamily: tagFamily,
      tag: tag,
      sourceType: _sourceTypeSlide,
      sourceId: slide.settingsKey,
      settings: settings,
    );
  }

  Future<void> saveSettingsForSource({
    required String tagFamily,
    required String tag,
    required String sourceType,
    required String sourceId,
    required PresentationSlideSettings settings,
  }) async {
    final normalizedSourceType = sourceType.trim();
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceType.isEmpty || normalizedSourceId.isEmpty) return;
    final db = await UserDatabase.instance.database;
    final tagId = _tagIdentityHash(tagFamily: tagFamily, tag: tag);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'presentation_item_settings',
      {
        'source_type': normalizedSourceType,
        'source_id': normalizedSourceId,
        'tag_id': tagId,
        'font_size_override': settings.fontSizeOverride,
        'alignment': settings.alignmentOverride == null
            ? null
            : presentationAlignmentPreferenceToJson(
                settings.alignmentOverride!,
              ),
        'layout': settings.layoutOverride == null
            ? null
            : presentationLayoutPreferenceToJson(settings.layoutOverride!),
        'allow_scroll': settings.allowScroll ? 1 : 0,
        'auto_fit': settings.autoFitEnabled ? 1 : 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteSettingsForTag({
    required String tagFamily,
    required String tag,
  }) async {
    final db = await UserDatabase.instance.database;
    final tagId = _tagIdentityHash(tagFamily: tagFamily, tag: tag);
    await db.delete(
      'presentation_item_settings',
      where: 'source_type = ? AND tag_id = ?',
      whereArgs: [_sourceTypeSlide, tagId],
    );
  }

  PresentationSlideSettings _settingsFromRow(Map<String, Object?> row) {
    return PresentationSlideSettings(
      fontSizeOverride: _doubleValueNullable(row['font_size_override']),
      alignmentOverride: row['alignment'] == null
          ? null
          : presentationAlignmentPreferenceFromJson(
              row['alignment']?.toString(),
              fallback: PresentationAlignmentPreference.left,
            ),
      layoutOverride: row['layout'] == null
          ? null
          : presentationLayoutPreferenceFromJson(
              row['layout']?.toString(),
              fallback: PresentationLayoutPreference.auto,
            ),
      allowScroll: _boolValue(row['allow_scroll'], fallback: true),
      autoFitEnabled: _boolValue(row['auto_fit'], fallback: true),
    );
  }

  double? _doubleValueNullable(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  bool _boolValue(Object? value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is int) return value != 0;
    if (value is num) return value.toInt() != 0;
    final raw = value.toString().trim().toLowerCase();
    if (raw.isEmpty) return fallback;
    if (raw == '1' || raw == 'true') return true;
    if (raw == '0' || raw == 'false') return false;
    return fallback;
  }

  int _tagIdentityHash({
    required String tagFamily,
    required String tag,
  }) {
    final normalizedFamily = _normalizeSettingSegment(tagFamily);
    final normalizedTag = _normalizeSettingSegment(tag);
    return _fnv1a32('$normalizedFamily|$normalizedTag');
  }

  String _normalizeSettingSegment(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'^[#\$@]+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  int _fnv1a32(String value) {
    const int offsetBasis = 0x811C9DC5;
    const int prime = 0x01000193;
    var hash = offsetBasis;
    for (final rune in value.runes) {
      hash ^= rune;
      hash = (hash * prime) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}
