import '../../../core/bootstrap/local_settings_store.dart';

class ReaderTiltPreferences {
  const ReaderTiltPreferences({
    this.reverseVerticalDirection = false,
    this.neutralZoneFraction = 0.05,
    this.speedMultiplier = 1.0,
    this.horizontalChapterTiltEnabled = false,
    this.reverseHorizontalDirection = false,
    this.horizontalSensitivity = 0.5,
    this.horizontalChapterTiltAvailabilityMigrated = false,
  });

  static const defaults = ReaderTiltPreferences();
  static const minimumNeutralZoneFraction = 0.02;
  static const maximumNeutralZoneFraction = 0.10;
  static const minimumSpeedMultiplier = 0.5;
  static const maximumSpeedMultiplier = 2.0;

  final bool reverseVerticalDirection;
  final double neutralZoneFraction;
  final double speedMultiplier;
  final bool horizontalChapterTiltEnabled;
  final bool reverseHorizontalDirection;
  final double horizontalSensitivity;
  final bool horizontalChapterTiltAvailabilityMigrated;

  ReaderTiltPreferences copyWith({
    bool? reverseVerticalDirection,
    double? neutralZoneFraction,
    double? speedMultiplier,
    bool? horizontalChapterTiltEnabled,
    bool? reverseHorizontalDirection,
    double? horizontalSensitivity,
    bool? horizontalChapterTiltAvailabilityMigrated,
  }) => ReaderTiltPreferences(
    reverseVerticalDirection:
        reverseVerticalDirection ?? this.reverseVerticalDirection,
    neutralZoneFraction: (neutralZoneFraction ?? this.neutralZoneFraction)
        .clamp(minimumNeutralZoneFraction, maximumNeutralZoneFraction),
    speedMultiplier: (speedMultiplier ?? this.speedMultiplier).clamp(
      minimumSpeedMultiplier,
      maximumSpeedMultiplier,
    ),
    horizontalChapterTiltEnabled:
        horizontalChapterTiltEnabled ?? this.horizontalChapterTiltEnabled,
    reverseHorizontalDirection:
        reverseHorizontalDirection ?? this.reverseHorizontalDirection,
    horizontalSensitivity: (horizontalSensitivity ?? this.horizontalSensitivity)
        .clamp(0.0, 1.0),
    horizontalChapterTiltAvailabilityMigrated:
        horizontalChapterTiltAvailabilityMigrated ??
        this.horizontalChapterTiltAvailabilityMigrated,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'reverse_vertical_direction': reverseVerticalDirection,
    'neutral_zone_fraction': neutralZoneFraction,
    'speed_multiplier': speedMultiplier,
    'horizontal_chapter_tilt_enabled': horizontalChapterTiltEnabled,
    'reverse_horizontal_direction': reverseHorizontalDirection,
    'horizontal_sensitivity': horizontalSensitivity,
    'horizontal_chapter_tilt_availability_migrated':
        horizontalChapterTiltAvailabilityMigrated,
  };

  factory ReaderTiltPreferences.fromJson(Object? value) {
    if (value is! Map) return defaults;
    double number(String key, double fallback) =>
        (value[key] as num?)?.toDouble() ?? fallback;
    bool boolean(String key, bool fallback) =>
        value[key] is bool ? value[key] as bool : fallback;
    return defaults.copyWith(
      reverseVerticalDirection: boolean('reverse_vertical_direction', false),
      neutralZoneFraction: number('neutral_zone_fraction', 0.05),
      speedMultiplier: number('speed_multiplier', 1.0),
      horizontalChapterTiltEnabled: boolean(
        'horizontal_chapter_tilt_enabled',
        false,
      ),
      reverseHorizontalDirection: boolean(
        'reverse_horizontal_direction',
        false,
      ),
      horizontalSensitivity: number('horizontal_sensitivity', 0.5),
      horizontalChapterTiltAvailabilityMigrated: boolean(
        'horizontal_chapter_tilt_availability_migrated',
        false,
      ),
    );
  }
}

class ReaderTiltPreferencesStore {
  const ReaderTiltPreferencesStore();

  static const storageKey = 'reader_tilt_preferences';

  Future<ReaderTiltPreferences> load() async {
    final settings = await LocalSettingsStore.instance.load();
    return ReaderTiltPreferences.fromJson(settings[storageKey]);
  }

  Future<void> save(ReaderTiltPreferences preferences) async {
    final settings = await LocalSettingsStore.instance.load();
    settings[storageKey] = preferences.toJson();
    await LocalSettingsStore.instance.save(settings);
  }
}
