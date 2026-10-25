import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_settings_service.dart';
import '../kokoro_mac_test_narrator.dart';
import '../narration_pronunciation.dart';
import '../../../../core/audio/local_narration_policy.dart';
import '../../../../core/audio/durable_speech_cache.dart';
import 'tag_playback_planner.dart' show splitIntoSpeechChunks;

@visibleForTesting
String tagNoteAudioKey({
  required String text,
  required String pronunciation,
  required String deferred,
  required double bakedSpeed,
  required String voiceRevision,
}) => sha256
    .convert(
      utf8.encode(
        jsonEncode([voiceRevision, text, pronunciation, deferred, bakedSpeed]),
      ),
    )
    .toString();

/// Persistent, content-addressed audio for locally narrated user notes.
/// A text or pronunciation edit gets a new filename, so an older background
/// render can never replace the recording selected for the newer text.
class TagNoteAudioCache {
  TagNoteAudioCache._();

  @visibleForTesting
  TagNoteAudioCache.forTesting({
    required Future<Directory> Function() directory,
    required Future<String> Function(String, double) key,
    required Future<File> Function(String, double) render,
  }) : _testDirectory = directory,
       _testKey = key,
       _testRender = render;

  Future<Directory> Function()? _testDirectory;
  Future<String> Function(String, double)? _testKey;
  Future<File> Function(String, double)? _testRender;
  static final instance = TagNoteAudioCache._();

  static const _voiceRevision = 'kokoro-default-v1';
  final Map<String, Future<String>> _inFlight = {};
  Future<void> _renderTail = Future<void>.value();
  final Map<String, int> _entryRevision = {};
  Future<void> _preparationTail = Future<void>.value();
  final Map<String, Set<Future<void>>> _preparingNotes = {};

  Future<void> _waitForSavedNote(String text) async {
    // A save registers every chunk before returning. Even a cached first chunk
    // waits for the rest of that note, so prefetch cannot race its preparation.
    while (_preparingNotes[text]?.isNotEmpty ?? false) {
      await Future.wait(_preparingNotes[text]!.toList());
    }
  }

