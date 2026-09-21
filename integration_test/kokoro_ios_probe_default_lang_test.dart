import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:studybible2/features/reader/presentation/kokoro_mac_test_narrator.dart';

/// Follow-up probe: kokoro_ios_probe_test.dart showed the real app engine
/// (lang: 'lexicon', the macOS-only patched sentinel) returns empty audio on
/// iOS. This isolates whether the underlying sherpa_onnx_ios engine can
/// synthesize speech at all on this platform when given the *unpatched*
/// default lang config, using the same staged model assets.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kokoro engine with default (non-lexicon) lang config', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());

    // Stage assets via the real narrator once (its own generate() call is
    // expected to fail/throw here; we only need the staged files it leaves
    // behind on disk).
    final narrator = KokoroMacTestNarrator();
    try {
      await narrator.prepare(text: 'stage assets', speed: 1.0);
    } catch (_) {
      // Expected: lang: 'lexicon' produces no audio on unpatched iOS engine.
    }
    narrator.dispose();

    final support = await getApplicationSupportDirectory();
    final root = '${support.path}/kokoro-multi-lang-v1_0-v2';

    sherpa.initBindings();
    final engine = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: '$root/model.onnx',
            voices: '$root/voices.bin',
            tokens: '$root/tokens.txt',
            dataDir: '$root/espeak-ng-data',
            lexicon: '$root/context-lexicon-v1.txt,$root/lexicon-us-en.txt',
            // Deliberately omit lang (defaults to '') to exercise the
            // stock, unpatched espeak-based frontend as a baseline.
          ),
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    try {
      final audio = engine.generate(
        text: 'In the beginning God created the heavens and the earth.',
        sid: 16,
        speed: 1.0,
      );
      // ignore: avoid_print
      print(
        'KOKORO_DEFAULT_LANG_RESULT samples=${audio.samples.length} sampleRate=${audio.sampleRate}',
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('KOKORO_DEFAULT_LANG_ERROR $e');
      // ignore: avoid_print
      print(st);
    } finally {
      engine.free();
    }
    // ignore: avoid_print
    print('KOKORO_DEFAULT_LANG_DONE');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
