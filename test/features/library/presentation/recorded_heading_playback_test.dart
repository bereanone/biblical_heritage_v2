// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
import '../../../support/fake_audioplayers_platform.dart';

class TrackingPlayer implements AudioplayersPlatformInterface {
  final events = StreamController<AudioEvent>.broadcast();
  final seeks = <Duration>[];
  int resumes = 0;
  @override
  Stream<AudioEvent> getEventStream(String playerId) => events.stream;
  @override
  Future<int?> getDuration(String playerId) async => 60000;
  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;
  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    scheduleMicrotask(
      () => events.add(
        const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
      ),
    );
  }

  @override
  Future<void> seek(String playerId, Duration position) async {
    seeks.add(position);
    scheduleMicrotask(
      () =>
          events.add(const AudioEvent(eventType: AudioEventType.seekComplete)),
    );
  }

  @override
  Future<void> resume(String playerId) async {
    resumes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  testWidgets(
    'title and author play the chapter opening; successful actions clear stale missing-audio feedback',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      installFakeAudioplayers();
      final player = TrackingPlayer();
      AudioplayersPlatformInterface.instance = player;
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('heading-playback-'),
      ))!;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      await tester.runAsync(() async {
        await UserDatabase.instance.close();
        await AppSettingsService.instance.loadRawSetting('heading_test_setup');
      });
      const items = [
        LibrarySpeechItem(
          cursor: '589',
          nextCursor: '590',
          text: 'The previous chapter ends here.',
        ),
        LibrarySpeechItem(
          cursor: '590',
          nextCursor: '591',
          text: 'Living by the Word',
          isHeading: true,
        ),
        LibrarySpeechItem(
          cursor: '591',
          nextCursor: '592',
          text: 'A. T. Jones',
          isHeading: true,
        ),
        LibrarySpeechItem(
          cursor: '592',
          nextCursor: '593',
          text: 'Now the righteousness of God is manifested.',
        ),
        LibrarySpeechItem(
          cursor: '593',
          nextCursor: '594',
          text: 'A genuinely unrecorded paragraph.',
        ),
        LibrarySpeechItem(
          cursor: '594',
          nextCursor: '595',
          text: 'Next chapter',
          isHeading: true,
        ),
        LibrarySpeechItem(
          cursor: '595',
          nextCursor: '596',
          text: 'The next chapter begins here.',
        ),
      ];
      Future<LibrarySpeechItem?> load(String cursor) async =>
          items.where((i) => i.cursor == cursor).firstOrNull;
      final package = RecordedLibraryAudioPackage('Lessons on Faith', [
        RecordedLibraryAudioTrack(
          1,
          'Living by the Word',
          File('${dir.path}/chapter1.mp3'),
          cues: [
            const RecordedLibraryAudioCue(
              Duration(seconds: 5),
              'Now the righteousness of God is manifested.',
              sourceCursor: '592',
            ),
          ],
        ),
        RecordedLibraryAudioTrack(
          2,
          'Next chapter',
          File('${dir.path}/chapter2.mp3'),
          cues: [
            const RecordedLibraryAudioCue(
              Duration(seconds: 3),
              'The next chapter begins here.',
              sourceCursor: '595',
            ),
          ],
        ),
      ]);
      final key = GlobalKey<RecordedLibraryAudioControlsState>();
      var selected = '590';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordedLibraryAudioControls(
              key: key,
              package: package,
              bookId: 'heading-playback',
              beforePlay: () async {},
              load: load,
              reveal: (_) async {},
              startCursor: '589',
              selectedCursor: () => selected,
            ),
          ),
        ),
      );
      Future<void> complete(Future<void> action) async {
        var done = false;
        action.whenComplete(() => done = true);
        for (var i = 0; i < 150 && !done; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(
          done,
          isTrue,
          reason: 'Playback action must finish without reopening the reader.',
        );
        await action;
      }

      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      Future<void> play(String cursor, {int offset = 0}) async {
        selected = cursor;
        await complete(
          key.currentState!.playFromParagraph(cursor, startOffset: offset),
        );
        await tester.pump();
      }

      await play('590', offset: 7);
      expect(player.resumes, 1);
      expect(
        player.seeks.last,
        Duration.zero,
        reason: 'A title selection must start before the first body cue.',
      );
      expect(find.textContaining('No recorded audio'), findsNothing);
      await play('591', offset: 3);
      expect(player.resumes, 2);
      expect(
        player.seeks.last,
        Duration.zero,
        reason: 'The author byline belongs to the same chapter opening.',
      );
      await play('593');
      expect(
        find.text('No recorded audio is available for this paragraph.'),
        findsOneWidget,
        reason: 'Genuine missing audio remains diagnosable.',
      );
      await play('592');
      expect(player.resumes, 3);
      expect(
        find.textContaining('No recorded audio'),
        findsNothing,
        reason: 'Successful playback clears stale feedback without reopening.',
      );
      await play('593');
      expect(find.textContaining('No recorded audio'), findsOneWidget);
      selected = '594';
      await complete(key.currentState!.selectForPlayback('594'));
      await tester.pump();
      expect(
        find.textContaining('No recorded audio'),
        findsNothing,
        reason: 'Contents navigation clears the previous failure.',
      );
      await play('593');
      expect(find.textContaining('No recorded audio'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous chapter'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(
        find.textContaining('No recorded audio'),
        findsNothing,
        reason: 'Chapter controls clear stale feedback.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await UserDatabase.instance.close();
        await player.events.close();
        await dir.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
    },
  );
}
