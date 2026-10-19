import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/durable_speech_cache.dart';
import 'package:studybible2/core/audio/synthesis_thermal_gate.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';

void main() {
  test(
    'book queue reuses saved segments after restart, then stops a hot missing segment',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'book-audio-lifecycle',
      );
      try {
        var cache = DurableSpeechCache(directory: () async => root);
        var renders = 0;
        var stopped = false;
        var hot = false;
        final enteredWait = Completer<void>();
        final releaseWait = Completer<void>();
        final gate = SynthesisThermalGate(
          mobile: true,
          read: () async => {'level': hot ? 2 : 0},
          delay: (_) async {
            if (!enteredWait.isCompleted) enteredWait.complete();
            await releaseWait.future;
          },
        );
        Future<File> render(String text) async {
          await gate.beforeJob(() => stopped);
          renders++;
          final bytes = Uint8List(48);
          bytes.setRange(0, 4, 'RIFF'.codeUnits);
          bytes.setRange(8, 12, 'WAVE'.codeUnits);
          final d = ByteData.sublistView(bytes);
          d.setUint32(4, 40, Endian.little);
          d.setUint16(20, 1, Endian.little);
          d.setUint16(22, 1, Endian.little);
          d.setUint32(24, 24000, Endian.little);
          d.setUint16(34, 16, Endian.little);
          d.setUint32(40, 4, Endian.little);
          return File('${root.path}/source-$renders.wav').writeAsBytes(bytes);
        }

        final segmenter = LibrarySpeechSegmenter((cursor) async {
          final n = int.parse(cursor);
          if (n > 2) return null;
          return LibrarySpeechItem(
            cursor: cursor,
            nextCursor: '${n + 1}',
            text: 'Book paragraph $n.',
          );
        });
        final played = <String>[];
        final errors = <Object>[];
        LibrarySpeechQueue makeQueue() => LibrarySpeechQueue(
          load: segmenter.load,
          reveal: (_) async {},
          speak: (item) async {
            final saved = await cache.renderOrGet(
              item.text,
              1,
              pronunciationMode: 'book1',
              render: render,
            );
            played.add(saved.path);
          },
          stopAudio: () async {
            stopped = true;
            if (hot && !releaseWait.isCompleted) releaseWait.complete();
          },
          onEnd: () {},
          onError: errors.add,
        );
        var queue = makeQueue();
        await queue.start('1');
        await queue.stop();
        expect(renders, 1);
        final original = played.single;
        // Reopen with fresh cache/queue objects and no synthesizer availability.
        cache = DurableSpeechCache(directory: () async => root);
        stopped = false;
        hot = true;
        gate.update({'level': 2});
        queue = makeQueue();
        await queue.start('1');
        expect(played.last, original);
        expect(renders, 1); // Cached playback bypasses thermal wait entirely.
        final awaitingMissing = queue.completed();
        await enteredWait.future;
        expect(gate.waitingForTemperature.value, isTrue);
        await queue.stop();
        await awaitingMissing;
        expect(queue.running, isFalse);
        expect(renders, 1);
        expect(errors, isEmpty);
        expect(await DurableSpeechCache.valid(File(original)), isTrue);
        expect(gate.waitingForTemperature.value, isFalse);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
