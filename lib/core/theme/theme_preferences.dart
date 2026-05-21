import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_settings_service.dart';
import '../database/user_database.dart';
import 'app_theme_mode.dart';

class ThemePreferences {
  ThemePreferences._();

  static final ThemePreferences instance = ThemePreferences._();
  static final ValueNotifier<AppThemeMode> themeModeListenable =
      ValueNotifier(AppThemeMode.sepia);

  static const _themeModeKey = 'theme_mode';

  Future<AppThemeMode> loadThemeMode() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'prefs',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_themeModeKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      themeModeListenable.value = AppThemeMode.sepia;
      return AppThemeMode.sepia;
    }
    final mode = AppThemeMode.values.byName(rows.first['value'] as String);
    themeModeListenable.value = mode;
    return mode;
  }

  Future<void> saveThemeMode(AppThemeMode mode) async {
    final db = await UserDatabase.instance.database;
    await db.insert(
      'prefs',
      {
        'key': _themeModeKey,
        'value': mode.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    themeModeListenable.value = mode;
    await AppSettingsService.instance.applyThemePreset(mode);
  }
}
