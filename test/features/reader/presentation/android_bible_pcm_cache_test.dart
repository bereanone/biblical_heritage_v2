import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bundled_bible_recording_cache.dart';

Uint8List pcm({int sampleRate = 24000}) {
  final bytes = Uint8List(244);
  final h = ByteData.sublistView(bytes);
  void label(int at, String value) =>
      bytes.setRange(at, at + value.length, value.codeUnits);
  label(0, 'RIFF');
  h.setUint32(4, 236, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, sampleRate, Endian.little);
  h.setUint32(28, sampleRate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  label(36, 'data');
  h.setUint32(40, 200, Endian.little);
  bytes[60] = 120;
  return bytes;
}

void main() {
  late Directory root;
  late Directory files;
  final identity = sha256.convert([1, 2, 3]).toString();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bible-pcm-test-');
    files = Directory('${root.path}/files/pcm');
  });
  tearDown(() => root.delete(recursive: true));
  Future<String> prepare({
    Future<void> Function(String, String)? render,
    String? hash,
  }) => materializeBiblePcmPlayback(
    directory: files,
    sourcePath: '${root.path}/source.m4a',
    sourceSha256: hash ?? identity,
    render:
        render ??
        (source, out) async {
          await File(out).writeAsBytes(pcm());
        },
  );
  test(
    'prepared chapter survives disposable cache eviction and reuses verified PCM',
    () async {
      final cache = await Directory('${root.path}/cache').create();
      await File('${cache.path}/chapter.m4a').writeAsBytes([1]);
      final output = await prepare();
      await cache.delete(recursive: true);
      expect(
        await prepare(
          render: (_, _) async {
            fail('must reuse intact PCM');
          },
        ),
        output,
      );
      expect(await File(output).readAsBytes(), pcm());
    },
  );
  test('nonempty PCM corruption is regenerated instead of played', () async {
    final output = await prepare();
    final damaged = pcm();
    damaged[60] = 0;
    await File(output).writeAsBytes(damaged);
    var rendered = false;
    await prepare(
      render: (_, out) async {
        rendered = true;
        await File(out).writeAsBytes(pcm());
      },
    );
    expect(rendered, isTrue);
    expect(await File(output).readAsBytes(), pcm());
  });
  test('interrupted decoding cannot publish a partial chapter', () async {
    await expectLater(
      prepare(
        render: (_, out) async {
          await File(out).writeAsBytes([0, 0]);
          throw StateError('decoder interrupted');
        },
      ),
      throwsStateError,
    );
    expect(await files.list().toList(), isEmpty);
    expect(await File(await prepare()).exists(), isTrue);
  });
  test('invalid or unsupported WAV output is rejected', () async {
    await expectLater(
      prepare(
        render: (_, out) async {
          await File(out).writeAsBytes(pcm(sampleRate: 44100));
        },
      ),
      throwsStateError,
    );
    expect(await files.list().toList(), isEmpty);
  });
  test('overlapping requests share one complete decode', () async {
    final ready = Completer<void>();
    var calls = 0;
    Future<void> render(String source, String out) async {
      calls++;
      await ready.future;
      await File(out).writeAsBytes(pcm());
    }

    final first = prepare(render: render);
    final second = prepare(render: render);
    ready.complete();
    final paths = await Future.wait([first, second]);
    expect(calls, 1);
    expect(paths[0], paths[1]);
    expect(await File(paths[0]).readAsBytes(), pcm());
  });
  test(
    'derived chapter storage is bounded without touching originals or unrelated files',
    () async {
      await files.create(recursive: true);
      final original = File('${files.path}/original.m4a');
      await original.writeAsBytes([1, 2, 3]);
      String? latest;
      for (var i = 0; i < 5; i++) {
        latest = await prepare(hash: sha256.convert([i]).toString());
      }
      final entries = await files.list().toList();
      expect(entries.where((f) => f.path.endsWith('.wav')).length, 3);
      expect(entries.where((f) => f.path.endsWith('.sha256')).length, 3);
      expect(await File(latest!).exists(), isTrue);
      expect(await original.readAsBytes(), [1, 2, 3]);
    },
  );
}
