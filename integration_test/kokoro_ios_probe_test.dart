import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studybible2/features/reader/presentation/kokoro_mac_test_narrator.dart';

/// Temporary probe: exercises the real native Kokoro/sherpa_onnx engine on
/// whatever platform this test runs on, bypassing the app's UI narration
/// gates entirely. Used to establish whether the offline TTS engine (and its
/// `lang: 'lexicon'` config, patched only for macOS) works on iOS before any
/// UI gate is widened.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kokoro engine can synthesize speech on this platform', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());

    Duration? readyDuration;
    String? engineErrorMessage;
    final narrator = KokoroMacTestNarrator(
      onPlaybackReady: (d) => readyDuration = d,
      onError: (e) => engineErrorMessage = e,
    );

    Object? thrown;
    StackTrace? thrownStack;
    try {
      final file = await narrator.prepare(
        text: 'In the beginning God created the heavens and the earth.',
        speed: 1.0,
      );
      final exists = await file.exists();
      final length = exists ? await file.length() : 0;
      // ignore: avoid_print
      print(
        'KOKORO_PROBE_RESULT file=${file.path} exists=$exists bytes=$length',
      );
    } catch (e, st) {
      thrown = e;
      thrownStack = st;
      // ignore: avoid_print
      print('KOKORO_PROBE_ERROR $e');
      // ignore: avoid_print
      print(thrownStack);
    }
    // ignore: avoid_print
    print(
      'KOKORO_PROBE_DONE thrown=$thrown engineError=$engineErrorMessage ready=$readyDuration',
    );

    narrator.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
