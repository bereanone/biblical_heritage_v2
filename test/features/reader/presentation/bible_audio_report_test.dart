import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:studybible2/core/audio/narration_diagnostics.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/reader/presentation/bible_audio_settings.dart';
import 'package:studybible2/features/reader/presentation/bundled_bible_audio_narrator.dart';

class _Target implements ReaderAutoScrollTarget {
  @override
  bool get isAttached => true;
  @override
  bool scrollBy(double delta) => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'audio report opens only on request, copies only on explicit tap, and leaves playback unchanged',
    (tester) async {
      final controller = MacReaderAutoScrollController(
        scrollTarget: _Target(),
        driveFrames: false,
        narrationControlsPacing: true,
        preferences: const MacAutoscrollPreferences(audioEnabled: true),
      );
      addTearDown(controller.dispose);
      controller.setSignedStep(1);
      var requests = 0;
      var changes = 0;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BibleAudioSettings(
              controller: controller,
              onPreferencesChanged: (_) {
                changes++;
              },
              onAnnouncementChanged: (_, _) {},
              onPronunciations: () {},
              onDiagnosticReport: () async {
                requests++;
                return 'local audio report';
              },
            ),
          ),
        ),
      );
      expect(requests, 0);
      expect(copied, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('bible-audio-report')),
      );
      await tester.tap(find.byKey(const ValueKey('bible-audio-report')));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(copied, isNull);
      expect(find.text('local audio report'), findsOneWidget);
      expect(controller.audioEnabled, isTrue);
      expect(controller.isScrolling, isTrue);
      expect(changes, 0);
      await tester.tap(find.text('Copy report'));
      await tester.pumpAndSettle();
      expect(copied, 'local audio report');
      expect(changes, 0);
      expect(controller.isScrolling, isTrue);
    },
  );
  test(
    'report captures native evidence without issuing playback commands',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Biblical Heritage',
        packageName: 'com.deanbowen.bibleappmac',
        version: '2.0.6',
        buildNumber: '157',
        buildSignature: '',
      );
      NarrationDiagnostics.recordTagPlaybackSource('generated_bible_speech');
      final calls = <String>[];
      const channel = MethodChannel('studybible/recorded_audio');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'diagnostics') {
              return {
                'readingRequested': true,
                'chapterPlaying': false,
                'pendingSeekMs': 10000,
              };
            }
            return null;
          });
      final narrator = BundledBibleAudioNarrator(
        onSegmentStart: (_, _) {},
        onChapterComplete: () {},
        onError: (_) {},
      );
      final report =
          jsonDecode(await narrator.diagnosticReport(audioEnabled: true))
              as Map;
      expect(calls, ['diagnostics']);
      expect(report['build'], '157');
      expect(report['lastTagPlaybackSource'], 'generated_bible_speech');
      expect(report['native']['pendingSeekMs'], 10000);
      expect(report['native']['chapterPlaying'], false);
      expect(report['note'], contains('cannot confirm audible sound'));
      narrator.dispose();
      await Future<void>.delayed(Duration.zero);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  test(
    'unsupported rate reports the failure without an unhandled future or autoplay',
    () async {
      final errors = <String>[];
      final calls = <String>[];
      const channel = MethodChannel('studybible/recorded_audio');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'setRate') {
              throw PlatformException(
                code: 'UNSUPPORTED',
                message: 'Try voice speed 1.0',
              );
            }
            return null;
          });
      final narrator = BundledBibleAudioNarrator(
        onSegmentStart: (_, _) {},
        onChapterComplete: () {},
        onError: errors.add,
      );
      await narrator.setRate(1.25);
      expect(errors, ['Try voice speed 1.0']);
      expect(narrator.playing, isFalse);
      expect(calls, ['setRate']);
      narrator.dispose();
      await Future<void>.delayed(Duration.zero);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
