import 'package:flutter/material.dart';
import '../core/audio/synthesis_thermal_gate.dart';
import '../features/reader/presentation/memory_schedule/memory_schedule_reminder.dart';

import '../core/navigation/app_route_observer.dart';
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
  final _audioMessages = GlobalKey<ScaffoldMessengerState>();
  bool _temperatureNoticeVisible = false;
  final _navigator = GlobalKey<NavigatorState>();
  late final MacMemoryReminderService _memoryReminders;
  AppThemeMode _themeMode = AppThemeMode.sepia;
  AppVisualSettings? _visualSettings;
  bool _loadedTheme = false;

  @override
  void initState() {
    super.initState();
    SynthesisThermalGate.instance.waitingForTemperature.addListener(
      _temperatureChanged,
    );
    _memoryReminders = MacMemoryReminderService(_navigator)..start();
    ThemePreferences.themeModeListenable.addListener(_handleThemeModeChanged);
    _loadThemeMode();
  }

  @override
  void dispose() {
    SynthesisThermalGate.instance.waitingForTemperature.removeListener(
      _temperatureChanged,
    );
    _memoryReminders.dispose();
    ThemePreferences.themeModeListenable.removeListener(
      _handleThemeModeChanged,
    );
    super.dispose();
  }

  void _temperatureChanged() {
    final waiting = SynthesisThermalGate.instance.waitingForTemperature.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messages = _audioMessages.currentState;
      if (waiting && !_temperatureNoticeVisible) {
        _temperatureNoticeVisible = true;
        messages?.showSnackBar(
          const SnackBar(
            duration: Duration(days: 1),
            content: Text(
              'Paused to let your phone cool down. Audio generation will resume when it’s safe.',
            ),
          ),
        );
      } else if (!waiting && _temperatureNoticeVisible) {
        _temperatureNoticeVisible = false;
        messages?.hideCurrentSnackBar();
        if (!SynthesisThermalGate.instance.paused) {
          messages?.showSnackBar(
            const SnackBar(
              content: Text('The phone has cooled. Audio creation can resume.'),
            ),
          );
        }
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
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
      title: 'Biblical Heritage StudyBible 2.0',
      scaffoldMessengerKey: _audioMessages,
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(_themeMode, settings: _visualSettings),
      navigatorObservers: [appRouteObserver],
      home: _loadedTheme
          ? EntryScreen(
              themeMode: _themeMode,
              onThemeChanged: (mode) {
                _setThemeMode(mode);
              },
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
