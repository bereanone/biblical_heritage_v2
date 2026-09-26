import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/study_bible_database.dart';
import '../../../../core/theme/app_settings_service.dart';
import '../kokoro_mac_test_narrator.dart';
import 'tag_playback_models.dart';

/// Reuses exact locally generated verse clips on later tag plays and loops.
/// The key includes the text, selected Bible row, speech settings and that
/// row's pronunciation data, so edits cannot reuse an older take.
class TagVerseAudioCache {
  TagVerseAudioCache._();
  static final instance = TagVerseAudioCache._();

  static const _voiceRevision = 'kokoro-verse-bible-map-v1';
  final Map<String, Future<String>> _inFlight = {};

  Future<String> _key(TagSpeechClip clip, double speed) async {
    final settings = AppSettingsService.instance;
    final blockId = clip.blockId;
    Map<String, Object?>? verse;
    if (blockId != null) {
      try {
        verse = await StudyBibleDatabase.instance.loadVersePronunciation(
          blockId,
        );
      } catch (_) {
        // The narrator itself can still render a verse without database cues.
      }
    }
    final parts = [
      _voiceRevision,
      clip.text,
      blockId,
      verse?['plain_text'],
      verse?['pronunciation'],
      await settings.loadRawSetting('narration_pronunciations_v1'),
      await settings.loadRawSetting('narration_deferred_pronunciations_v2'),
      KokoroMacTestNarrator.synthesisSpeedFor(speed),
    ];
    return sha256.convert(utf8.encode(jsonEncode(parts))).toString();
  }

  Future<String> renderOrGet(
    TagSpeechClip clip, {
    required double speed,
    required KokoroMacTestNarrator narrator,
  }) async {
    final key = await _key(clip, speed);
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/tag_verse_audio');
    await directory.create(recursive: true);
    final target = File('${directory.path}/$key.wav');
    if (await target.exists() && await target.length() > 44) {
      return target.path;
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final operation = _render(target, clip, speed, narrator);
    _inFlight[key] = operation;
    try {
      return await operation;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<String> _render(
    File target,
    TagSpeechClip clip,
    double speed,
    KokoroMacTestNarrator narrator,
  ) async {
    final rendered = await narrator.renderClip(
      text: clip.text,
      speed: speed,
      blockId: clip.blockId,
    );
    final temporary = File('${target.path}.part');
    try {
      if (await temporary.exists()) await temporary.delete();
      await rendered.copy(temporary.path);
      if (await temporary.length() <= 44) {
        throw StateError('Empty verse recording');
      }
      await temporary.rename(target.path);
      return target.path;
    } finally {
      if (await rendered.exists()) await rendered.delete();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  bool isCachedPath(String path) => path.contains('/tag_verse_audio/');
}
