import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/utilities/presentation/recorded_bible_audio_screen.dart';

void main() {
  testWidgets('Qwen test chapters can be added for phone playback', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('qwen-audio-test-');
    final calls = <MethodCall>[];
    const channel = MethodChannel('studybible/recorded_audio');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      directory.deleteSync(recursive: true);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecordedBibleAudioScreen(
            documentsDirectory: () async => directory,
            loadBooks: () async => [
              const BookRecord(
                bookNumber: 66,
                bookName: 'Revelation',
                bookIndex: 65,
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    final first = File(
      '${directory.path}/recorded_bible_audio/66_Rev_001.m4a',
    );
    final second = File(
      '${directory.path}/recorded_bible_audio/66_Rev_002.m4a',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Add Qwen test chapters'));
      for (var attempt = 0; attempt < 100; attempt++) {
        if (await first.exists() && await second.exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.textContaining('Unable to load asset'), findsNothing);
    expect(first.existsSync(), isTrue);
    expect(second.existsSync(), isTrue);
    expect(first.lengthSync(), greaterThan(1000000));
    expect(second.lengthSync(), greaterThan(1000000));
    expect(find.text('Revelation 1'), findsOneWidget);
    expect(find.text('Revelation 2'), findsOneWidget);
    await tester.tap(find.text('Revelation 1'));
    await tester.pump();
    expect(
      (calls.lastWhere((call) => call.method == 'load').arguments
          as Map)['path'],
      first.path,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'saved audio resumes without reload and controls stay independent',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'recorded-bible-test-',
      );
      final audio = Directory('${directory.path}/recorded_bible_audio')
        ..createSync();
      File('${audio.path}/01-001.m4a').writeAsBytesSync([0]);
      File('${audio.path}/01-002.m4a').writeAsBytesSync([0]);
      final calls = <MethodCall>[];
      const channel = MethodChannel('studybible/recorded_audio');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'state') {
          return {'duration': 120.0, 'position': 30.0, 'playing': true};
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        directory.deleteSync(recursive: true);
      });
      Future<void> settleIO() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: RecordedBibleAudioScreen(
              documentsDirectory: () async => directory,
              loadBooks: () async => [
                const BookRecord(
                  bookNumber: 1,
                  bookName: 'Genesis',
                  bookIndex: 0,
                ),
              ],
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settleIO();
      await tester.tap(find.text('Genesis 1'));
      await settleIO();
      expect(calls.where((c) => c.method == 'load').length, 1);
      await tester.tap(find.byIcon(Icons.pause));
      await settleIO();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await settleIO();
      expect(calls.where((c) => c.method == 'load').length, 1);
      expect(calls.where((c) => c.method == 'play').length, 2);
      await tester.pump(const Duration(milliseconds: 500));
      await settleIO();
      var sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      sliders[0].onChangeEnd!(45);
      await settleIO();
      expect(calls.lastWhere((c) => c.method == 'seek').arguments, {
        'seconds': 45.0,
      });
      await tester.runAsync(() async {
        sliders[1].onChangeEnd!(1.25);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settleIO();
      expect(calls.lastWhere((c) => c.method == 'setRate').arguments, {
        'rate': 1.25,
      });
      sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      await tester.runAsync(() async {
        sliders[2].onChangeEnd!(-2);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settleIO();
      expect(calls.lastWhere((c) => c.method == 'setPitch').arguments, {
        'pitch': -2.0,
      });
      await tester.runAsync(() async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('complete'),
          ),
          (_) {},
        );
      });
      await settleIO();
      expect(
        (calls.lastWhere((c) => c.method == 'load').arguments as Map)['path'],
        endsWith('01-002.m4a'),
      );
      expect(
        calls.every(
          (c) => {
            'setRate',
            'setPitch',
            'load',
            'play',
            'pause',
            'state',
            'seek',
            'stop',
          }.contains(c.method),
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await settleIO();
      expect(calls.last.method, 'stop');
    },
  );
}
