import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';

void main() {
  test('Contents heading resolves forward and stops at next chapter', () async {
    final items = {
      '10': const LibrarySpeechItem(
        cursor: '10',
        nextCursor: '11',
        text: 'Chapter twelve',
      ),
      '11': const LibrarySpeechItem(
        cursor: '11',
        nextCursor: '12',
        text: 'Many people ask questions about the Bible.',
      ),
      '12': const LibrarySpeechItem(
        cursor: '12',
        nextCursor: '13',
        text: 'Chapter thirteen',
      ),
    };
    Future<LibrarySpeechItem?> load(String cursor) async => items[cursor];
    expect(
      await recordedCursorForNavigation(
        cursor: '10',
        load: load,
        recordedCursors: {'11'},
        endCursor: '12',
      ),
      '11',
    );
    expect(
      await recordedCursorForNavigation(
        cursor: '10',
        load: load,
        recordedCursors: {'12'},
        endCursor: '12',
      ),
      isNull,
    );
  });
  testWidgets(
    'Contents replaces saved chapter and resets a repeated chapter selection without autoplay',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        (_) async => 1,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global/events'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (call) async {
          calls.add(call.method);
          if (call.method == 'create') {
            final id = (call.arguments as Map)['playerId'];
            messenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$id'),
              (_) async => null,
            );
          }
          if (call.method == 'getCurrentPosition' ||
              call.method == 'getDuration') {
            return null;
          }
          return 1;
        },
      );
      final dir = (await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final dir = await Directory.systemTemp.createTemp('toc_audio_');
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
        await AppSettingsService.instance.saveRawSetting(
          'library_recorded_audio_position:test-toc',
          jsonEncode({'chapter': 1, 'position_ms': 45000}),
        );
        return dir;
      }))!;
      const first = 'Nature and revelation alike testify of the love of God.';
      const second =
          'Many especially those who are young have questions about faith.';
      final items = {
        '0': const LibrarySpeechItem(
          cursor: '0',
          nextCursor: '1',
          text: 'Chapter one',
        ),
        '1': const LibrarySpeechItem(cursor: '1', nextCursor: '2', text: first),
        '2': const LibrarySpeechItem(
          cursor: '2',
          nextCursor: '3',
          text: 'Chapter twelve',
        ),
        '3': const LibrarySpeechItem(
          cursor: '3',
          nextCursor: '4',
          text: second,
        ),
      };
      final revealed = <String>[];
      final key = GlobalKey<RecordedLibraryAudioControlsState>();
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecordedLibraryAudioControls(
                key: key,
                package: RecordedLibraryAudioPackage('Test', [
                  RecordedLibraryAudioTrack(
                    1,
                    'One',
                    File('${dir.path}/1.mp3'),
                    cues: [const RecordedLibraryAudioCue(Duration.zero, first)],
                  ),
                  RecordedLibraryAudioTrack(
                    12,
                    'Twelve',
                    File('${dir.path}/12.mp3'),
                    cues: [
                      const RecordedLibraryAudioCue(Duration.zero, second),
                    ],
                  ),
                ]),
                bookId: 'test-toc',
                startCursor: '0',
                load: (cursor) async => items[cursor],
                reveal: (item) async {
                  revealed.add(item.sourceCursor);
                },
                selectedCursor: () => null,
                beforePlay: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => key.currentState!
            .selectForPlayback('2')
            .timeout(const Duration(seconds: 10)),
      );
      await tester.pump();
      final saved = await tester.runAsync(
        () => AppSettingsService.instance.loadRawSetting(
          'library_recorded_audio_position:test-toc',
        ),
      );
      expect(jsonDecode(saved!), {
        'chapter': 12,
        'position_ms': 0,
        'include_margin_notes': true,
      });
      await tester.runAsync(() => key.currentState!.selectForPlayback('2'));
      await tester.pump();
      expect(calls, isNot(contains('resume')));
      expect(find.text('Play'), findsOneWidget);
      await tester.runAsync(
        () => key.currentState!.selectForPlayback('0', endCursor: '2'),
      );
      await tester.pump();
      final back = await tester.runAsync(
        () => AppSettingsService.instance.loadRawSetting(
          'library_recorded_audio_position:test-toc',
        ),
      );
      expect(jsonDecode(back!), {
        'chapter': 1,
        'position_ms': 0,
        'include_margin_notes': true,
      });
      await tester.pump();
      // Paused transport navigation must also reveal its destination.
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Next chapter'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(revealed.last, '3');
      expect(find.text('Play'), findsOneWidget);
      final next = await tester.runAsync(
        () => AppSettingsService.instance.loadRawSetting(
          'library_recorded_audio_position:test-toc',
        ),
      );
      expect(jsonDecode(next!), {
        'chapter': 12,
        'position_ms': 0,
        'include_margin_notes': true,
      });
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Previous chapter'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(revealed.last, '1');
      expect(calls, isNot(contains('resume')));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await UserDatabase.instance.close();
        await dir.delete(recursive: true);
      });
    },
  );
}
