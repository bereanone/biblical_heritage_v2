import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:studybible2/features/reader/presentation/kokoro_mac_test_narrator.dart';

/// Isolates which layer of the narration pipeline is failing on a simulator
/// where synthesis apparently succeeds but nothing is heard, by running two
/// clips through the *exact* playback call the app uses
/// (`AudioPlayer().play(DeviceFileSource(path))`, as in
/// kokoro_mac_test_narrator.dart:118):
///   1. A known-good, independently-generated 1kHz sine tone (no Kokoro
///      involved at all) - isolates AudioPlayer/AVAudioSession/output route.
///   2. A real Kokoro-synthesized clip - the actual app path end to end.
/// For each: captures play() errors, player volume/state, whether playback
/// position actually advances in real time (proof of real decoding, not an
/// instant no-op "completion"), and dumps the exact WAV bytes as base64 so
/// they can be reassembled and inspected/listened to outside the simulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Audio pipeline isolation: tone vs Kokoro clip', (tester) async {
    Future<File> writeSineTone() async {
      const sampleRate = 44100;
      const seconds = 1.0;
      const freq = 1000.0;
      final sampleCount = (sampleRate * seconds).round();
      const headerLength = 44;
      final bytes = ByteData(headerLength + sampleCount * 2);
      void text(int offset, String value) {
        for (var i = 0; i < value.length; i++) {
          bytes.setUint8(offset + i, value.codeUnitAt(i));
        }
      }

      text(0, 'RIFF');
      bytes.setUint32(4, 36 + sampleCount * 2, Endian.little);
      text(8, 'WAVEfmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, 1, Endian.little);
      bytes.setUint32(24, sampleRate, Endian.little);
      bytes.setUint32(28, sampleRate * 2, Endian.little);
      bytes.setUint16(32, 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      text(36, 'data');
      bytes.setUint32(40, sampleCount * 2, Endian.little);
      for (var i = 0; i < sampleCount; i++) {
        final t = i / sampleRate;
        // Fade in/out 20ms to avoid click artifacts, otherwise full-scale.
        final fade = math.min(1.0, math.min(i / (sampleRate * 0.02),
            (sampleCount - i) / (sampleRate * 0.02)));
        final sample = (math.sin(2 * math.pi * freq * t) * 32000 * fade)
            .round()
            .clamp(-32768, 32767);
        bytes.setInt16(headerLength + i * 2, sample, Endian.little);
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/reference-tone.wav');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return file;
    }

    Future<void> dumpBase64(String label, File file) async {
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      // ignore: avoid_print
      print('B64_START $label bytes=${bytes.length}');
      const chunkSize = 4000;
      for (var i = 0; i < b64.length; i += chunkSize) {
        final end = math.min(i + chunkSize, b64.length);
        // ignore: avoid_print
        print('B64_CHUNK $label ${b64.substring(i, end)}');
      }
      // ignore: avoid_print
      print('B64_END $label');
    }

    Future<void> playAndObserve(String label, String path) async {
      final player = AudioPlayer();
      final states = <String>[];
      final positions = <int>[];
      String? errorMessage;
      final sub = player.onPlayerStateChanged.listen(
        (s) => states.add(s.toString()),
      );
      final completer = Completer<void>();
      final completeSub = player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });
      final errorSub = player.onLog.listen((msg) {
        // ignore: avoid_print
        print('PLAYER_LOG $label $msg');
      });
      try {
        // ignore: avoid_print
        print('PLAYER_VOLUME_BEFORE $label ${player.volume}');
        await player.play(DeviceFileSource(path));
      } catch (e) {
        errorMessage = e.toString();
      }
      // ignore: avoid_print
      print('PLAY_CALL_RETURNED $label error=$errorMessage state=${player.state}');
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline) && !completer.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final pos = await player.getCurrentPosition();
        positions.add(pos?.inMilliseconds ?? -1);
        // ignore: avoid_print
        print(
          'POLL $label state=${player.state} '
          'position=${pos?.inMilliseconds}ms',
        );
      }
      final duration = await player.getDuration();
      // ignore: avoid_print
      print(
        'RESULT $label completed=${completer.isCompleted} '
        'finalState=${player.state} duration=${duration?.inMilliseconds}ms '
        'positions=$positions error=$errorMessage',
      );
      await sub.cancel();
      await completeSub.cancel();
      await errorSub.cancel();
      await player.dispose();
    }

    await tester.pumpWidget(const SizedBox());

    // 1. Known-good reference tone through the app's exact playback call.
    final tone = await writeSineTone();
    await tester.runAsync(() => playAndObserve('TONE', tone.path));
    await tester.runAsync(() => dumpBase64('TONE', tone));

    // 2. Real Kokoro-synthesized clip through the same call.
    final narrator = KokoroMacTestNarrator();
    File? kokoroClip;
    String? kokoroError;
    await tester.runAsync(() async {
      try {
        kokoroClip = await narrator.prepare(
          text: 'In the beginning God created the heavens and the earth.',
          speed: 1.0,
        );
      } catch (e) {
        kokoroError = e.toString();
      }
    });
    // ignore: avoid_print
    print('KOKORO_PREPARE error=$kokoroError file=${kokoroClip?.path}');
    if (kokoroClip != null) {
      await tester.runAsync(() => playAndObserve('KOKORO', kokoroClip!.path));
      await tester.runAsync(() => dumpBase64('KOKORO', kokoroClip!));
    }
    narrator.dispose();

    // ignore: avoid_print
    print(jsonEncode({'stage': 'isolation_done'}));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
