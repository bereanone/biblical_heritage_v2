import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// App-owned recordings, intentionally outside the OS's temporary cache.
/// Completed chunks are checkpoints: a restart retries only missing chunks.
class DurableSpeechCache {
  DurableSpeechCache({
    required this.directory,
    this.revision = 'kokoro-sid16-model1-lexicon1-wave1',
  });
  static final instance = DurableSpeechCache(
    directory: () async => Directory(
      '${(await getApplicationSupportDirectory()).path}/narration_audio_v1',
    ),
  );
  final Future<Directory> Function() directory;
  final String revision;
  final Map<String, Future<File>> _pending = {};
  static const maxCharacters = 320;

  String key(String text, double speed, String pronunciationMode) => sha256
      .convert(
        utf8.encode(jsonEncode([revision, pronunciationMode, speed, text])),
      )
      .toString();

  static bool owns(String path) => path.contains('/narration_audio_v1/');

  /// Hard bound, including unbroken tokens; never bisect a surrogate pair.
  static List<String> chunks(String text) {
    final result = <String>[];
    var rest = text;
    while (rest.length > maxCharacters) {
      var end = maxCharacters;
      final space = rest.lastIndexOf(RegExp(r'\s'), end);
      if (space >= maxCharacters ~/ 2) end = space + 1;
      final last = rest.codeUnitAt(end - 1);
      if (last >= 0xD800 && last <= 0xDBFF) end--;
      result.add(rest.substring(0, end));
      rest = rest.substring(end);
    }
    if (rest.isNotEmpty) result.add(rest);
    return result;
  }

  static Future<bool> valid(File file) async {
    if (!await file.exists() || await file.length() <= 44) return false;
    final handle = await file.open();
    try {
      final header = await handle.read(44);
      if (header.length != 44) return false;
      final data = ByteData.sublistView(header);
      return ascii.decode(header.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
          ascii.decode(header.sublist(8, 12), allowInvalid: true) == 'WAVE' &&
          data.getUint16(20, Endian.little) == 1 &&
          data.getUint16(22, Endian.little) == 1 &&
          data.getUint16(34, Endian.little) == 16 &&
          data.getUint32(24, Endian.little) > 0 &&
          data.getUint32(40, Endian.little) == await file.length() - 44;
    } finally {
      await handle.close();
    }
  }

  Future<File> renderOrGet(
    String text,
    double speed, {
    required String pronunciationMode,
    required Future<File> Function(String chunk) render,
  }) async {
    final id = key(text, speed, pronunciationMode);
    final root = await directory();
    await root.create(recursive: true);
    final target = File('${root.path}/$id.wav');
    if (await valid(target)) return target;
    final existing = _pending[id];
    if (existing != null) return existing;
    final future = _render(target, text, speed, pronunciationMode, render);
    _pending[id] = future;
    try {
      return await future;
    } finally {
      _pending.remove(id);
    }
  }

  Future<File> _render(
    File target,
    String text,
    double speed,
    String mode,
    Future<File> Function(String) render,
  ) async {
    // The scratch name is unique even if another process left a partial write.
    final part = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      final segments = chunks(text);
      if (segments.length <= 1) {
        final temporary = await render(text);
        try {
          if (!await valid(temporary)) {
            throw StateError('Invalid narration WAV');
          }
          await temporary.copy(part.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      } else {
        final pcm = BytesBuilder(copy: false);
        Uint8List? header;
        for (final chunk in segments) {
          final file = await renderOrGet(
            chunk,
            speed,
            pronunciationMode: mode,
            render: render,
          );
          final bytes = await file.readAsBytes();
          if (header != null &&
              ByteData.sublistView(header).getUint32(24, Endian.little) !=
                  ByteData.sublistView(bytes).getUint32(24, Endian.little)) {
            throw StateError('Narration sample rates differ');
          }
          header ??= Uint8List.fromList(bytes.sublist(0, 44));
          pcm.add(bytes.sublist(44));
        }
        final samples = pcm.takeBytes();
        final data = ByteData.sublistView(header!);
        data.setUint32(4, samples.length + 36, Endian.little);
        data.setUint32(40, samples.length, Endian.little);
        await part.writeAsBytes([...header, ...samples], flush: true);
      }
      // Flush before the atomic commit. A partial file is never a cache hit.
      final handle = await part.open(mode: FileMode.append);
      await handle.flush();
      await handle.close();
      if (!await valid(part)) throw StateError('Incomplete narration WAV');
      return await part.rename(target.path);
    } finally {
      if (await part.exists()) await part.delete();
    }
  }
}