  Future<Directory> _directory() async {
    if (_testDirectory != null) return _testDirectory!();
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/tag_note_audio');
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _key(String text, double speed) async {
    speed = LocalNarrationPolicy.noteSynthesisSpeed(speed);
    if (_testKey != null) return _testKey!(text, speed);
    final settings = AppSettingsService.instance;
    final pronunciation =
        await settings.loadRawSetting('narration_pronunciations_v1') ?? '';
    final deferred =
        await settings.loadRawSetting('narration_deferred_pronunciations_v2') ??
        '';
    final bakedSpeed = KokoroMacTestNarrator.synthesisSpeedFor(speed);
    return tagNoteAudioKey(
      voiceRevision: _voiceRevision,
      text: text,
      pronunciation: pronunciation,
      deferred: deferred,
      bakedSpeed: bakedSpeed,
    );
  }

  Future<File?> cached(String text, {required double speed}) async {
    final key = await _key(text, speed);
    final file = File('${(await _directory()).path}/$key.wav');
    if (!await DurableSpeechCache.valid(file)) return null;
    return file;
  }

  Future<String> renderOrGet(
    String text, {
    required double speed,
    KokoroMacTestNarrator? narrator,
    bool prepareOnSave = false,
    bool Function()? stillCurrent,
  }) async {
    if (LocalNarrationPolicy.savedPlaybackOnly && !prepareOnSave) {
      await _waitForSavedNote(text);
    }
    final key = await _key(text, speed);
    final target = File('${(await _directory()).path}/$key.wav');
    if (await DurableSpeechCache.valid(target)) {
      return target.path;
    }
    if (LocalNarrationPolicy.savedPlaybackOnly && !prepareOnSave) {
      throw const SavedAudioUnavailable(
        'No saved recording is available for this note. Open the note and save it to prepare audio.',
      );
    }
    if (LocalNarrationPolicy.savedPlaybackOnly &&
        text.length > LocalNarrationPolicy.maxNoteChunkCharacters) {
      throw const SavedAudioUnavailable(
        'This note recording needs smaller chunks.',
      );
    }
    final current = _inFlight[key];
    if (current != null) return current;
    final completer = Completer<String>();
    _inFlight[key] = completer.future;
    _renderTail = _renderTail.then((_) async {
      try {
        if (await DurableSpeechCache.valid(target)) {
          completer.complete(target.path);
          return;
        }
        if (stillCurrent != null && !stillCurrent()) {
          throw const SavedAudioUnavailable(
            'A newer note has replaced this recording request.',
          );
        }
        final bakedSpeed = LocalNarrationPolicy.noteSynthesisSpeed(speed);
        final rendered = _testRender != null
            ? await _testRender!(text, bakedSpeed)
            : await narrator!.renderClip(text: text, speed: bakedSpeed);
        try {
          final temporary = File('${target.path}.part');
          if (await temporary.exists()) await temporary.delete();
          await rendered.copy(temporary.path);
          if (!await DurableSpeechCache.valid(temporary)) {
            throw StateError('Empty note recording');
          }
          await temporary.rename(target.path);
        } finally {
          if (await rendered.exists()) await rendered.delete();
        }
        completer.complete(target.path);
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _inFlight.remove(key);
      }
    });
    return completer.future;
  }

  bool isCachedPath(String path) => path.contains('/tag_note_audio/');

  /// Called after a note is saved. Saving returns immediately; rendering is
  /// queued on device. Playback never starts generation on a mobile cache miss.
  void scheduleNoteText(
    String text, {
    required String entryKey,
    String? title,
  }) {
    final revision = (_entryRevision[entryKey] ?? 0) + 1;
    _entryRevision[entryKey] = revision;
    final lead = title?.trim() ?? '';
    if (LocalNarrationPolicy.savedPlaybackOnly &&
        text.length + lead.length >
            LocalNarrationPolicy.maxMobileNoteCharacters) {
      debugPrint(
        'Note saved; audio needs desktop preparation because the note is too long.',
      );
      return;
    }
    final chunks = [if (lead.isNotEmpty) '$lead.', ..._splitNote(text)];
    if (chunks.isEmpty) return;
    final completion = Completer<void>();
    for (final chunk in chunks.toSet()) {
      (_preparingNotes[chunk] ??= {}).add(completion.future);
    }
    _preparationTail = _preparationTail.then((_) async {
      try {
        await _prepare(chunks, entryKey: entryKey, revision: revision);
      } finally {
        for (final chunk in chunks.toSet()) {
          final pending = _preparingNotes[chunk];
          pending?.remove(completion.future);
          if (pending?.isEmpty ?? false) _preparingNotes.remove(chunk);
        }
        completion.complete();
      }
    });
  }

  Future<void> _prepare(
    List<String> chunks, {
    required String entryKey,
    required int revision,
  }) async {
    final narrator = _testRender == null ? KokoroMacTestNarrator() : null;
    try {
      if (narrator != null) {
        final settings = AppSettingsService.instance;
        final rules = decodeNarrationPronunciations(
          await settings.loadRawSetting('narration_pronunciations_v1'),
        );
        narrator.pronunciationCorrections = rules;
        narrator.deferredPronunciationCorrections =
            await loadDeferredNarrationPronunciations(
              rules: rules,
              load: settings.loadRawSetting,
              save: settings.saveRawSetting,
            );
      }
      for (final chunk in chunks) {
        if (_entryRevision[entryKey] != revision) return;
        await renderOrGet(
          chunk,
          speed: 1,
          narrator: narrator,
          prepareOnSave: true,
          stillCurrent: () => _entryRevision[entryKey] == revision,
        );
      }
    } catch (error) {
      debugPrint('Note audio preparation pending: $error');
    } finally {
      narrator?.dispose();
    }
  }

  // Share the planner's chunking and preserve exact text, including spaces.
  List<String> _splitNote(String text) => [
    for (final chunk in splitIntoSpeechChunks(text))
      ...DurableSpeechCache.chunks(chunk),
  ];
}
