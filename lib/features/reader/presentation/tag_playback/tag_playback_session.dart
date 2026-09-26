import 'dart:async';

import '../../../../core/database/study_bible_database.dart';
import '../../../../core/theme/app_settings_service.dart';
import '../kokoro_mac_test_narrator.dart';
import '../narration_pronunciation.dart';
import '../tag_quick_apply_helper.dart';
import 'tag_playback_controller.dart';
import 'tag_playback_kokoro_adapters.dart';
import 'tag_playback_media_binding.dart';
import 'tag_playback_planner.dart';
import 'tag_playback_settings.dart';
import 'tag_note_audio_cache.dart';

/// Everything one open playback popup owns: the controller and, behind it,
/// the narrator (and its lease on the shared Kokoro engine) and the players.
/// Disposing the session stops audio and cancels any pending synthesis.
class TagPlaybackSession {
  TagPlaybackSession({
    required this.tag,
    required this.controller,
    this.media,
    Future<void> Function()? onDispose,
  }) : _onDispose = onDispose;

  final String tag;
  final TagPlaybackController controller;

  /// Lock screen / Control Center wiring; released before the controller.
  final TagPlaybackMediaBinding? media;
  final Future<void> Function()? _onDispose;
  bool _disposed = false;

  /// Loads the tag in the same order the detail screen shows it and wires the
  /// existing Kokoro pipeline, pronunciation rules and speech-rate setting.
  static Future<TagPlaybackSession> open({
    required String tag,
    String? category,
    bool isDollar = false,
    TagPlaybackSettingsStore? settingsStore,
  }) async {
    final repository = isDollar ? DollarTagRepository() : HashTagRepository();
    final database = StudyBibleDatabase.instance;
    final settings = AppSettingsService.instance;

    final entries = await repository.loadEntries(
      tag,
      category: category,
      sortMode: HashTagEntrySortMode.slideOrder,
    );
    final books = await database.loadBooks();
    final items = await TagPlaybackPlanner(
      bookNames: {for (final book in books) book.bookNumber: book.bookName},
      resolveBlockId: (book, chapter, verse) => database.loadBlockIdForVerse(
        bookNumber: book,
        chapter: chapter,
        verse: verse,
      ),
    ).plan(entries);
    // Older notes may predate the persistent cache. Prepare a bounded lead
    // from this tag only; opening the popup never waits for local synthesis.
    for (final item in items.take(6)) {
      if (item.noteClips.isEmpty) continue;
      TagNoteAudioCache.instance.scheduleNoteText(
        item.noteClips.map((clip) => clip.body).join('\n'),
        entryKey: 'existing:$tag:${item.entryId}',
      );
    }

    final store = settingsStore ?? AppTagPlaybackSettingsStore();
    final playback = await store.load();
    final preferences = await settings.loadMacAutoscrollPreferences();
    final rules = decodeNarrationPronunciations(
      await settings.loadRawSetting('narration_pronunciations_v1'),
    );
    final deferred = await loadDeferredNarrationPronunciations(
      rules: rules,
      load: settings.loadRawSetting,
      save: settings.saveRawSetting,
    );

    final narrator = KokoroMacTestNarrator()
      ..pronunciationCorrections = rules
      ..deferredPronunciationCorrections = deferred;
    final player = AudioplayersTagClipPlayer(speed: preferences.speechRate);
    final controller = TagPlaybackController(
      items: items,
      renderer: KokoroTagClipRenderer(narrator, speed: preferences.speechRate),
      player: player,
      maxAhead: 6,
      backgroundMaxAhead: 8,
      includeNotes: playback.speakNotes,
      speakReference: playback.speakReference,
      loop: playback.loop,
      onSettingsChanged: (changed) => unawaited(store.save(changed)),
    );
    // Load the engine now so the first clip does not pay for model startup.
    unawaited(narrator.warmUp());
    return TagPlaybackSession(
      tag: tag,
      controller: controller,
      media: TagPlaybackMediaBinding(controller: controller, tag: tag),
      // The controller stops and disposes the player; the narrator releases
      // its lease so the model is freed if nothing else is using it.
      onDispose: () async => narrator.dispose(),
    );
  }

  /// Stops speech, cancels buffered and in-flight synthesis and releases the
  /// engine lease. Safe to call more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    media?.dispose();
    controller.dispose();
    final onDispose = _onDispose;
    if (onDispose != null) unawaited(onDispose());
  }
}
