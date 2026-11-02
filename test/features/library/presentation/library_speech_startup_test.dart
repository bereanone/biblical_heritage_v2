// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'recorded_heading_playback_test.dart' as support;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:studybible2/features/library/presentation/library_speech_controls.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
import '../../../support/fake_audioplayers_platform.dart';

class _Player extends support.TrackingPlayer {
  int pauses = 0;
  @override
  Future<void> pause(String playerId) async {
    pauses++;
  }
}

class _Target implements ReaderAutoScrollTarget {
  @override
  bool get isAttached => false;
  @override
  bool scrollBy(double delta) => false;
}

void main() {
  testWidgets(
    'enabled recording shows Play on entry, while Audio Off hides and blocks all playback',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      installFakeAudioplayers();
      final player = _Player();
      AudioplayersPlatformInterface.instance = player;
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('speech-startup-'),
      ))!;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      await tester.runAsync(() async {
        await UserDatabase.instance.close();
        await AppSettingsService.instance.loadRawSetting('startup_test');
      });
      final gate = Completer<RecordedLibraryAudioPackage?>();
      final controller = MacReaderAutoScrollController(
        scrollTarget: _Target(),
        driveFrames: false,
        preferences: const MacAutoscrollPreferences(audioEnabled: true),
      );
      final package = RecordedLibraryAudioPackage('Lessons on Faith', [
        RecordedLibraryAudioTrack(
          1,
          'Lessons on Faith',
          File('${dir.path}/track.mp3'),
          cues: [
            const RecordedLibraryAudioCue(
              Duration.zero,
              'A complete opening.',
              sourceCursor: '1',
            ),
          ],
        ),
      ]);
      final key = GlobalKey<LibrarySpeechControlsState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibrarySpeechControls(
              key: key,
              controller: controller,
              initialCursor: () => '1',
              load: (cursor) async => cursor == '1'
                  ? const LibrarySpeechItem(
                      cursor: '1',
                      nextCursor: '2',
                      text: 'A complete opening.',
                    )
                  : null,
              reveal: (_) async {},
              onPaused: () {},
              bookId: 'startup-test',
              title: 'Lessons on Faith',
              prepareRecording: () => gate.future,
            ),
          ),
        ),
      );
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Preparing recording…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Play'))
            .onPressed,
        isNull,
      );
      gate.complete(package);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(find.byType(RecordedLibraryAudioControls), findsOneWidget);
      expect(find.text('Preparing recording…'), findsNothing);
      expect(find.text('Play'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Play'))
            .onPressed,
        isNotNull,
      );
      final stalePlay = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Play'))
          .onPressed!;
      await tester.tap(find.text('Play'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(player.resumes, 1);
      controller.updatePreferences(
        const MacAutoscrollPreferences(audioEnabled: false),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      expect(find.text('Play'), findsNothing);
      expect(find.byTooltip('Reading speed'), findsNothing);
      expect(player.pauses, greaterThan(0));
      stalePlay();
      await tester.runAsync(() => key.currentState!.playFromParagraph('1'));
      await tester.pump();
      expect(
        player.resumes,
        1,
        reason: 'Off must block stale transport and selection callbacks',
      );
      expect(controller.audioEnabled, isFalse);
      controller.updatePreferences(
        const MacAutoscrollPreferences(audioEnabled: true),
      );
      await tester.pump();
      expect(find.text('Play'), findsOneWidget);
      expect(player.resumes, 1, reason: 'Enabling Audio must leave it paused');
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      controller.dispose();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await UserDatabase.instance.close();
        await dir.delete(recursive: true);
      });
    },
  );
}
