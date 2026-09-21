import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studybible2/features/reader/presentation/kokoro_mac_test_narrator.dart';

/// Reads the raw PCM samples out of a synthesized clip to tell apart two
/// very different failure modes that both look identical from the outside
/// ("the pipeline runs, nothing is heard"): (a) the model produced real,
/// non-silent audio and something downstream (AVAudioSession routing,
/// simulator/host volume) is swallowing it, vs (b) the model itself produced
/// near-zero-amplitude samples.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kokoro-generated clip has real (non-silent) PCM content', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final narrator = KokoroMacTestNarrator();
    final file = await narrator.prepare(
      text: 'In the beginning God created the heavens and the earth.',
      speed: 1.0,
    );
    final bytes = await file.readAsBytes();
    // ignore: avoid_print
    print('AMPLITUDE_PROBE fileBytes=${bytes.length}');
    const headerLength = 44;
    final data = ByteData.sublistView(bytes, headerLength);
    final sampleCount = data.lengthInBytes ~/ 2;
    var maxAbs = 0;
    var sumAbs = 0.0;
    var nonZero = 0;
    for (var i = 0; i < sampleCount; i++) {
      final s = data.getInt16(i * 2, Endian.little);
      final abs = s.abs();
      if (abs > maxAbs) maxAbs = abs;
      sumAbs += abs;
      if (s != 0) nonZero++;
    }
    final meanAbs = sampleCount == 0 ? 0.0 : sumAbs / sampleCount;
    // ignore: avoid_print
    print(
      'AMPLITUDE_PROBE_RESULT sampleCount=$sampleCount maxAbs=$maxAbs '
      '(of 32767) meanAbs=${meanAbs.toStringAsFixed(1)} '
      'nonZeroFraction=${sampleCount == 0 ? 0 : (nonZero / sampleCount).toStringAsFixed(3)}',
    );
    narrator.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
