import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bundled_bible_recording_cache.dart';

void main() {
  late Directory root;
  late File cached;
  final shipped = Uint8List.fromList([1, 2, 3, 4, 5]);
  final hash = sha256.convert(shipped).toString();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bible-recording-cache-test-');
    cached = File('${root.path}/chapter.m4a');
  });
  tearDown(() => root.delete(recursive: true));

  test('verified cache plays without reloading bundled audio', () async {
    await cached.writeAsBytes(shipped);
    expect(
      await materializeVerifiedBibleRecording(
        destination: cached,
        expectedSha256: hash,
        loadBytes: () async => throw StateError('bundle should not be opened'),
      ),
      cached.path,
    );
    expect(await cached.readAsBytes(), shipped);
  });

  test(
    'nonempty damaged chapter is replaced from verified shipped bytes',
    () async {
      await cached.writeAsBytes([1, 2]);
      expect(await bibleRecordingMatches(cached, hash), isFalse);
      await materializeVerifiedBibleRecording(
        destination: cached,
        expectedSha256: hash,
        loadBytes: () async => shipped,
      );
      expect(await cached.readAsBytes(), shipped);
      expect(await bibleRecordingMatches(cached, hash), isTrue);
      expect(await root.list().length, 1);
    },
  );

  test('wrong replacement never overwrites the existing cache', () async {
    await cached.writeAsBytes([9]);
    await expectLater(
      materializeVerifiedBibleRecording(
        destination: cached,
        expectedSha256: hash,
        loadBytes: () async => Uint8List.fromList([4, 5]),
      ),
      throwsStateError,
    );
    expect(await cached.readAsBytes(), [9]);
    expect(await root.list().length, 1);
  });

  test(
    'missing source reports failure and does not create a recording',
    () async {
      await expectLater(
        materializeVerifiedBibleRecording(
          destination: cached,
          expectedSha256: hash,
          loadBytes: () async => throw StateError('source missing'),
        ),
        throwsStateError,
      );
      expect(await cached.exists(), isFalse);
    },
  );

  test(
    'overlapping chapter requests both produce complete verified audio',
    () async {
      await Future.wait(
        List.generate(
          2,
          (_) => materializeVerifiedBibleRecording(
            destination: cached,
            expectedSha256: hash,
            loadBytes: () async => shipped,
          ),
        ),
      );
      expect(await cached.readAsBytes(), shipped);
      expect(await root.list().length, 1);
    },
  );
}
