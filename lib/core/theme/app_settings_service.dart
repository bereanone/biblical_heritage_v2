import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/user_database.dart';
import '../../features/library/presentation/mac_reader_autoscroll_controller.dart';
import '../../features/library/presentation/reader_tilt_preferences.dart';
import 'app_theme_mode.dart';
import '../../features/reader/data/presentation/presentation_models.dart';
import '../../features/reader/presentation/viewer_interlinear_settings.dart';
import '../../features/reader/presentation/viewer_presentation_settings.dart';

class AppVisualSettings {
  const AppVisualSettings({
    required this.backgroundColor,
    required this.textColor,
    required this.appBarColor,
    required this.bottomBarColor,
    required this.accentColor,
    required this.viewerFontScale,
  });

  final Color backgroundColor;
  final Color textColor;
  final Color appBarColor;
  final Color bottomBarColor;
  final Color accentColor;
  final double viewerFontScale;

  AppVisualSettings copyWith({
    Color? backgroundColor,
    Color? textColor,
    Color? appBarColor,
    Color? bottomBarColor,
    Color? accentColor,
    double? viewerFontScale,
  }) {
    return AppVisualSettings(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      appBarColor: appBarColor ?? this.appBarColor,
      bottomBarColor: bottomBarColor ?? this.bottomBarColor,
      accentColor: accentColor ?? this.accentColor,
      viewerFontScale: viewerFontScale ?? this.viewerFontScale,
    );
  }
}

class AppSettingsService {
  AppSettingsService._();

  static final AppSettingsService instance = AppSettingsService._();

  static const _backgroundKey = 'theme.color.background';
  static const _textKey = 'theme.color.text';
  static const _appBarKey = 'theme.color.appbar';
  static const _bottomBarKey = 'theme.color.bottombar';
  static const _accentKey = 'theme.color.accent';
  static const _viewerFontSizeKey = 'viewer.font_size';
  static const _elibraryZoomScaleKey = 'viewer.elibrary.zoom_scale';
  static const _defaultHighlightGroupKey = 'viewer.markup.default_group_id';
  static const _defaultElibraryHighlightColorKey =
      'viewer.elibrary.highlight.color_hex';
  static const _interlinearEnabledKey = 'viewer.interlinear.enabled';
  static const _interlinearEnglishOrderKey = 'viewer.interlinear.english_order';
  static const _interlinearShowEnglishGlossKey =
      'viewer.interlinear.show_english_gloss';
  static const _interlinearShowOriginalTextKey =
      'viewer.interlinear.show_original_text';
  static const _interlinearShowTransliterationKey =
      'viewer.interlinear.show_transliteration';
  static const _interlinearShowPronunciationKey =
      'viewer.interlinear.show_pronunciation';
  static const _interlinearShowStrongsNumberKey =
      'viewer.interlinear.show_strongs_number';
  static const _interlinearShowMorphologyKey =
      'viewer.interlinear.show_morphology';
  static const _lastTagTabIndexKey = 'viewer.tag.last_tab_index';
  static const _activeTagFamilyKey = 'viewer.tag.active_family';
  static const _presentationAspectRatioKey = 'viewer.presentation.aspect_ratio';
  static const _tagPresentationLayoutKeyPrefix = 'tags.presentation_layout.';
  static const _churchAutoMuteEnabledKey = 'utilities.church_auto_mute.enabled';
  static const _lastBibleSearchKey = 'search.last_bible_search';
  static const _lastBibleSearchSessionKey = 'search.last_bible_search_session';
  static const _lastElibrarySearchKey = 'search.last_elibrary_search';
  static const _lastElibrarySearchSessionKey =
      'search.last_elibrary_search_session';
  static const _elibraryMediaFilterKey = 'library.media_filter';
  static const _elibraryCollectionFilterKey = 'library.collection_filter';

