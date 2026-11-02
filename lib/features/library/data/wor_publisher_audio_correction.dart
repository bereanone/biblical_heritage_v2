import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'bundled_audio_installer.dart';
import 'optional_book_companions.dart';
import 'verified_audio_download.dart';

/// Desktop libraries do not run mobile provisioning. Repair only the selected,
/// known WOR package, publishing a verified new selection before playback.
class WorPublisherAudioCorrection {
  static final Map<String, Future<void>> _pending = {};
  static Future<void> ensure(
    Directory root,
    String? sourceHash, {
    AssetBundle? assets,
  }) async {
    if (sourceHash != OptionalBookCompanions.worSingleReaderSource) return;
    final key = root.absolute.path;
    final running = _pending[key];
    if (running != null) return running;
    final work = _apply(root, assets ?? rootBundle);
    _pending[key] = work;
    try {
      await work;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<void> _apply(Directory root, AssetBundle assets) async {
    final pointer = File('${root.path}/bundled-current.json');
    if (!await pointer.exists()) return;
    final current = jsonDecode(await pointer.readAsString()) as Map;
    final folder = current['wor'];
    if (folder is! String ||
        folder.contains('/') ||
        folder.contains('\\') ||
        folder == '.' ||
        folder == '..') {
      return;
    }
    final path = File('${root.path}/$folder/audio-manifest.json');
    if (!await path.exists()) return;
    final manifest = jsonDecode(await path.readAsString()) as Map;
    if (manifest['source_sha256'] !=
        OptionalBookCompanions.worSingleReaderSource) {
      return;
    }
    final affected = (manifest['tracks'] as List).cast<Map>().any(
      (track) => (track['cues'] as List).cast<Map>().any(
        (cue) =>
            cue['source_refcode'] == 'WOR 102.14' &&
            cue['text'].toString().contains('raised up fro the dead'),
      ),
    );
    if (!affected) return;
    final bundle =
        jsonDecode(await assets.loadString('assets/bundled_library/audio.json'))
            as Map;
    final spec = (bundle['packages'] as List).cast<Map>().singleWhere(
      (p) =>
          p['id'] == 'wor' && p['publisher_correction'] == 'wor-102-14-from-v1',
    );
    final download = VerifiedAudioDownload();
    try {
      await BundledAudioInstaller(
        root,
        download,
      ).installAssets(Map<String, dynamic>.from(spec), assets);
    } finally {
      download.close();
    }
  }
}
