import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/durable_speech_cache.dart';

void main() {
  late Directory root;
  late DurableSpeechCache cache;
  var renders = 0;
  Future<File> render(String text) async {
    renders++;
    final bytes = Uint8List(48);
    bytes.setRange(0, 4, 'RIFF'.codeUnits);
    bytes.setRange(8, 12, 'WAVE'.codeUnits);
    final data = ByteData.sublistView(bytes);
    data.setUint32(4, 40, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, 24000, Endian.little);
    data.setUint16(34, 16, Endian.little);
    data.setUint32(40, 4, Endian.little);
    return File('${root.path}/render-$renders.wav').writeAsBytes(bytes);
  }

  Future<File> get(String text, {double speed = 1, String mode = 'lexicon1'}) =>
      cache.renderOrGet(text, speed, pronunciationMode: mode, render: render);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('speech-cache-test');
    renders = 0;
    cache = DurableSpeechCache(directory: () async => root);
  });
  tearDown(() async => root.delete(recursive: true));

  test('restart reads saved WAV without invoking the engine', () async {
    final first = await get('Saved book paragraph.');
    cache = DurableSpeechCache(directory: () async => root);
    final again = await get('Saved book paragraph.');
    expect(again.path, first.path);
    expect(renders, 1);
    expect(await DurableSpeechCache.valid(again), isTrue);
  });
  test(
    'spoken pronunciation, speed, engine revision invalidate independently',
    () async {
      final first = await get('Original.');
      expect((await get('Pronunciation changed.')).path, isNot(first.path));
      expect((await get('Original.', speed: 1.2)).path, isNot(first.path));
      expect(
        (await get('Original.', mode: 'dictionary2')).path,
        isNot(first.path),
      );
      cache = DurableSpeechCache(
        directory: () async => root,
        revision: 'new-model',
      );
      expect((await get('Original.')).path, isNot(first.path));
      expect(renders, 5);
    },
  );
  test('interruption resumes at the first missing bounded chunk', () async {
    final text = List.generate(
      6,
      (i) => '${String.fromCharCode(65 + i) * 300}. ',
    ).join();
    final chunks = DurableSpeechCache.chunks(text);
    var attempts = 0;
    await expectLater(
      cache.renderOrGet(
        text,
        1,
        pronunciationMode: 'lexicon1',
        render: (chunk) async {
          if (++attempts == 2) throw StateError('simulated interruption');
          return render(chunk);
        },
      ),
      throwsStateError,
    );
    expect(renders, 1);
    cache = DurableSpeechCache(directory: () async => root);
    final result = await get(text);
    expect(renders, chunks.toSet().length);
    expect(await DurableSpeechCache.valid(result), isTrue);
    expect(root.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
  });
  test('partial and malformed WAVs never count as completed audio', () async {
    final id = cache.key('Missing.', 1, 'lexicon1');
    await File('${root.path}/$id.wav.older.part').writeAsString('interrupted');
    await File('${root.path}/$id.wav').writeAsBytes(List.filled(100, 0));
    final file = await get('Missing.');
    expect(renders, 1);
    expect(await DurableSpeechCache.valid(file), isTrue);
  });
  test(
    'concurrent requests deduplicate and long tokens preserve Unicode',
    () async {
      final outputs = await Future.wait([get('Same.'), get('Same.')]);
      expect(outputs[0].path, outputs[1].path);
      expect(renders, 1);
      final text = '😀' * 500;
      final chunks = DurableSpeechCache.chunks(text);
      expect(chunks.join(), text);
      expect(chunks.every((c) => c.length <= 320), isTrue);
      expect(chunks.every((c) => c.runes.every((r) => r > 0xDFFF)), isTrue);
    },
  );
}
