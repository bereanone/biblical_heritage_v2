import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/database/user_database.dart';
import 'presentation_models.dart';
import 'note_image_layout.dart';
import 'presentation_slide_settings.dart';

class PresentationItemSettingsRepository {
  PresentationItemSettingsRepository._() : _database = null;
  PresentationItemSettingsRepository.forDatabase(Database database)
    : _database = database;
  final Database? _database;
  Future<Database> get _db async =>
      _database ?? await UserDatabase.instance.database;

  static final PresentationItemSettingsRepository instance =
      PresentationItemSettingsRepository._();

  static const _sourceTypeSlide = 'tag_slide';
  static const _sourceTypeElement = 'tag_slide_element';
  static const _sourceTypeImage = 'tag_slide_image';

  Future<Map<String, PresentationSlideSettings>> loadSlideSettingsForTag({
    required String tagFamily,
    required String tag,
  }) async {
    final db = await _db;
    final tagId = _tagIdentityHash(tagFamily: tagFamily, tag: tag);
    final rows = await db.query(
      'presentation_item_settings',
      columns: [
        'source_type',
        'source_id',
        'font_size_override',
        'alignment',
        'layout',
        'allow_scroll',
        'auto_fit',
      ],
      where: 'source_type IN (?, ?, ?) AND tag_id = ?',
      whereArgs: [_sourceTypeSlide, _sourceTypeElement, _sourceTypeImage, tagId],
      orderBy: 'updated_at DESC, id DESC',
    );
    final result = <String, PresentationSlideSettings>{};
    for (final row in rows) {
      final sourceId = row['source_id']?.toString().trim() ?? '';
      if (sourceId.isEmpty) continue;
      if (row['source_type'] == _sourceTypeSlide)
        result[sourceId] = _settingsFromRow(row);
    }
    for (final row in rows.where(
      (row) => row['source_type'] == _sourceTypeElement,
    )) {
      final identity = _elementIdentity(row['source_id']);
      final size = _doubleValueNullable(row['font_size_override']);
      final rawAlignment = row['alignment']?.toString();
      final alignment = PresentationAlignmentPreference.values
          .where(
            (value) =>
                presentationAlignmentPreferenceToJson(value) == rawAlignment,
          )
          .firstOrNull;
      final validSize =
          size != null && size.isFinite && size >= 12 && size <= 160;
      if (identity == null || (!validSize && alignment == null)) continue;
      final current =
          result[identity[0]] ?? PresentationSlideSettings.defaults();
      result[identity[0]] = current.copyWith(
        elementFontSizes: {
          ...current.elementFontSizes,
          if (validSize) identity[1]: size,
        },
        elementAlignments: {
          ...current.elementAlignments,
          if (alignment != null) identity[1]: alignment,
        },
      );
    }
    for (final row in rows.where((row) => row['source_type'] == _sourceTypeImage)) {
      final identity = _elementIdentity(row['source_id']);
      if (identity == null) continue;
      try {
        final layout = NoteImageLayout.fromJson(jsonDecode(row['layout']?.toString() ?? ''));
        if (layout == null) continue;
        final current = result[identity[0]] ?? PresentationSlideSettings.defaults();
        result[identity[0]] = current.copyWith(imageLayouts: {...current.imageLayouts, identity[1]: layout});
      } catch (_) { /* Ignore invalid optional image settings. */ }
    }
    return result;
  }

  Future<void> saveSlideSettingsForTag({
    required String tagFamily,
    required String tag,
    required PresentationSlide slide,
    required PresentationSlideSettings settings,
  }) async {
    final db = await _db;
    final tagId = _tagIdentityHash(tagFamily: tagFamily, tag: tag);
    await db.transaction((tx) async {
      await tx.insert(
        'presentation_item_settings',
        _row(tagId, _sourceTypeSlide, slide.settingsKey, settings),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final existing = await tx.query(
        'presentation_item_settings',
        columns: ['id', 'source_id'],
        where: 'source_type IN (?, ?) AND tag_id = ?',
        whereArgs: [_sourceTypeElement, _sourceTypeImage, tagId],
      );
      for (final row in existing) {
        if (_elementIdentity(row['source_id'])?.first == slide.settingsKey) {
          await tx.delete(
            'presentation_item_settings',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
      for (final entry in settings.imageLayouts.entries) {
        await tx.insert('presentation_item_settings', {
          ..._row(tagId, _sourceTypeImage, jsonEncode([slide.settingsKey, entry.key]), const PresentationSlideSettings()),
          'layout': jsonEncode(entry.value.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final keys = {
        ...settings.elementFontSizes.keys,
        ...settings.elementAlignments.keys,
      };
      for (final key in keys) {
        final size = settings.elementFontSizes[key];
        final validSize =
            size != null && size.isFinite && size >= 12 && size <= 160;
        final alignment = settings.elementAlignments[key];
        if (!validSize && alignment == null) continue;
        await tx.insert(
          'presentation_item_settings',
          _row(
            tagId,
            _sourceTypeElement,
            jsonEncode([slide.settingsKey, key]),
            PresentationSlideSettings(
              fontSizeOverride: validSize ? size : null,
              alignmentOverride: alignment,
            ),
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
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
    final db = await _db;
    final tagId = _tagIdentityHash(tagFamily: tagFamily, tag: tag);
    await db.insert(
      'presentation_item_settings',
      _row(tagId, normalizedSourceType, normalizedSourceId, settings),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, Object?> _row(
    int tagId,
    String type,
    String sourceId,
    PresentationSlideSettings settings,
  ) => {
    'source_type': type,
    'source_id': sourceId,
    'tag_id': tagId,
    'font_size_override': settings.fontSizeOverride,
    'alignment': settings.alignmentOverride == null
        ? null
        : presentationAlignmentPreferenceToJson(settings.alignmentOverride!),
    'layout': settings.layoutOverride == null
        ? null
        : presentationLayoutPreferenceToJson(settings.layoutOverride!),
    'allow_scroll': settings.allowScroll ? 1 : 0,
    'auto_fit': settings.autoFitEnabled ? 1 : 0,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  List<String>? _elementIdentity(Object? value) {
    try {
      final decoded = jsonDecode(value?.toString() ?? '');
      if (decoded is List &&
          decoded.length == 2 &&
          decoded.every((v) => v is String && v.isNotEmpty)) {
        return decoded.cast<String>();
      }
    } catch (_) {
      /* Ignore unrelated or malformed saved rows. */
    }
    return null;
  }

  Future<void> deleteSettingsForTag({
    required String tagFamily,
    required String tag,
  }) async {
    final db = await _db;
    final tagId = _tagIdentityHash(tagFamily: tagFamily, tag: tag);
    await db.delete(
      'presentation_item_settings',
      where: 'source_type IN (?, ?, ?) AND tag_id = ?',
      whereArgs: [_sourceTypeSlide, _sourceTypeElement, _sourceTypeImage, tagId],
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

  int _tagIdentityHash({required String tagFamily, required String tag}) {
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
