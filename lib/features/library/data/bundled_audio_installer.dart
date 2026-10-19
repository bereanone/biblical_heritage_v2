import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'verified_audio_download.dart';

/// Installs an immutable audio package. The playable manifest is published last.
class BundledAudioInstaller {
  BundledAudioInstaller(this.root, this.download);
  final Directory root;
  final VerifiedAudioDownload download;

  Future<Directory> install(
    Map<String, dynamic> spec, {
    void Function(int, int)? onProgress,
  }) async {
    final id = spec['id'] as String;
    final hash = spec['sha256'] as String;
    final (destination, files) = _package(spec);
    if (await _receiptMatches(destination, files) ||
        await _complete(destination, files)) {
      await _writeReceipt(destination, files);
      await _select(id, destination);
      return destination;
    }
    final cache = File(p.join(root.path, '.downloads', '$hash.zip'));
    await download.fetch(
      url: Uri.parse(spec['url'] as String),
      destination: cache,
      bytes: spec['bytes'] as int,
      digest: hash,
      onProgress: onProgress,
    );
    final rootPath = root.path;
    final cachePath = cache.path;
    final destinationPath = destination.path;
    await Isolate.run(
      () => _unpack(rootPath, cachePath, destinationPath, id, hash, files),
    );
    await _writeReceipt(destination, files);
    await _select(id, destination);
    return destination;
  }

