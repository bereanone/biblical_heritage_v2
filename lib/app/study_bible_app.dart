import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_settings_service.dart';
import '../core/theme/app_theme_mode.dart';
import '../core/theme/theme_preferences.dart';
import '../features/entry/presentation/entry_screen.dart';

class StudyBibleApp extends StatefulWidget {
  const StudyBibleApp({super.key});

  @override
  State<StudyBibleApp> createState() => _StudyBibleAppState();
}

class _StudyBibleAppState extends State<StudyBibleApp> {
  AppThemeMode _themeMode = AppThemeMode.sepia;
  AppVisualSettings? _visualSettings;
  bool _loadedTheme = false;

  @override
  void initState() {
    super.initState();
    ThemePreferences.themeModeListenable.addListener(_handleThemeModeChanged);
    _loadThemeMode();
  }

  @override
  void dispose() {
    ThemePreferences.themeModeListenable.removeListener(_handleThemeModeChanged);
    super.dispose();
  }

  void _handleThemeModeChanged() {
    final mode = ThemePreferences.themeModeListenable.value;
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
      _visualSettings = AppSettingsService.instance.presetForMode(mode);
    });
  }

  Future<void> _loadThemeMode() async {
    final mode = await ThemePreferences.instance.loadThemeMode();
    await AppSettingsService.instance.applyThemePreset(mode);
    final settings = await AppSettingsService.instance.loadVisualSettings(mode);
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
      _visualSettings = settings;
      _loadedTheme = true;
    });
  }

  Future<void> _setThemeMode(AppThemeMode mode) async {
    final settings = AppSettingsService.instance.presetForMode(mode);
    setState(() {
      _themeMode = mode;
      _visualSettings = settings;
    });
    await ThemePreferences.instance.saveThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StudyBible',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(_themeMode, settings: _visualSettings),
      home: _loadedTheme
          ? EntryScreen(
              themeMode: _themeMode,
              onThemeChanged: (mode) {
                _setThemeMode(mode);
              },
            )
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}
