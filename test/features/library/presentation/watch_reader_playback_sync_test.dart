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
import 'package:studybible2/features/library/presentation/watch_library_catalog.dart';
import 'package:studybible2/features/library/presentation/watch_library_playback.dart';

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
    'Watch state drives visible transport, paragraph, loop, and phone commands on the same player',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      installFakeAudioplayers();
      final player = TrackingPlayer();
      AudioplayersPlatformInterface.instance = player;
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('watch-reader-sync-'),
      ))!;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => dir.path,
      );
      await tester.runAsync(() async {
        await UserDatabase.instance.close();
        await AppSettingsService.instance.loadRawSetting(
          'watch_sync_test_setup',
        );
      });
      final commands = <Map<Object?, Object?>>[];
      final native = <String, Object>{
        'libraryBookID': 'lof',
        'chapter': 2,
        'verse': 1,
        'position_ms': 22000,
        'playing': true,
        'nativePlayback': true,
        'loop': 'verse',
      };
      messenger.setMockMethodCallHandler(WatchLibraryCatalog.channel, (
        call,
      ) async {
        if (call.method == 'readerCommand') {
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          commands.add(args);
          final command = args['command'] as String;
          if (command.startsWith('rate:'))
            native['reading_rate'] = double.parse(command.substring(5));
          switch (args['command']) {
            case 'pause':
              native['playing'] = false;
            case 'start':
              native['playing'] = true;
            case 'loop:book':
              native['loop'] = 'book';
            case 'loop:off':
              native['loop'] = 'off';
            case 'seek':
              native['chapter'] = args['chapter'] as int;
              native['position_ms'] = args['position_ms'] as int;
              native['playing'] = args['play'] as bool;
          }
        }
        return native;
      });
      const items = [
        LibrarySpeechItem(
          cursor: '0',
          nextCursor: '1',
          text: 'The first chapter opens here.',
        ),
        LibrarySpeechItem(
          cursor: '1',
          nextCursor: '2',
          text: 'The second chapter opens here.',
        ),
      ];
      final package = RecordedLibraryAudioPackage('Lessons on Faith', [
        RecordedLibraryAudioTrack(
          1,
          'First chapter',
          File('${dir.path}/one.mp3'),
          cues: [
            const RecordedLibraryAudioCue(
              Duration.zero,
              'The first chapter opens here.',
              sourceCursor: '0',
            ),
          ],
        ),
        RecordedLibraryAudioTrack(
          2,
          'Second chapter',
          File('${dir.path}/two.mp3'),
          cues: [
            const RecordedLibraryAudioCue(
              Duration(seconds: 20),
              'The second chapter opens here.',
              sourceCursor: '1',
            ),
          ],
        ),
      ]);
      final key = GlobalKey<RecordedLibraryAudioControlsState>();
      final revealed = <String>[];
      WatchLibraryCatalog.playback.value = null;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordedLibraryAudioControls(
              key: key,
              package: package,
              bookId: 'lof',
              beforePlay: () async {},
              load: (cursor) async =>
                  items.where((i) => i.cursor == cursor).firstOrNull,
              reveal: (item) async {
                revealed.add(item.cursor);
              },
              startCursor: '0',
              selectedCursor: () => null,
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();
      WatchLibraryCatalog.playback.value = WatchLibraryPlayback.fromNative(
        native,
      );
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Looping chapter 2, paragraph 1'), findsOneWidget);
      expect(revealed, contains('1'));
      expect(player.resumes, 0);
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Play'), findsOneWidget);
      expect(commands.last['command'], 'pause');
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);
      expect(commands.last['command'], 'start');
      await tester.tap(find.byTooltip('Looping chapter 2, paragraph 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loop book'));
      await tester.pumpAndSettle();
      expect(commands.last['command'], 'loop:book');
      expect(find.text('Looping Lessons on Faith'), findsOneWidget);
      await tester.tap(find.byTooltip('Reading speed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.25×'));
      await tester.pumpAndSettle();
      expect(commands.last['command'], 'rate:1.25');
      expect(find.text('Speed 1.25×'), findsOneWidget);
      expect(
        player.resumes,
        0,
        reason: 'Speed uses the same Watch-owned phone player',
      );

      await tester.runAsync(() => key.currentState!.playFromParagraph('1'));
      await tester.pump();
      expect(
        commands.where((c) => c['command'] == 'seek').last,
        containsPair('position_ms', 20000),
      );
      expect(commands.every((c) => c['bookId'] == 'lof'), isTrue);
      expect(find.text('Pause'), findsOneWidget);
      expect(
        player.resumes,
        0,
        reason: 'Phone controls must use the Watch-owned phone player',
      );
      WatchLibraryCatalog.playback.value = WatchLibraryPlayback.fromNative({
        ...native,
        'libraryBookID': 'wor',
      });
      await tester.pump();
      expect(
        find.text('Play'),
        findsOneWidget,
        reason: 'The old book cannot claim to own the other recording',
      );
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(commands.any((c) => c['command'] == 'libraryBook:lof'), isTrue);
      expect(find.text('Pause'), findsOneWidget);
      expect(
        player.resumes,
        0,
        reason:
            'Changing the book on the phone must update the same remote player',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      WatchLibraryCatalog.playback.value = null;
      messenger.setMockMethodCallHandler(WatchLibraryCatalog.channel, null);
      await tester.runAsync(() => UserDatabase.instance.close());
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    },
  );
}
