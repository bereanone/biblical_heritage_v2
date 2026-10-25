import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_pcm_clip_edges.dart';

Uint8List wave({
  int frames = 1000,
  bool extra = false,
  bool extensible = false,
}) {
  final fmtSize = extensible ? 40 : 16;
  final dataStart = 12 + 8 + fmtSize + (extra ? 12 : 0) + 8;
  final bytes = Uint8List(dataStart + frames * 2);
  final b = ByteData.sublistView(bytes);
  void text(int at, String s) => bytes.setRange(at, at + s.length, s.codeUnits);
  text(0, 'RIFF');
  b.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  b.setUint32(16, fmtSize, Endian.little);
  b.setUint16(20, extensible ? 0xfffe : 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, 24000, Endian.little);
  b.setUint32(28, 48000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  if (extensible) {
    b.setUint16(36, 22, Endian.little);
    b.setUint16(38, 16, Endian.little);
    bytes.setRange(44, 60, [
      1,
      0,
      0,
      0,
      0,
      0,
      16,
      0,
      128,
      0,
      0,
      170,
      0,
      56,
      155,
      113,
    ]);
  }
  if (extra) {
    text(dataStart - 20, 'JUNK');
    b.setUint32(dataStart - 16, 3, Endian.little);
    bytes.setRange(dataStart - 12, dataStart - 9, [7, 8, 9]);
  }
  text(dataStart - 8, 'data');
  b.setUint32(dataStart - 4, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    b.setInt16(
      dataStart + i * 2,
      i < frames ~/ 2 ? 12000 : -9000,
      Endian.little,
    );
  }
  return bytes;
}

void main() {
  test(
    'edges reach silence smoothly without changing duration or interior',
    () {
      final bytes = wave();
      final before = Uint8List.fromList(bytes);
      softenTagPcmClipEdges(bytes);
      final b = ByteData.sublistView(bytes);
      expect(bytes.length, before.length);
      expect(bytes.sublist(0, 44), before.sublist(0, 44));
      expect(
        bytes.sublist(44 + 240, bytes.length - 240),
        before.sublist(44 + 240, before.length - 240),
      );
      expect(b.getInt16(44, Endian.little), 0);
      expect(b.getInt16(bytes.length - 2, Endian.little), 0);
      // A 12000 -> silence hard cut becomes a gradual slope, not a shifted cut.
      for (var i = 1; i < 120; i++) {
        final previous = b.getInt16(44 + (i - 1) * 2, Endian.little);
        final current = b.getInt16(44 + i * 2, Endian.little);
        expect(current, greaterThanOrEqualTo(previous));
        expect(current - previous, lessThan(200));
      }
    },
  );
  test('unknown odd-sized metadata is preserved', () {
    final bytes = wave(extra: true);
    final header = bytes.sublist(0, 56);
    softenTagPcmClipEdges(bytes);
    expect(bytes.sublist(0, 56), header);
    expect(ByteData.sublistView(bytes).getInt16(56, Endian.little), 0);
  });
  test('extensible PCM16 mono is supported', () {
    final bytes = wave(extensible: true);
    softenTagPcmClipEdges(bytes);
    expect(ByteData.sublistView(bytes).getInt16(68, Endian.little), 0);
  });
  test('short clips do not overlap ramps or change frame count', () {
    for (final frames in [2, 3, 20, 239, 240]) {
      final bytes = wave(frames: frames);
      softenTagPcmClipEdges(bytes);
      expect(bytes.length, 44 + frames * 2);
      final b = ByteData.sublistView(bytes);
      expect(b.getInt16(44, Endian.little), 0);
      expect(b.getInt16(bytes.length - 2, Endian.little), 0);
    }
  });
  test('invalid and unsupported files fail before mutation', () {
    final badEncoding = wave();
    ByteData.sublistView(badEncoding).setUint16(20, 3, Endian.little);
    final wrongRate = wave();
    ByteData.sublistView(wrongRate).setUint32(24, 48000, Endian.little);
    for (final bytes in [
      Uint8List(0),
      wave().sublist(0, 50),
      badEncoding,
      wrongRate,
    ]) {
      final before = Uint8List.fromList(bytes);
      expect(() => softenTagPcmClipEdges(bytes), throwsFormatException);
      expect(bytes, before);
    }
  });
  test('new cache identity excludes earlier hard-cut outputs', () {
    expect(tagQwenPcmCacheVersion, isNot('qwen-tag-pcm-v1'));
  });
}
