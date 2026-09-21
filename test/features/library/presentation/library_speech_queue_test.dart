import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';

void main() {
  test(
    'large paragraphs are bounded exact slices with a stable source cursor',
    () async {
      final source = List.filled(
        40,
        'A complete sentence with words and punctuation. ',
      ).join();
      final splitter = LibrarySpeechSegmenter(
        (cursor) async => cursor == 'block'
            ? LibrarySpeechItem(
                cursor: 'block',
                nextCursor: 'end',
                text: source,
              )
            : null,
      );
      var cursor = 'block';
      final pieces = <String>[];
      var expectedOffset = 0;
      while (true) {
        final item = await splitter.load(cursor);
        if (item == null) break;
        expect(item.sourceCursor, 'block');
        expect(item.startOffset, expectedOffset);
        expect(
          item.text.length,
          lessThanOrEqualTo(LibrarySpeechSegmenter.maximumCharacters),
        );
        pieces.add(item.text);
        expectedOffset += item.text.length;
        cursor = item.nextCursor;
      }
      expect(pieces.length, greaterThan(1));
      expect(pieces.join(), source);
    },
  );
  test(
    'long sentences split at words and retain contractions and Unicode',
    () async {
      final source = List.filled(90, "people’s prayer 😀 ").join();
      final splitter = LibrarySpeechSegmenter(
        (cursor) async => cursor == '0:0'
            ? LibrarySpeechItem(cursor: '0:0', nextCursor: 'done', text: source)
            : null,
      );
      var cursor = '0:0';
      var output = '';
      while (true) {
        final item = await splitter.load(cursor);
        if (item == null) break;
        expect(item.text.endsWith(' '), isTrue);
        output += item.text;
        cursor = item.nextCursor;
      }
      expect(output, source);
    },
  );

  LibrarySpeechItem item(int i) => LibrarySpeechItem(
    cursor: '$i',
    nextCursor: '${i + 1}',
    text: 'Original paragraph $i.',
  );
  test(
    'advances only after playback completes and stops at book end',
    () async {
      final spoken = <String>[];
      var ended = false;
      final q = LibrarySpeechQueue(
        load: (c) async => int.parse(c) < 2 ? item(int.parse(c)) : null,
        reveal: (_) async {},
        speak: (i) async {
          spoken.add(i.text);
        },
        stopAudio: () async {},
        onEnd: () => ended = true,
        onError: (e) => fail('$e'),
      );
      await q.start('0');
      expect(spoken, ['Original paragraph 0.']);
      await q.completed();
      expect(spoken.length, 2);
      await q.completed();
      expect(ended, isTrue);
      expect(q.running, isFalse);
    },
  );
  test('stop during loading prevents stale audio and scrolling', () async {
    final gate = Completer<LibrarySpeechItem?>();
    var revealed = false;
    var spoken = false;
    final q = LibrarySpeechQueue(
      load: (_) => gate.future,
      reveal: (_) async {
        revealed = true;
      },
      speak: (_) async {
        spoken = true;
      },
      stopAudio: () async {},
      onEnd: () {},
      onError: (_) {},
    );
    final started = q.start('0');
    await Future<void>.delayed(Duration.zero);
    await q.stop();
    gate.complete(item(0));
    await started;
    expect(revealed, isFalse);
    expect(spoken, isFalse);
  });
  test('duplicate completion cannot skip a paragraph while loading', () async {
    final gate = Completer<LibrarySpeechItem?>();
    final spoken = <String>[];
    final q = LibrarySpeechQueue(
      load: (c) async => c == '0' ? item(0) : gate.future,
      reveal: (_) async {},
      speak: (i) async {
        spoken.add(i.cursor);
      },
      stopAudio: () async {},
      onEnd: () {},
      onError: (_) {},
    );
    await q.start('0');
    final next = q.completed();
    await q.completed();
    gate.complete(item(1));
    await next;
    expect(spoken, ['0', '1']);
  });
  test('short playback completion during speak is not lost', () async {
    late LibrarySpeechQueue q;
    var ended = false;
    q = LibrarySpeechQueue(
      load: (c) async => c == '0' ? item(0) : null,
      reveal: (_) async {},
      speak: (_) async {
        await q.completed();
      },
      stopAudio: () async {},
      onEnd: () => ended = true,
      onError: (_) {},
    );
    await q.start('0');
    expect(ended, isTrue);
  });
  test('load errors stop the session and report once', () async {
    var errors = 0;
    final q = LibrarySpeechQueue(
      load: (_) async => throw StateError('missing block'),
      reveal: (_) async {},
      speak: (_) async {},
      stopAudio: () async {},
      onEnd: () {},
      onError: (_) => errors++,
    );
    await q.start('0');
    expect(errors, 1);
    expect(q.running, isFalse);
  });
}
