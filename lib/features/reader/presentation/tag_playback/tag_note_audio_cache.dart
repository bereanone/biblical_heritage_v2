import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_settings_service.dart';
import '../kokoro_mac_test_narrator.dart';
import '../narration_pronunciation.dart';

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
  static final instance = TagNoteAudioCache._();

  static const _voiceRevision = 'kokoro-default-v1';
  final Map<String, Future<String>> _inFlight = {};
  Future<void> _renderTail = Future<void>.value();
  final Map<String, int> _entryRevision = {};

  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/tag_note_audio');
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _key(String text, double speed) async {
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
    if (!await file.exists() || await file.length() <= 44) return null;
    return file;
  }

  Future<String> renderOrGet(
    String text, {
    required double speed,
    required KokoroMacTestNarrator narrator,
  }) async {
    final key = await _key(text, speed);
    final target = File('${(await _directory()).path}/$key.wav');
    if (await target.exists() && await target.length() > 44) {
      return target.path;
    }
    final current = _inFlight[key];
    if (current != null) return current;
    final completer = Completer<String>();
    _inFlight[key] = completer.future;
    _renderTail = _renderTail.then((_) async {
      try {
        if (await target.exists() && await target.length() > 44) {
          completer.complete(target.path);
          return;
        }
        final rendered = await narrator.renderClip(text: text, speed: speed);
        try {
          final temporary = File('${target.path}.part');
          if (await temporary.exists()) await temporary.delete();
          await rendered.copy(temporary.path);
          if (await temporary.length() <= 44) {
            throw StateError('Empty note recording');
          }
          await temporary.rename(target.path);
          completer.complete(target.path);
        } finally {
          if (await rendered.exists()) await rendered.delete();
        }
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
  /// queued on device and a missed cache remains an honest playback wait.
  void scheduleNoteText(String text, {required String entryKey}) {
    final revision = (_entryRevision[entryKey] ?? 0) + 1;
    _entryRevision[entryKey] = revision;
    unawaited(_prepare(text, entryKey: entryKey, revision: revision));
  }

  Future<void> _prepare(
    String text, {
    required String entryKey,
    required int revision,
  }) async {
    final chunks = _splitNote(text);
    if (chunks.isEmpty) return;
    final narrator = KokoroMacTestNarrator();
    try {
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
      for (final chunk in chunks) {
        if (_entryRevision[entryKey] != revision) return;
        await renderOrGet(chunk, speed: 1, narrator: narrator);
      }
    } catch (error) {
      debugPrint('Note audio preparation pending: $error');
    } finally {
      narrator.dispose();
    }
  }

  // Kept equivalent to the planner's speech chunking so saved notes reuse
  // the exact clips requested during tag playback.
  List<String> _splitNote(String text) {
    final chunks = <String>[];
    for (final paragraph in text.split(RegExp(r'\n+'))) {
      final clean = paragraph.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.isEmpty) continue;
      var current = '';
      for (final sentence in clean.split(RegExp(r'(?<=[.!?])\s+'))) {
        if (current.isEmpty) {
          current = sentence;
        } else if (current.length + 1 + sentence.length <= 320) {
          current = '$current $sentence';
        } else {
          chunks.add(current);
          current = sentence;
        }
      }
      if (current.isNotEmpty) chunks.add(current);
    }
    return chunks;
  }
}
