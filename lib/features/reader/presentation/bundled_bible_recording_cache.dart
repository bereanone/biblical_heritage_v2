import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A nonempty cached file is not enough: interrupted or damaged recordings
/// must never be handed to the player as if they matched the shipped chapter.
Future<bool> bibleRecordingMatches(File file, String expectedSha256) async {
  if (!await file.exists()) return false;
  return (await sha256.bind(file.openRead()).first).toString() ==
      expectedSha256;
}

Future<String> materializeVerifiedBibleRecording({
  required File destination,
  required String expectedSha256,
  required Future<Uint8List> Function() loadBytes,
}) async {
  if (await bibleRecordingMatches(destination, expectedSha256)) {
    return destination.path;
  }
  final bytes = await loadBytes();
  if (sha256.convert(bytes).toString() != expectedSha256) {
    throw StateError('Recorded Bible audio failed verification.');
  }
  await destination.parent.create(recursive: true);
  // Each attempt gets its own staging file. A later request cannot truncate
  // another request's write; both may only promote the verified same chapter.
  final staging = await Directory(
    destination.parent.path,
  ).createTemp('.chapter-');
  try {
    final temporary = File('${staging.path}/recording');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
    return destination.path;
  } finally {
    await staging.delete(recursive: true);
  }
}

/// Decode the verified shipped chapter through the same PCM exporter used by
/// hashtag verse playback. Keep this derivative in app files, not OS cache.
final _pcmInFlight = <String, Future<String>>{};

Future<String> materializeBiblePcmPlayback({
  required Directory directory,
  required String sourcePath,
  required String sourceSha256,
  required Future<void> Function(String source, String output) render,
}) async {
  final key = '${directory.path}/$sourceSha256.wav';
  final existing = _pcmInFlight[key];
  if (existing != null) return existing;
  final pending = _prepareBiblePcmPlayback(
    directory: directory,
    sourcePath: sourcePath,
    sourceSha256: sourceSha256,
    render: render,
  );
  _pcmInFlight[key] = pending;
  try {
    return await pending;
  } finally {
    _pcmInFlight.remove(key);
  }
}

Future<String> _prepareBiblePcmPlayback({
  required Directory directory,
  required String sourcePath,
  required String sourceSha256,
  required Future<void> Function(String source, String output) render,
}) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceSha256)) {
    throw StateError('Invalid Bible recording identity');
  }
  await directory.create(recursive: true);
  final target = File('${directory.path}/$sourceSha256.wav');
  final stamp = File('${target.path}.sha256');
  if (await stamp.exists() &&
      await bibleRecordingMatches(
        target,
        (await stamp.readAsString()).trim(),
      ) &&
      await _isBiblePcm(target)) {
    await target.setLastModified(DateTime.now());
    return target.path;
  }
  final staging = await directory.createTemp('.decode-');
  try {
    final part = File('${staging.path}/chapter.wav');
    await render(sourcePath, part.path);
    if (!await _isBiblePcm(part)) {
      throw StateError('Bible chapter could not be prepared for playback');
    }
    final hash = (await sha256.bind(part.openRead()).first).toString();
    final stagedStamp = File('${staging.path}/chapter.sha256');
    await stagedStamp.writeAsString(hash, flush: true);
    await part.rename(target.path);
    await stagedStamp.rename(stamp.path);
    // Derivatives only: bound storage to three recent chapters. Original
    // bundled recordings, user data and other audio folders are untouched.
    final chapters = await directory
        .list()
        .where(
          (file) =>
              file is File &&
              RegExp(r'/[a-f0-9]{64}\.wav$').hasMatch(file.path),
        )
        .cast<File>()
        .toList();
    final times = <String, DateTime>{};
    for (final file in chapters) {
      times[file.path] = await file.lastModified();
    }
    chapters.sort((a, b) => times[b.path]!.compareTo(times[a.path]!));
    for (final old in chapters.skip(3)) {
      if (old.path == target.path || _pcmInFlight.containsKey(old.path)) {
        continue;
      }
      await old.delete();
      final oldStamp = File('${old.path}.sha256');
      if (await oldStamp.exists()) await oldStamp.delete();
    }
    return target.path;
  } finally {
    await staging.delete(recursive: true);
  }
}

Future<bool> _isBiblePcm(File file) async {
  if (!await file.exists() || await file.length() <= 44) return false;
  final input = await file.open();
  try {
    final header = await input.read(44);
    if (header.length != 44) return false;
    final h = ByteData.sublistView(header);
    bool label(int at, String value) =>
        String.fromCharCodes(header.sublist(at, at + value.length)) == value;
    return label(0, 'RIFF') &&
        label(8, 'WAVE') &&
        label(12, 'fmt ') &&
        label(36, 'data') &&
        h.getUint32(16, Endian.little) == 16 &&
        h.getUint16(20, Endian.little) == 1 &&
        h.getUint16(22, Endian.little) == 1 &&
        h.getUint32(24, Endian.little) == 24000 &&
        h.getUint32(28, Endian.little) == 48000 &&
        h.getUint16(32, Endian.little) == 2 &&
        h.getUint16(34, Endian.little) == 16 &&
        h.getUint32(40, Endian.little) == await file.length() - 44 &&
        h.getUint32(4, Endian.little) == await file.length() - 8;
  } finally {
    await input.close();
  }
}
