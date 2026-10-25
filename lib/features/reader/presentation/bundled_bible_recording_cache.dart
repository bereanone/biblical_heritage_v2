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
