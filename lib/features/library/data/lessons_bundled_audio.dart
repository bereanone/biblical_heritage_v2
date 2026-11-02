import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'bundled_audio_installer.dart';
import 'verified_audio_download.dart';
import 'lessons_reading_edition.dart';

/// Desktop counterpart to mobile provisioning; attach only to the exact source.
class LessonsBundledAudio {
  static final Map<String, Future<void>> _pending = {};
  static Future<void> ensure(
    Directory root,
    String? sourceHash, {
    AssetBundle? assets,
  }) async {
    if (sourceHash != LessonsReadingEdition.sourceHash) return;
    final key = root.absolute.path;
    if (_pending.containsKey(key)) return _pending[key];
    final future = _install(root, assets ?? rootBundle);
    _pending[key] = future;
    try {
      await future;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<void> _install(Directory root, AssetBundle assets) async {
    final manifest =
        jsonDecode(await assets.loadString('assets/bundled_library/audio.json'))
            as Map;
    final spec = (manifest['packages'] as List).cast<Map>().singleWhere(
      (p) =>
          p['id'] == 'lof' &&
          p['requires_source_sha256'] == LessonsReadingEdition.sourceHash,
    );
    final downloader = VerifiedAudioDownload();
    try {
      await BundledAudioInstaller(
        root,
        downloader,
      ).installAssets(Map<String, dynamic>.from(spec), assets);
    } finally {
      downloader.close();
    }
  }
}
