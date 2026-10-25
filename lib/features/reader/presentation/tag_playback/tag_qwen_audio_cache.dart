import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/study_bible_database.dart';
import '../bundled_bible_audio_narrator.dart';
import 'tag_playback_models.dart';
import 'tag_pcm_clip_edges.dart';
import 'tag_playback_planner.dart';

/// Only an exact verse may reuse its recording. Edited excerpts keep their
/// own words through synthesis rather than silently playing the canonical text.
bool tagCanUseQwen(TagSpeechClip clip, BibleVerseRecord verse) {
  String normalize(String text) => text
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clip.kind != TagClipKind.verse ||
      clip.blockId != verse.blockId ||
      normalize(clip.sourceBody ?? clip.body) != normalize(verse.text)) {
    return false;
  }
  final reference = clip.sourceReference ?? clip.reference;
  return reference == null ||
      reference ==
          spokenBibleReference(
            bookName: verse.bookName,
            chapter: verse.chapter,
            verseStart: verse.verse,
            verseEnd: verse.verse,
          );
}

/// Extracts measured verse intervals from the shipped Qwen recording. The
/// native exporter only decodes audio; it never changes the voice or words.
class TagQwenAudioCache {
  TagQwenAudioCache._();
  static final instance = TagQwenAudioCache._();
  static const _channel = MethodChannel('studybible/recorded_audio');
  final _chapters = <String, BundledChapter>{};
  final _cueHashes = <String, String>{};
  Future<void>? _catalogLoad;
  final _inFlight = <String, Future<String>>{};
  final _assetInFlight = <String, Future<String>>{};

  static bool isCachedPath(String path) => path.contains('/tag_qwen_audio/');
  String get _cueRoot => Platform.isAndroid
      ? 'assets/audio/qwen_loop_cues_android'
      : 'assets/audio/qwen_loop_cues';

  Future<void> _load() => _catalogLoad ??= () async {
    final catalog =
        jsonDecode(
              await rootBundle.loadString(
                'assets/audio/qwen_bible/catalog.json',
              ),
            )
            as Map<String, dynamic>;
    for (final row in catalog['chapters'] as List) {
      final chapter = BundledChapter.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
      _chapters['${chapter.book}:${chapter.chapter}'] = chapter;
    }
    final cues =
        jsonDecode(await rootBundle.loadString('$_cueRoot/manifest.json'))
            as Map<String, dynamic>;
    for (final row in cues['cues'] as List) {
      _cueHashes[row['name'] as String] = row['audio_sha256'] as String;
    }
  }();

  Future<String> _asset(String asset, String hash, Directory directory) async {
    final pending = _assetInFlight[hash];
    if (pending != null) return pending;
    final operation = _copyAsset(asset, hash, directory);
    _assetInFlight[hash] = operation;
    try {
      return await operation;
    } finally {
      _assetInFlight.remove(hash);
    }
  }

  Future<String> _copyAsset(
    String asset,
    String hash,
    Directory directory,
  ) async {
    final file = File('${directory.path}/${hash}_${asset.split('/').last}');
    if (await file.exists() && await file.length() > 0) return file.path;
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (sha256.convert(bytes).toString() != hash) {
      throw StateError('Qwen recording checksum mismatch');
    }
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
    return file.path;
  }

  Future<String?> renderIfAvailable(TagSpeechClip clip) async {
    if (!(Platform.isMacOS || Platform.isIOS || Platform.isAndroid) ||
        clip.kind != TagClipKind.verse ||
        clip.blockId == null) {
      return null;
    }
    try {
      final records = await StudyBibleDatabase.instance
          .loadVerseRecordsForBlockIds([clip.blockId!]);
      final verse = records[clip.blockId];
      if (verse == null || !tagCanUseQwen(clip, verse)) return null;
      await _load();
      final chapter = _chapters['${verse.bookNumber}:${verse.chapter}'];
      final range = chapter?.rangeForVerse(verse.verse);
      if (chapter == null || range == null) return null;
      final cueNames = (clip.sourceReference ?? clip.reference) == null
          ? <String>[]
          : [
              'book_${verse.bookNumber.toString().padLeft(2, '0')}',
              'chapter_${verse.chapter.toString().padLeft(3, '0')}',
              'verse_${verse.verse.toString().padLeft(3, '0')}',
            ];
      if (cueNames.any((name) => !_cueHashes.containsKey(name))) return null;
      final key = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                tagQwenPcmCacheVersion,
                chapter.audioSha256,
                range.$1,
                range.$2,
                for (final cue in cueNames) _cueHashes[cue],
              ]),
            ),
          )
          .toString();
      final root = await getTemporaryDirectory();
      final directory = Directory('${root.path}/tag_qwen_audio');
      await directory.create(recursive: true);
      final target = File('${directory.path}/$key.wav');
      if (await target.exists() && await target.length() > 44) {
        return target.path;
      }
      final existing = _inFlight[key];
      if (existing != null) return await existing;
      final pending = _render(target, chapter, range, cueNames);
      _inFlight[key] = pending;
      try {
        return await pending;
      } finally {
        _inFlight.remove(key);
      }
    } catch (error) {
      debugPrint(
        'Qwen tag recording unavailable; using exact-text fallback: $error',
      );
      return null;
    }
  }

  Future<String> _render(
    File target,
    BundledChapter chapter,
    (double, double) range,
    List<String> cues,
  ) async {
    final sources = Directory('${target.parent.path}/sources');
    await sources.create(recursive: true);
    final segments = <Map<String, Object>>[];
    for (final cue in cues) {
      segments.add({
        'path': await _asset('$_cueRoot/$cue.m4a', _cueHashes[cue]!, sources),
      });
    }
    segments.add({
      'path': await _asset(chapter.asset, chapter.audioSha256, sources),
      'startSeconds': range.$1,
      'endSeconds': range.$2,
    });
    final part = File('${target.path}.part.wav');
    try {
      await _channel.invokeMethod<void>('exportSegments', {
        'segments': segments,
        'outputPath': part.path,
      });
      if (!await part.exists() || await part.length() <= 44) {
        throw StateError('Empty Qwen verse clip');
      }
      final wav = await part.readAsBytes();
      softenTagPcmClipEdges(wav);
      await part.writeAsBytes(wav, flush: true);
      await part.rename(target.path);
      debugPrint(
        'Tag playback using Qwen: ${chapter.book}:${chapter.chapter} at ${range.$1}s',
      );
      return target.path;
    } finally {
      if (await part.exists()) await part.delete();
    }
  }
}
