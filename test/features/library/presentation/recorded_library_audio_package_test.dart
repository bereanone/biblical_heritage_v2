import 'dart:convert';
import 'dart:io';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';

void main() {
  test('margin-note toggle skips every note cue and lands on body text', () {
    const cues = [
      RecordedLibraryAudioCue(Duration.zero, 'Paragraph one.'),
      RecordedLibraryAudioCue(
        Duration(seconds: 5),
        'First margin note.',
        role: 'margin_note',
      ),
      RecordedLibraryAudioCue(
        Duration(seconds: 7),
        'Second margin note.',
        role: 'margin_note',
      ),
      RecordedLibraryAudioCue(Duration(seconds: 9), 'Paragraph two.'),
    ];
    expect(recordedNextPlayableCueIndex(cues, 0, includeMarginNotes: true), 1);
    expect(recordedNextPlayableCueIndex(cues, 0, includeMarginNotes: false), 3);
  });

  test(
    'margin-note cues retain their paragraph owner without matching body words',
    () {
      const items = [
        LibrarySpeechItem(
          cursor: '12',
          nextCursor: '13',
          text: 'The owning paragraph.',
        ),
        LibrarySpeechItem(
          cursor: '13',
          nextCursor: '14',
          text: 'The next paragraph.',
        ),
      ];
      const note = RecordedLibraryAudioCue(
        Duration.zero,
        'Margin notes. Deuteronomy 4:14.',
        sourceCursor: '12',
        role: 'margin_note',
      );
      expect(recordedCueItemIndex(note, items, startIndex: 1), 0);
      const missingOwner = RecordedLibraryAudioCue(
        Duration.zero,
        'Margin notes.',
        sourceCursor: '99',
        role: 'margin_note',
      );
      expect(recordedCueItemIndex(missingOwner, items), -1);
      const unrelatedBody = RecordedLibraryAudioCue(
        Duration.zero,
        'Different prose.',
        sourceCursor: '12',
      );
      expect(recordedCueItemIndex(unrelatedBody, items), -1);
    },
  );

  test(
    'only the requested book and package-owned audio are selected',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'recorded-library-test',
      );
      addTearDown(() => root.delete(recursive: true));
      final folder = await Directory('${root.path}/sc').create();
      await File('${folder.path}/chapter-02.mp3').writeAsBytes([1, 2, 3]);
      await File('${folder.path}/chapter-01.mp3').writeAsBytes([1, 2, 3]);
      await File('${folder.path}/audio-manifest.json').writeAsString(
        jsonEncode({
          'title': 'Steps to Christ',
          'tracks': [
            {'chapter': 2, 'title': 'Chapter two', 'file': 'chapter-02.mp3'},
            {'chapter': 1, 'title': 'Chapter one', 'file': 'chapter-01.mp3'},
            {
              'chapter': 3,
              'title': 'Outside package',
              'file': '../outside.mp3',
            },
            {'chapter': 4, 'title': 'Missing', 'file': 'missing.mp3'},
          ],
        }),
      );
      expect(
        await RecordedLibraryAudioPackage.findIn(root, 'Another book'),
        isNull,
      );
      final package = await RecordedLibraryAudioPackage.findIn(
        root,
        'Steps to Christ',
      );
      expect(package!.tracks.map((t) => t.chapter), [1, 2]);
      expect(
        package.tracks.every((t) => t.file.path.startsWith(folder.path)),
        isTrue,
      );
    },
  );
  test(
    'only the published managed package is selected ahead of legacy audio',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'recorded-published-test',
      );
      addTearDown(() => root.delete(recursive: true));
      for (final name in [
        'legacy',
        '.installing-sc-new',
        'bundled-sc-old',
        'bundled-sc-new',
      ]) {
        final folder = await Directory('${root.path}/$name').create();
        await File('${folder.path}/one.mp3').writeAsBytes([1]);
        await File('${folder.path}/audio-manifest.json').writeAsString(
          jsonEncode({
            'title': 'Steps to Christ',
            'tracks': [
              {'chapter': 1, 'title': name, 'file': 'one.mp3'},
            ],
          }),
        );
      }
      await File(
        '${root.path}/bundled-current.json',
      ).writeAsString(jsonEncode({'sc': 'bundled-sc-new'}));
      var package = await RecordedLibraryAudioPackage.findIn(
        root,
        'Steps to Christ',
      );
      expect(package!.tracks.single.title, 'bundled-sc-new');
      await File('${root.path}/bundled-current.json').writeAsString('{}');
      package = await RecordedLibraryAudioPackage.findIn(
        root,
        'Steps to Christ',
      );
      expect(package!.tracks.single.title, 'legacy');
    },
  );

  test('an incomplete manifest does not break book opening', () async {
    final root = await Directory.systemTemp.createTemp(
      'recorded-library-incomplete',
    );
    addTearDown(() => root.delete(recursive: true));
    final folder = await Directory('${root.path}/incomplete').create();
    await File('${folder.path}/audio-manifest.json').writeAsString('{');
    expect(
      await RecordedLibraryAudioPackage.findIn(root, 'Steps to Christ'),
      isNull,
    );
  });
  test('chapter timing and download completeness are preserved', () async {
    final root = await Directory.systemTemp.createTemp('recorded-timing-test');
    addTearDown(() => root.delete(recursive: true));
    final folder = await Directory('${root.path}/sc').create();
    await File('${folder.path}/chapter-01.mp3').writeAsBytes([1, 2, 3]);
    final manifest = File('${folder.path}/audio-manifest.json');
    final data = {
      'title': 'Steps to Christ',
      'total_chapters': 2,
      'tracks': [
        {
          'chapter': 1,
          'title': 'Chapter one',
          'file': 'chapter-01.mp3',
          'cues': [
            {
              'start_ms': 3950,
              'text': 'Nature and revelation alike testify of God’s love.',
              'phrases': [
                {
                  'start_ms': 2400,
                  'text': 'Our Father in heaven is the source of life.',
                },
              ],
            },
          ],
        },
      ],
    };
    await manifest.writeAsString(jsonEncode(data));
    var package = (await RecordedLibraryAudioPackage.findIn(
      root,
      'Steps to Christ',
    ))!;
    expect(package.isComplete, isFalse);
    expect(package.tracks.single.cues.single.start.inMilliseconds, 3950);
    expect(
      package.tracks.single.cues.single.phrases.single.start.inMilliseconds,
      2400,
    );
    expect(
      package.tracks.single.cues.single.text,
      'Nature and revelation alike testify of God’s love.',
    );
    await File('${folder.path}/chapter-02.mp3').writeAsBytes([1]);
    (data['tracks'] as List).add({
      'chapter': 2,
      'title': 'Chapter two',
      'file': 'chapter-02.mp3',
    });
    await manifest.writeAsString(jsonEncode(data));
    package = (await RecordedLibraryAudioPackage.findIn(
      root,
      'Steps to Christ',
    ))!;
    expect(package.isComplete, isTrue);
  });

  test('margin-note line seek resolves each displayed paragraph start', () {
    const text =
        'Margin notes. Isaiah 42:6, 7.\n'
        'For precept must be upon precept; line upon line.\nIsaiah 28:10.';

    expect(
      recordedMarginNoteLineStartFraction(text, 0),
      closeTo(14 / text.length, .01),
    );

    expect(
      recordedMarginNoteLineStartFraction(text, 1),

      closeTo(text.indexOf('For precept') / text.length, .01),
    );

    expect(
      recordedMarginNoteLineStartFraction(text, 2),

      closeTo(text.indexOf('Isaiah 28') / text.length, .01),
    );
  });
}
