import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';

void main() {
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
}