  /// Generic single-key string accessor for callers (e.g. platform storage
  /// policy preferences) that don't warrant a dedicated typed key constant
  /// pair here.
  Future<String?> loadRawSetting(String key) async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value']?.toString();
  }

  Future<void> saveRawSetting(String key, String value) async {
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> loadElibraryMediaFilter() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_elibraryMediaFilterKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value']?.toString();
  }

  Future<void> saveElibraryMediaFilter(String value) async {
    await (await UserDatabase.instance.database).insert('app_settings', {
      'key': _elibraryMediaFilterKey,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> loadElibraryCollectionFilter() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_elibraryCollectionFilterKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value']?.toString();
  }

  Future<void> saveElibraryCollectionFilter(String value) async {
    await (await UserDatabase.instance.database).insert('app_settings', {
      'key': _elibraryCollectionFilterKey,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AppVisualSettings> loadVisualSettings(AppThemeMode mode) async {
    final db = await UserDatabase.instance.database;
    final preset = presetForMode(mode);
    final rows = await db.query(
      'app_settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?, ?, ?, ?, ?)',
      whereArgs: [
        _backgroundKey,
        _textKey,
        _appBarKey,
        _bottomBarKey,
        _accentKey,
        _viewerFontSizeKey,
      ],
    );

    final values = <String, String>{
      for (final row in rows) row['key'] as String: row['value'] as String,
    };

    final loaded = AppVisualSettings(
      backgroundColor:
          _parseColor(values[_backgroundKey]) ?? preset.backgroundColor,
      textColor: _parseColor(values[_textKey]) ?? preset.textColor,
      appBarColor: _parseColor(values[_appBarKey]) ?? preset.appBarColor,
      bottomBarColor:
          _parseColor(values[_bottomBarKey]) ?? preset.bottomBarColor,
      accentColor: _parseColor(values[_accentKey]) ?? preset.accentColor,
      viewerFontScale:
          double.tryParse(values[_viewerFontSizeKey] ?? '') ??
          preset.viewerFontScale,
    );
    return _looksReadable(loaded) ? loaded : preset;
  }

  Future<void> applyThemePreset(AppThemeMode mode) async {
    final db = await UserDatabase.instance.database;
    final preset = presetForMode(mode);
    final batch = db.batch();
    batch.insert('app_settings', {
      'key': _backgroundKey,
      'value': _hexFromColor(preset.backgroundColor),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert('app_settings', {
      'key': _textKey,
      'value': _hexFromColor(preset.textColor),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert('app_settings', {
      'key': _appBarKey,
      'value': _hexFromColor(preset.appBarColor),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert('app_settings', {
      'key': _bottomBarKey,
      'value': _hexFromColor(preset.bottomBarColor),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert('app_settings', {
      'key': _accentKey,
      'value': _hexFromColor(preset.accentColor),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  Future<void> saveViewerFontScale(double value) async {
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': _viewerFontSizeKey,
      'value': value.toStringAsFixed(2),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double> loadViewerFontScale() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_viewerFontSizeKey],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final value = double.tryParse(rows.first['value']?.toString() ?? '');
      if (value != null && value.isFinite && value > 0) {
        return value;
      }
    }
    return presetForMode(AppThemeMode.sepia).viewerFontScale;
  }

  static const _macAutoscrollBaseSpeedKey = 'mac_autoscroll_base_speed';
  static const _macAutoscrollLastStepKey = 'mac_autoscroll_last_nonzero_step';
  static const _macAutoscrollMaximumStepKey = 'mac_autoscroll_maximum_step';

  Future<MacAutoscrollPreferences> loadMacAutoscrollPreferences() async {
    final tiltPreferences = await const ReaderTiltPreferencesStore().load();
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: const ['key', 'value'],
      where: 'key IN (?, ?, ?)',
      whereArgs: const [
        _macAutoscrollBaseSpeedKey,
        _macAutoscrollLastStepKey,
        _macAutoscrollMaximumStepKey,
      ],
    );
    final values = <String, String>{
      for (final row in rows)
        row['key'].toString(): row['value']?.toString() ?? '',
    };
    return MacAutoscrollPreferences.fromStoredValues(
      baseSpeed: values[_macAutoscrollBaseSpeedKey],
      lastNonzeroStep: values[_macAutoscrollLastStepKey],
      maximumStep: values[_macAutoscrollMaximumStepKey],
      statusBannerMode: tiltPreferences.statusBannerMode,
    );
  }

  Future<void> saveMacAutoscrollPreferences(
    MacAutoscrollPreferences preferences,
  ) async {
    final tiltStore = const ReaderTiltPreferencesStore();
    final tiltPreferences = await tiltStore.load();
    await tiltStore.save(
      tiltPreferences.copyWith(statusBannerMode: preferences.statusBannerMode),
    );
    final db = await UserDatabase.instance.database;
    final batch = db.batch();
    batch.insert('app_settings', {
      'key': _macAutoscrollBaseSpeedKey,
      'value': preferences.baseSpeed.toStringAsFixed(1),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert('app_settings', {
      'key': _macAutoscrollLastStepKey,
      'value': preferences.lastNonzeroStep.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert('app_settings', {
      'key': _macAutoscrollMaximumStepKey,
      'value': preferences.maximumStep.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  Future<void> saveElibraryZoomScale(double value) async {
    final db = await UserDatabase.instance.database;
    final normalized = value.isFinite
        ? value.clamp(0.85, 1.60).toDouble()
        : 1.0;
    await db.insert('app_settings', {
      'key': _elibraryZoomScaleKey,
      'value': normalized.toStringAsFixed(2),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double> loadElibraryZoomScale() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_elibraryZoomScaleKey],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final value = double.tryParse(rows.first['value']?.toString() ?? '');
      if (value != null && value.isFinite && value > 0) {
        // The older eLibrary reader treated 170% as the implicit baseline.
        // Normalize that exact legacy value back to the new honest 100% base.
        if ((value - 1.70).abs() < 0.005) {
          await saveElibraryZoomScale(1.0);
          return 1.0;
        }
        return value.clamp(0.85, 1.60).toDouble();
      }
    }
    return 1.0;
  }

  Future<int?> loadDefaultHighlightGroupId() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_defaultHighlightGroupKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return int.tryParse(rows.first['value'] as String? ?? '');
  }

  Future<void> saveDefaultHighlightGroupId(int id) async {
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': _defaultHighlightGroupKey,
      'value': id.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> loadDefaultElibraryHighlightColorHex() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_defaultElibraryHighlightColorKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> saveDefaultElibraryHighlightColorHex(String hex) async {
    final db = await UserDatabase.instance.database;
    final value = hex.trim();
    if (value.isEmpty) return;
    await db.insert('app_settings', {
      'key': _defaultElibraryHighlightColorKey,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> loadInterlinearEnabled() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_interlinearEnabledKey],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return _parseBool(rows.first['value'] as String?) ?? false;
  }

  Future<void> saveInterlinearEnabled(bool value) async {
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': _interlinearEnabledKey,
      'value': value ? '1' : '0',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ViewerInterlinearSettings> loadInterlinearSettings() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?, ?, ?, ?, ?, ?)',
      whereArgs: [
        _interlinearEnglishOrderKey,
        _interlinearShowEnglishGlossKey,
        _interlinearShowOriginalTextKey,
        _interlinearShowTransliterationKey,
        _interlinearShowPronunciationKey,
        _interlinearShowStrongsNumberKey,
        _interlinearShowMorphologyKey,
      ],
    );
    final values = <String, String>{
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    return ViewerInterlinearSettings(
      englishOrder: _parseBool(values[_interlinearEnglishOrderKey]) ?? false,
      showEnglishGloss:
          _parseBool(values[_interlinearShowEnglishGlossKey]) ?? true,
      showOriginalText:
          _parseBool(values[_interlinearShowOriginalTextKey]) ?? true,
      showTransliteration:
          _parseBool(values[_interlinearShowTransliterationKey]) ?? true,
      showPronunciation:
          _parseBool(values[_interlinearShowPronunciationKey]) ?? true,
      showStrongsNumber:
          _parseBool(values[_interlinearShowStrongsNumberKey]) ?? true,
      showMorphology:
          _parseBool(values[_interlinearShowMorphologyKey]) ?? false,
    );
  }

  Future<void> saveInterlinearSettings(
    ViewerInterlinearSettings settings,
  ) async {
    final db = await UserDatabase.instance.database;
    final batch = db.batch();
    void put(String key, bool value) {
      batch.insert('app_settings', {
        'key': key,
        'value': value ? '1' : '0',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    put(_interlinearEnglishOrderKey, settings.englishOrder);
    put(_interlinearShowEnglishGlossKey, settings.showEnglishGloss);
    put(_interlinearShowOriginalTextKey, settings.showOriginalText);
    put(_interlinearShowTransliterationKey, settings.showTransliteration);
    put(_interlinearShowPronunciationKey, settings.showPronunciation);
    put(_interlinearShowStrongsNumberKey, settings.showStrongsNumber);
    put(_interlinearShowMorphologyKey, settings.showMorphology);
    await batch.commit(noResult: true);
  }

  Future<int> loadLastTagTabIndex() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_lastTagTabIndexKey],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
  }

  Future<void> saveLastTagTabIndex(int value) async {
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': _lastTagTabIndexKey,
      'value': value.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> loadActiveTagFamily() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_activeTagFamilyKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value']?.toString().trim().toLowerCase() ?? '';
    if (value == 'hash' || value == '#') return 'hash';
    if (value == 'dollar' || value == r'$') return 'dollar';
    return null;
  }

  Future<void> saveActiveTagFamily(String family) async {
    final normalized = family.trim().toLowerCase();
    if (normalized != 'hash' && normalized != 'dollar') return;
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': _activeTagFamilyKey,
      'value': normalized,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<PresentationAspectRatioPreset>
  loadPresentationAspectRatioPreset() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_presentationAspectRatioKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return PresentationAspectRatioPreset.auto;
    }
    return PresentationAspectRatioPreset.fromStorage(
      rows.first['value'] as String?,
    );
  }

  Future<void> savePresentationAspectRatioPreset(
    PresentationAspectRatioPreset preset,
  ) async {
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': _presentationAspectRatioKey,
      'value': preset.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Tag/list default only. Future slide- and range-level overrides can layer on top.
  Future<PresentationLayoutPreference> loadTagPresentationLayoutPreference({
    required String tagFamily,
    required String tag,
  }) async {
    final key = _tagPresentationLayoutKey(tagFamily: tagFamily, tag: tag);
    if (key.isEmpty) return PresentationLayoutPreference.auto;
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return PresentationLayoutPreference.auto;
    return presentationLayoutPreferenceFromJson(rows.first['value'] as String?);
  }

  Future<void> saveTagPresentationLayoutPreference({
    required String tagFamily,
    required String tag,
    required PresentationLayoutPreference preference,
  }) async {
    final key = _tagPresentationLayoutKey(tagFamily: tagFamily, tag: tag);
    if (key.isEmpty) return;
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': key,
      'value': presentationLayoutPreferenceToJson(preference),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<int, PresentationLayoutPreference>>
  loadTagPresentationSlideLayoutPreferences({
    required String tagFamily,
    required String tag,
  }) async {
    final prefix = _tagPresentationSlideLayoutPrefix(
      tagFamily: tagFamily,
      tag: tag,
    );
    if (prefix.isEmpty) return const <int, PresentationLayoutPreference>{};
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['key', 'value'],
      where: 'key GLOB ?',
      whereArgs: ['$prefix*'],
    );
    final result = <int, PresentationLayoutPreference>{};
    for (final row in rows) {
      final key = row['key']?.toString() ?? '';
      if (!key.startsWith(prefix)) continue;
      final slideNumber = int.tryParse(key.substring(prefix.length));
      if (slideNumber == null || slideNumber <= 0) continue;
      result[slideNumber] = presentationLayoutPreferenceFromJson(
        row['value'] as String?,
      );
    }
    return result;
  }

  Future<void> saveTagPresentationSlideLayoutPreferences({
    required String tagFamily,
    required String tag,
    required PresentationLayoutPreference defaultPreference,
    required Map<int, PresentationLayoutPreference> slidePreferences,
  }) async {
    final prefix = _tagPresentationSlideLayoutPrefix(
      tagFamily: tagFamily,
      tag: tag,
    );
    if (prefix.isEmpty) return;
    final db = await UserDatabase.instance.database;
    final batch = db.batch();
    batch.delete('app_settings', where: 'key GLOB ?', whereArgs: ['$prefix*']);
    for (final entry in slidePreferences.entries) {
      if (entry.value == defaultPreference) continue;
      batch.insert('app_settings', {
        'key': '$prefix${entry.key}',
        'value': presentationLayoutPreferenceToJson(entry.value),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<bool> loadChurchAutoMuteEnabled() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_churchAutoMuteEnabledKey],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return _parseBool(rows.first['value'] as String?) ?? false;
  }

  Future<void> saveChurchAutoMuteEnabled(bool value) async {
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': _churchAutoMuteEnabledKey,
      'value': value ? '1' : '0',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> loadLastBibleSearch() {
    return _loadStringSetting(_lastBibleSearchKey);
  }

  Future<void> saveLastBibleSearch(String value) {
    return _saveStringSetting(_lastBibleSearchKey, value);
  }

  Future<String?> loadLastBibleSearchSessionJson() {
    return _loadStringSetting(_lastBibleSearchSessionKey);
  }

  Future<void> saveLastBibleSearchSessionJson(String value) {
    return _saveStringSetting(_lastBibleSearchSessionKey, value);
  }

  Future<String?> loadLastElibrarySearch() {
    return _loadStringSetting(_lastElibrarySearchKey);
  }

  Future<void> saveLastElibrarySearch(String value) {
    return _saveStringSetting(_lastElibrarySearchKey, value);
  }

  Future<String?> loadLastElibrarySearchSessionJson() {
    return _loadStringSetting(_lastElibrarySearchSessionKey);
  }

  Future<void> saveLastElibrarySearchSessionJson(String value) {
    return _saveStringSetting(_lastElibrarySearchSessionKey, value);
  }

  AppVisualSettings presetForMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.night:
        return const AppVisualSettings(
          backgroundColor: Color(0xFF000000),
          textColor: Color(0xFFF1F1F1),
          appBarColor: Color(0xFF000000),
          bottomBarColor: Color(0xFF000000),
          accentColor: Color(0xFFFFB347),
          viewerFontScale: 1.3,
        );
      case AppThemeMode.sepia:
        return const AppVisualSettings(
          backgroundColor: Color(0xFFF6F1E4),
          textColor: Color(0xFF2B2316),
          appBarColor: Color(0xFFEDE6D6),
          bottomBarColor: Color(0xFFEDE6D6),
          accentColor: Color(0xFF8B6F47),
          viewerFontScale: 1.3,
        );
    }
  }

  Color? _parseColor(String? value) {
    if (value == null || value.isEmpty) return null;
    final hex = value.replaceFirst('#', '');
    final normalized = hex.length == 6 ? 'FF$hex' : hex;
    final parsed = int.tryParse(normalized, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  bool? _parseBool(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value == '1' || value.toLowerCase() == 'true') return true;
    if (value == '0' || value.toLowerCase() == 'false') return false;
    return null;
  }

  String _tagPresentationLayoutKey({
    required String tagFamily,
    required String tag,
  }) {
    final prefix = _tagPresentationLayoutPrefix(tagFamily: tagFamily, tag: tag);
    if (prefix.isEmpty) return '';
    return prefix.substring(0, prefix.length - 1);
  }

  String _tagPresentationLayoutPrefix({
    required String tagFamily,
    required String tag,
  }) {
    final normalizedFamily = _normalizeSettingSegment(tagFamily);
    final normalizedTag = _normalizeSettingSegment(tag);
    if (normalizedFamily.isEmpty || normalizedTag.isEmpty) return '';
    return '$_tagPresentationLayoutKeyPrefix$normalizedFamily.$normalizedTag.';
  }

  String _tagPresentationSlideLayoutPrefix({
    required String tagFamily,
    required String tag,
  }) {
    return _tagPresentationLayoutPrefix(tagFamily: tagFamily, tag: tag);
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

  String _hexFromColor(Color color) {
    final argb = color.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  Future<String?> _loadStringSetting(String key) async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> _saveStringSetting(String key, String value) async {
    final db = await UserDatabase.instance.database;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await db.insert('app_settings', {
      'key': key,
      'value': trimmed,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  bool _looksReadable(AppVisualSettings settings) {
    final background = settings.backgroundColor;
    final text = settings.textColor;
    final appBar = settings.appBarColor;
    final bottomBar = settings.bottomBarColor;
    final backgroundTextContrast =
        (background.computeLuminance() - text.computeLuminance()).abs();
    final backgroundBarContrast =
        (background.computeLuminance() - appBar.computeLuminance()).abs();
    final backgroundBottomContrast =
        (background.computeLuminance() - bottomBar.computeLuminance()).abs();
    return backgroundTextContrast > 0.20 ||
        backgroundBarContrast > 0.08 ||
        backgroundBottomContrast > 0.08;
  }
}
