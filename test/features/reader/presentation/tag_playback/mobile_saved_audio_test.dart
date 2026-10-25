import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/local_narration_policy.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_note_audio_cache.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_planner.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

Future<File> wav(File file) async {
  final bytes = Uint8List(48);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  bytes.setRange(8, 12, ascii.encode('WAVE'));
  bytes.setRange(12, 16, ascii.encode('fmt '));
  bytes.setRange(36, 40, ascii.encode('data'));
  final data = ByteData.sublistView(bytes);
  data.setUint32(4, 40, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 24000, Endian.little);
  data.setUint32(28, 48000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(40, 4, Endian.little);
  return file.writeAsBytes(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late TagNoteAudioCache cache;
  var renders = 0;
  final speeds = <double>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('saved-note-policy-');
    renders = 0;
    speeds.clear();
    cache = TagNoteAudioCache.forTesting(
      directory: () async => root,
      key: (text, speed) async =>
          base64Url.encode(utf8.encode('$text|$speed')).replaceAll('=', ''),
      render: (text, speed) async {
        renders++;
        speeds.add(speed);
        return wav(File('${root.path}/render-$renders.wav'));
      },
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await root.delete(recursive: true);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group(platform.name, () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);
      test('playback waits for all chunks of a save already in progress', () async {
        final firstStarted = Completer<void>();
        final secondStarted = Completer<void>();
        final releaseSecond = Completer<void>();
        final renderedText = <String>[];
        cache = TagNoteAudioCache.forTesting(
          directory: () async => root,
          key: (text, speed) async => base64Url.encode(utf8.encode('$text|$speed')),
          render: (text, speed) async {
            renderedText.add(text);
            if (text == 'First paragraph.') firstStarted.complete();
            if (text == 'Second paragraph.') {
              secondStarted.complete();
              await releaseSecond.future;
            }
            return wav(File('${root.path}/render-${renderedText.length}.wav'));
          },
        );
        cache.scheduleNoteText('First paragraph.\nSecond paragraph.', entryKey: 'note1');
        await firstStarted.future;
        await secondStarted.future;
        var firstPlayable = false;
        var secondPlayable = false;
        final first = cache.renderOrGet('First paragraph.', speed: 1)
            .then((value) { firstPlayable = true; return value; });
        final second = cache.renderOrGet('Second paragraph.', speed: 1.5)
            .then((value) { secondPlayable = true; return value; });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(firstPlayable, isFalse, reason: 'A cached opening must wait for the complete note');
        expect(secondPlayable, isFalse);
        releaseSecond.complete();
        expect(await File(await first).exists(), isTrue);
        expect(await File(await second).exists(), isTrue);
        expect(renderedText, ['First paragraph.', 'Second paragraph.']);
        await cache.renderOrGet('Second paragraph.', speed: .75);
        expect(renderedText.length, 2, reason: 'Playback never adds a generation request');
      });
      test('failed save preparation releases playback with a missing recording error', () async {
        var attempts = 0;
        cache = TagNoteAudioCache.forTesting(
          directory: () async => root,
          key: (text, speed) async => text,
          render: (_, _) async { attempts++; throw StateError('test render failure'); },
        );
        cache.scheduleNoteText('Unavailable.', entryKey: 'failed');
        await expectLater(cache.renderOrGet('Unavailable.', speed: 1),
            throwsA(isA<SavedAudioUnavailable>()));
        expect(attempts, 1);
      });
      test('a superseding save cancels old queued chunks and prepares the new note', () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final texts = <String>[];
        cache = TagNoteAudioCache.forTesting(
          directory: () async => root,
          key: (text, speed) async => text,
          render: (text, speed) async {
            texts.add(text);
            if (text == 'Old opening.') { started.complete(); await release.future; }
            return wav(File('${root.path}/edit-${texts.length}.wav'));
          },
        );
        cache.scheduleNoteText('Old opening.\nOld ending.', entryKey: 'edited');
        await started.future;
        cache.scheduleNoteText('New note.', entryKey: 'edited');
        final playback = cache.renderOrGet('New note.', speed: 1);
        release.complete();
        expect(await File(await playback).exists(), isTrue);
        expect(texts, ['Old opening.', 'New note.']);
        await expectLater(cache.renderOrGet('Old ending.', speed: 1),
            throwsA(isA<SavedAudioUnavailable>()));
      });
      test('playback misses never invoke the speech renderer', () async {
        await expectLater(
          cache.renderOrGet('Note.', speed: 1),
          throwsA(isA<SavedAudioUnavailable>()),
        );
        expect(renders, 0);
      });
      test(
        'saved note replays and changes speed without new synthesis',
        () async {
          final saved = await cache.renderOrGet(
            'Note.',
            speed: 1,
            prepareOnSave: true,
          );
          for (final speed in [.75, 1.0, 1.5, 1.2]) {
            expect(await cache.renderOrGet('Note.', speed: speed), saved);
          }
          expect(renders, 1);
          expect(speeds, [1]);
        },
      );
      test(
        'edited note never reuses previous text or generates at play',
        () async {
          final old = await cache.renderOrGet(
            'Original.',
            speed: 1,
            prepareOnSave: true,
          );
          await expectLater(
            cache.renderOrGet('Edited.', speed: 1),
            throwsA(isA<SavedAudioUnavailable>()),
          );
          expect(renders, 1);
          final edited = await cache.renderOrGet(
            'Edited.',
            speed: 1,
            prepareOnSave: true,
          );
          expect(edited, isNot(old));
          expect(await cache.renderOrGet('Edited.', speed: 1.5), edited);
          expect(renders, 2);
        },
      );
      test(
        'a deleted or incomplete cache file never starts generation',
        () async {
          final path = await cache.renderOrGet(
            'Note.',
            speed: 1,
            prepareOnSave: true,
          );
          await File(path).writeAsString('partial');
          await expectLater(
            cache.renderOrGet('Note.', speed: 1),
            throwsA(isA<SavedAudioUnavailable>()),
          );
          expect(renders, 1);
        },
      );
      test('a stale queued save is cancelled before rendering', () async {
        await expectLater(
          cache.renderOrGet(
            'Old.',
            speed: 1,
            prepareOnSave: true,
            stillCurrent: () => false,
          ),
          throwsA(isA<SavedAudioUnavailable>()),
        );
        expect(renders, 0);
      });
      test('save preparation bounds individual synthesis jobs', () async {
        await expectLater(
          cache.renderOrGet('a' * 321, speed: 1, prepareOnSave: true),
          throwsA(isA<SavedAudioUnavailable>()),
        );
        expect(renders, 0);
      });
      test('full-book synthesis is unavailable', () {
        expect(LocalNarrationPolicy.canGenerateBooks, false);
      });
    });
  }
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    test('${platform.name} retains desktop generation', () async {
      debugDefaultTargetPlatformOverride = platform;
      expect(LocalNarrationPolicy.canGenerateBooks, true);
      await cache.renderOrGet('Desktop.', speed: 1.2);
      expect(renders, 1);
      expect(speeds, [1.2]);
    });
  }
  test(
    'long unpunctuated notes use bounded clips without losing text',
    () async {
      final text = 'a' * 700;
      final items =
          await TagPlaybackPlanner(
            bookNames: const {},
            resolveBlockId: (_, _, _) async => null,
          ).plan([
            HashTagEntry(
              id: 1,
              bookNumber: 0,
              chapter: 0,
              verse: 0,
              verseEnd: 0,
              verseRef: 'note:1',
              verseText: '',
              createdAt: 1,
              sortOrder: 1,
              noteText: text,
            ),
          ]);
      final clips = items.single.noteClips;
      expect(clips.map((c) => c.body).join(), text);
      expect(clips.every((c) => c.body.length <= 320), true);
    },
  );
}