  (Directory, Map<String, Map<String, dynamic>>) _package(
    Map<String, dynamic> spec,
  ) {
    final id = spec['id'] as String;
    final hash = spec['sha256'] as String;
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(id) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid audio package identity');
    }
    final files = <String, Map<String, dynamic>>{};
    for (final raw in spec['files'] as List) {
      final file = Map<String, dynamic>.from(raw as Map);
      final name = file['name'] as String;
      if (p.basename(name) != name ||
          name.contains('..') ||
          name.contains('\\') ||
          !(name.endsWith('.mp3') || name == 'audio-manifest.json') ||
          files.containsKey(name) ||
          (file['bytes'] as int) <= 0 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(file['sha256'] as String)) {
        throw const FormatException('Invalid audio package member');
      }
      files[name] = file;
    }
    if (!files.containsKey('audio-manifest.json')) {
      throw const FormatException('Audio package has no manifest');
    }
    final destination = Directory(p.join(root.path, 'bundled-$id-$hash'));
    return (destination, files);
  }

  /// Fast local check of files previously verified against the pinned hashes.
  Future<bool> isReady(Map<String, dynamic> spec) async {
    final (destination, files) = _package(spec);
    if (!await _receiptMatches(destination, files)) return false;
    try {
      final pointer =
          jsonDecode(
                await File(
                  p.join(root.path, 'bundled-current.json'),
                ).readAsString(),
              )
              as Map;
      return pointer[spec['id']] == p.basename(destination.path);
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  /// Silently adopt an existing complete package. Expensive hashing runs off
  /// the UI isolate; no receipt or selection is published until it succeeds.
  /// An interrupted check simply restarts without changing the recordings.
  Future<bool> verifyInstalled(Map<String, dynamic> spec) async {
    if (await isReady(spec)) return true;
    final (destination, files) = _package(spec);
    if (await _fileStats(destination, files) == null) return false;
    final path = destination.path;
    final valid = await Isolate.run(() => _complete(Directory(path), files));
    if (!valid) return false;
    await _writeReceipt(destination, files);
    await _select(spec['id'] as String, destination);
    return true;
  }

  static String _fileSetDigest(Map<String, Map<String, dynamic>> files) =>
      sha256.convert(utf8.encode(jsonEncode(files))).toString();

  static Future<Map<String, dynamic>?> _fileStats(
    Directory directory,
    Map<String, Map<String, dynamic>> files,
  ) async {
    final result = <String, dynamic>{};
    for (final entry in files.entries) {
      final stat = await File(p.join(directory.path, entry.key)).stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size != entry.value['bytes'])
        return null;
      result[entry.key] = [
        stat.size,
        stat.modified.microsecondsSinceEpoch,
        stat.changed.microsecondsSinceEpoch,
      ];
    }
    return result;
  }

  static Future<bool> _receiptMatches(
    Directory directory,
    Map<String, Map<String, dynamic>> files,
  ) async {
    try {
      final receipt =
          jsonDecode(
                await File(
                  p.join(directory.path, '.verified.json'),
                ).readAsString(),
              )
              as Map;
      if (receipt['schema'] != 1 || receipt['fileSet'] != _fileSetDigest(files))
        return false;
      final stats = await _fileStats(directory, files);
      return stats != null && jsonEncode(stats) == jsonEncode(receipt['stats']);
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  static Future<void> _writeReceipt(
    Directory directory,
    Map<String, Map<String, dynamic>> files,
  ) async {
    final stats = await _fileStats(directory, files);
    if (stats == null)
      throw const FormatException(
        'Verified audio files changed during installation',
      );
    final receipt = File(p.join(directory.path, '.verified.json'));
    final temporary = File('${receipt.path}.new');
    await temporary.writeAsString(
      jsonEncode({
        'schema': 1,
        'fileSet': _fileSetDigest(files),
        'stats': stats,
      }),
      flush: true,
    );
    await temporary.rename(receipt.path);
  }

  static Future<void> _unpack(
    String rootPath,
    String cachePath,
    String destinationPath,
    String id,
    String hash,
    Map<String, Map<String, dynamic>> files,
  ) async {
    final cache = File(cachePath);
    final destination = Directory(destinationPath);
    final staging = Directory(p.join(rootPath, '.installing-$id-$hash'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    final input = InputFileStream(cache.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final seen = <String>{};
      for (final member in archive.files) {
        final expected = files[member.name];
        if (!member.isFile ||
            member.isSymbolicLink ||
            expected == null ||
            !seen.add(member.name) ||
            member.size != expected['bytes']) {
          throw const FormatException('Unexpected audio archive member');
        }
        final output = OutputFileStream(p.join(staging.path, member.name));
        try {
          member.writeContent(output);
        } finally {
          await output.close();
        }
      }
      if (seen.length != files.length || !await _complete(staging, files)) {
        throw const FormatException('Audio package is incomplete or damaged');
      }
      // A manifest with bad track references must never become playable.
      final manifest =
          jsonDecode(
                await File(
                  p.join(staging.path, 'audio-manifest.json'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final tracks = manifest['tracks'] as List;
      if (tracks.isEmpty || tracks.any((t) => !files.containsKey(t['file']))) {
        throw const FormatException('Audio manifest references missing tracks');
      }
      if (await destination.exists()) {
        // Only an invalid directory of this exact content hash is replaced.
        await destination.delete(recursive: true);
      }
      await staging.rename(destination.path);
      await cache.delete();
    } finally {
      await input.close();
    }
  }

  Future<void> _select(String id, Directory directory) async {
    final pointer = File(p.join(root.path, 'bundled-current.json'));
    final current = await pointer.exists()
        ? Map<String, dynamic>.from(
            jsonDecode(await pointer.readAsString()) as Map,
          )
        : <String, dynamic>{};
    current[id] = p.basename(directory.path);
    final temporary = File('${pointer.path}.installing');
    await temporary.writeAsString(jsonEncode(current), flush: true);
    await temporary.rename(pointer.path);
  }

  static Future<bool> _complete(
    Directory directory,
    Map<String, Map<String, dynamic>> files,
  ) async {
    for (final entry in files.entries) {
      final file = File(p.join(directory.path, entry.key));
      if (!await file.exists() ||
          await file.length() != entry.value['bytes'] ||
          (await sha256.bind(file.openRead()).first).toString() !=
              entry.value['sha256']) {
        return false;
      }
    }
    return true;
  }
}
