// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
import '../../../support/fake_audioplayers_platform.dart';
import 'recorded_heading_playback_test.dart' as support;

class RatePlayer extends support.TrackingPlayer {
  final rates = <double>[];
  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {
    rates.add(playbackRate);
  }
}

void main() {
  testWidgets(
    'visible speed changes playback while paused and retains Normal and location',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      installFakeAudioplayers();
      final player = RatePlayer();
      AudioplayersPlatformInterface.instance = player;
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('reading-speed-'),
      ))!;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => dir.path,
      );
      await tester.runAsync(() async {
        await UserDatabase.instance.close();
        await AppSettingsService.instance.loadRawSetting('speed_setup');
      });
      final package = RecordedLibraryAudioPackage('Lessons on Faith', [
        RecordedLibraryAudioTrack(
          2,
          'Lessons on Faith',
          File('${dir.path}/track.mp3'),
          cues: [
            const RecordedLibraryAudioCue(
              Duration.zero,
              'Opening words.',
              sourceCursor: '0',
            ),
            const RecordedLibraryAudioCue(
              Duration(seconds: 4),
              'A complete paragraph.',
              sourceCursor: '1',
            ),
          ],
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: defaultTargetPlatform == TargetPlatform.macOS
                    ? 900
                    : 320,
                child: RecordedLibraryAudioControls(
                  package: package,
                  bookId: 'speed-test',
                  beforePlay: () async {},
                  startCursor: '1',
                  selectedCursor: () => '1',
                  load: (cursor) async => switch (cursor) {
                    '0' => const LibrarySpeechItem(
                      cursor: '0',
                      nextCursor: '1',
                      text: 'Opening words.',
                    ),
                    '1' => const LibrarySpeechItem(
                      cursor: '1',
                      nextCursor: '2',
                      text: 'A complete paragraph.',
                    ),
                    _ => null,
                  },
                  reveal: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(find.text('Speed 1.0×'), findsOneWidget);
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        expect(
          tester.getCenter(find.byTooltip('Reading speed')).dx,
          greaterThan(tester.getCenter(find.text('Play')).dx + 200),
          reason: 'Desktop speed must be separated from the transport cluster',
        );
      }
      expect(
        tester.takeException(),
        isNull,
        reason: 'The speed control must fit a narrow phone',
      );
      await tester.tap(find.byTooltip('Reading speed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('1.25×'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Speed 1.25×'), findsOneWidget);
      expect(player.rates.last, 1.25);
      expect(
        player.resumes,
        0,
        reason: 'Changing speed while paused must not start narration',
      );
      await tester.tap(find.text('Play'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(player.rates.last, 1.25);
      expect(player.resumes, 1);
      expect(
        player.seeks.last,
        const Duration(seconds: 4),
        reason: 'Speed changes must not skip to another word',
      );
      await tester.tap(find.byTooltip('Reading speed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('1.0× (Normal)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Speed 1.0×'), findsOneWidget);
      expect(player.rates.last, 1.0);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await UserDatabase.instance.close();
        await dir.delete(recursive: true);
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );
}
