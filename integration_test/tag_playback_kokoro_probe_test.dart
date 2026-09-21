import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studybible2/features/reader/presentation/kokoro_engine_host.dart';
import 'package:studybible2/features/reader/presentation/kokoro_mac_test_narrator.dart';

/// Real-engine check for tag playback (run on macOS and on a physical iPhone):
/// the Bible reader's `prepare()` path and the tag popup's `renderClip()` path
/// must share one engine, both must produce audible audio, and one narrator
/// closing must not break the other. Prints per-clip synthesis latency.
/// Nothing is played aloud.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const short =
      'John 3, verse 16. For God so loved the world, that he gave his only '
      'begotten Son.';
  const verse =
      'Genesis 1, verse 2. And the earth was without form, and void; and '
      'darkness was upon the face of the deep. And the Spirit of God moved '
      'upon the face of the waters.';
  const note =
      'This note is modern prose. We live in hope, and we lived by faith. '
      'Read it again and let it lead you back to the promise.';

  ({double seconds, int maxAbs}) inspect(File file) {
    final bytes = file.readAsBytesSync();
    final header = ByteData.sublistView(bytes, 0, 44);
    final rate = header.getUint32(24, Endian.little);
    final data = ByteData.sublistView(bytes, 44);
    var maxAbs = 0;
    for (var i = 0; i < data.lengthInBytes ~/ 2; i++) {
      final v = data.getInt16(i * 2, Endian.little).abs();
      if (v > maxAbs) maxAbs = v;
    }
    return (seconds: data.lengthInBytes / 2 / rate, maxAbs: maxAbs);
  }

  testWidgets(
    'reader prepare() and tag renderClip() share one engine',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final host = KokoroEngineHost.instance;
      expect(host.leaseCount, 0);

      final reader = KokoroMacTestNarrator();
      final tag = KokoroMacTestNarrator();

      final cold = Stopwatch()..start();
      final readerClip = await reader.prepare(text: short, speed: 1.0);
      cold.stop();
      // ignore: avoid_print
      print(
        'PROBE cold reader prepare (engine start + clip) ${cold.elapsedMilliseconds} ms',
      );
      expect(host.leaseCount, 1);
      expect(inspect(readerClip).maxAbs, greaterThan(500));

      final files = <File>[];
      for (final entry in {
        'short verse': short,
        'long verse': verse,
        'modern note': note,
      }.entries) {
        final watch = Stopwatch()..start();
        final file = await tag.renderClip(text: entry.value, speed: 1.0);
        watch.stop();
        files.add(file);
        final info = inspect(file);
        // ignore: avoid_print
        print(
          'PROBE renderClip ${entry.key}: ${watch.elapsedMilliseconds} ms for '
          '${info.seconds.toStringAsFixed(1)} s of audio '
          '(${(watch.elapsedMilliseconds / 1000 / info.seconds).toStringAsFixed(2)}x real time), '
          'peak ${info.maxAbs}',
        );
        expect(
          info.maxAbs,
          greaterThan(500),
          reason: '${entry.key} is audible',
        );
      }
      // Both narrators hold a lease on the one engine.
      expect(host.leaseCount, 2);

      // The reader's narrator closing must not take the tag's engine with it.
      reader.dispose();
      expect(host.leaseCount, 1);
      final after = await tag.renderClip(text: short, speed: 1.0);
      expect(inspect(after).maxAbs, greaterThan(500));

      tag.dispose();
      expect(host.leaseCount, 0);

      // A fresh narrator after everything closed starts a new engine cleanly.
      final again = KokoroMacTestNarrator();
      final fresh = await again.renderClip(text: short, speed: 1.0);
      expect(inspect(fresh).maxAbs, greaterThan(500));
      again.dispose();
      expect(host.leaseCount, 0);

      for (final file in [readerClip, after, fresh, ...files]) {
        if (file.existsSync()) file.deleteSync();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
