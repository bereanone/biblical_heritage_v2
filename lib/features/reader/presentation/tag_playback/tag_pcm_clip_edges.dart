import 'dart:math' as math;
import 'dart:typed_data';

// Change the generated-file identity so older hard-cut clips are not reused.
const tagQwenPcmCacheVersion = 'qwen-tag-pcm-v2-soft-edges';

/// Taper only the outer 5 ms of a generated verse clip. Keep its sample count,
/// timing, headers and interior unchanged; never edit shipped chapter audio.
void softenTagPcmClipEdges(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  bool tag(int offset, String text) {
    if (offset + text.length > wav.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (wav[offset + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (wav.length < 12 || !tag(0, 'RIFF') || !tag(8, 'WAVE')) {
    throw const FormatException('Expected a PCM WAV verse clip');
  }
  int? sampleRate, sampleOffset, sampleBytes;
  var validFormat = false;
  for (var offset = 12; offset + 8 <= wav.length;) {
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (size > wav.length - start) {
      throw const FormatException('Truncated WAV verse clip');
    }
    if (tag(offset, 'fmt ')) {
      if (size < 16) throw const FormatException('Invalid WAV format');
      final encoding = data.getUint16(start, Endian.little);
      // AVAudioFile may use the extensible PCM format; accept only PCM16 mono.
      final pcm =
          encoding == 1 ||
          (encoding == 0xfffe &&
              size >= 40 &&
              data.getUint16(start + 16, Endian.little) >= 22 &&
              data.getUint16(start + 18, Endian.little) == 16 &&
              List.generate(16, (i) => wav[start + 24 + i]).join(',') ==
                  '1,0,0,0,0,0,16,0,128,0,0,170,0,56,155,113');
      sampleRate = data.getUint32(start + 4, Endian.little);
      validFormat =
          pcm &&
          data.getUint16(start + 2, Endian.little) == 1 &&
          data.getUint16(start + 12, Endian.little) == 2 &&
          data.getUint16(start + 14, Endian.little) == 16 &&
          sampleRate == 24000;
    } else if (tag(offset, 'data')) {
      if (sampleOffset != null) {
        throw const FormatException('Multiple WAV data chunks');
      }
      sampleOffset = start;
      sampleBytes = size;
    }
    offset = start + size + (size.isOdd ? 1 : 0);
  }
  if (!validFormat ||
      sampleOffset == null ||
      sampleBytes == null ||
      sampleBytes < 4 ||
      sampleBytes.isOdd) {
    throw const FormatException('Expected nonempty 24 kHz mono PCM16 audio');
  }
  final frames = sampleBytes ~/ 2;
  final fadeFrames = math.min(sampleRate! ~/ 200, frames ~/ 2);
  for (var i = 0; i < fadeFrames; i++) {
    final gain = fadeFrames == 1
        ? 0.0
        : 0.5 - 0.5 * math.cos(math.pi * i / (fadeFrames - 1));
    for (final frame in [i, frames - 1 - i]) {
      final offset = sampleOffset + frame * 2;
      data.setInt16(
        offset,
        (data.getInt16(offset, Endian.little) * gain).round(),
        Endian.little,
      );
    }
  }
}
