import 'package:flutter/foundation.dart';

import '../../../../core/database/user_database.dart';
import '../../../../core/theme/app_settings_service.dart';

/// What the tag playback popup speaks and how it repeats. Remembered across
/// sessions and shared by every tag.
@immutable
class TagPlaybackSettings {
  const TagPlaybackSettings({
    this.speakReference = true,
    this.speakNotes = true,
    this.loop = false,
  });

  /// Say what identifies each entry before it: "John 3, verse 16" for a
  /// verse, the work and location for an eLibrary quote, a note's own title.
  /// Off: only the entry's content and note, with no identifier.
  final bool speakReference;

  /// Read the note attached to an entry after its content.
  final bool speakNotes;

  final bool loop;

  TagPlaybackSettings copyWith({
    bool? speakReference,
    bool? speakNotes,
    bool? loop,
  }) => TagPlaybackSettings(
    speakReference: speakReference ?? this.speakReference,
    speakNotes: speakNotes ?? this.speakNotes,
    loop: loop ?? this.loop,
  );

  @override
  bool operator ==(Object other) =>
      other is TagPlaybackSettings &&
      other.speakReference == speakReference &&
      other.speakNotes == speakNotes &&
      other.loop == loop;

  @override
  int get hashCode => Object.hash(speakReference, speakNotes, loop);
}

/// Where [TagPlaybackSettings] live between sessions.
abstract interface class TagPlaybackSettingsStore {
  Future<TagPlaybackSettings> load();
  Future<void> save(TagPlaybackSettings settings);
}

typedef RawSettingLoader = Future<String?> Function(String key);
typedef RawSettingSaver = Future<void> Function(String key, String value);
typedef RawSettingRemover = Future<void> Function(String key);

/// Keeps the settings in the app's existing key/value settings table, one key
/// per toggle so a missing key falls back to that toggle's own default.
class AppTagPlaybackSettingsStore implements TagPlaybackSettingsStore {
  AppTagPlaybackSettingsStore({RawSettingLoader? load, RawSettingSaver? save})
    : _load = load ?? AppSettingsService.instance.loadRawSetting,
      _save = save ?? AppSettingsService.instance.saveRawSetting;

  static const speakReferenceKey = 'tag_playback.speak_reference';
  static const speakNotesKey = 'tag_playback.speak_notes';
  static const loopKey = 'tag_playback.loop';

  /// "Begin with Note" was removed; nothing reads this key any more.
  static const retiredAnnounceNoteKey = 'tag_playback.announce_note';

  /// Startup cleanup for keys no toggle owns any more. Best effort.
  static Future<void> removeRetiredKeys([RawSettingRemover? remove]) async {
    try {
      await (remove ?? _removeFromAppSettings)(retiredAnnounceNoteKey);
    } catch (_) {
      /* A leftover row is harmless; try again next launch. */
    }
  }

  static Future<void> _removeFromAppSettings(String key) async {
    final db = await UserDatabase.instance.database;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  final RawSettingLoader _load;
  final RawSettingSaver _save;

  static bool _flag(String? raw, {required bool fallback}) => switch (raw) {
    '1' || 'true' => true,
    '0' || 'false' => false,
    _ => fallback,
  };

  @override
  Future<TagPlaybackSettings> load() async {
    try {
      const defaults = TagPlaybackSettings();
      return TagPlaybackSettings(
        speakReference: _flag(
          await _load(speakReferenceKey),
          fallback: defaults.speakReference,
        ),
        speakNotes: _flag(
          await _load(speakNotesKey),
          fallback: defaults.speakNotes,
        ),
        loop: _flag(await _load(loopKey), fallback: defaults.loop),
      );
    } catch (_) {
      return const TagPlaybackSettings(); // Never block playback on settings.
    }
  }

  @override
  Future<void> save(TagPlaybackSettings settings) async {
    try {
      await _save(speakReferenceKey, settings.speakReference ? '1' : '0');
      await _save(speakNotesKey, settings.speakNotes ? '1' : '0');
      await _save(loopKey, settings.loop ? '1' : '0');
    } catch (_) {
      /* A failed save only loses the preference, never the playback. */
    }
  }
}
