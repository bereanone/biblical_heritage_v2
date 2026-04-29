import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/user_database.dart';
import 'app_theme_mode.dart';
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
  static const _defaultHighlightGroupKey = 'viewer.markup.default_group_id';
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
  static const _presentationAspectRatioKey =
      'viewer.presentation.aspect_ratio';

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

    return AppVisualSettings(
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

  Future<PresentationAspectRatioPreset> loadPresentationAspectRatioPreset() async {
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

  String _hexFromColor(Color color) {
    final argb = color.toARGB32();
    return '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}
