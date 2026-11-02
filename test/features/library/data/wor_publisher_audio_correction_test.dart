import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/wor_publisher_audio_correction.dart';
import 'package:studybible2/features/library/data/optional_book_companions.dart';

class _Assets extends CachingAssetBundle {
  _Assets(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(files[key]!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Assets assets;
  const source = OptionalBookCompanions.worSingleReaderSource;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('wor-publisher-update-');
    final old = Directory('${root.path}/bundled-old');
    await old.create();
    await File('${old.path}/audio-manifest.json').writeAsString(
      jsonEncode({
        'source_sha256': source,
        'tracks': [
          {
            'cues': [
              {
                'source_refcode': 'WOR 102.14',
                'text': 'raised up fro the dead',
              },
            ],
          },
        ],
      }),
    );
    await File(
      '${root.path}/bundled-current.json',
    ).writeAsString(jsonEncode({'wor': 'bundled-old', 'sc': 'keep-sc'}));
    final manifest = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'source_sha256': source,
          'tracks': [
            {
              'file': 'chapter.mp3',
              'cues': [
                {
                  'source_refcode': 'WOR 102.14',
                  'text': 'raised up from the dead',
                },
              ],
            },
          ],
        }),
      ),
    );
    final audio = Uint8List.fromList([1, 2, 3, 4]);
    final files = <Map<String, dynamic>>[];
    final data = <String, Uint8List>{};
    for (final e in {
      'audio-manifest.json': manifest,
      'chapter.mp3': audio,
    }.entries) {
      final hash = sha256.convert(e.value).toString();
      final asset = 'assets/bundled_library/files/$hash';
      data[asset] = e.value;
      files.add({
        'name': e.key,
        'asset': asset,
        'sha256': hash,
        'bytes': e.value.length,
      });
    }
    data['assets/bundled_library/audio.json'] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'packages': [
            {
              'id': 'wor',
              'publisher_correction': 'wor-102-14-from-v1',
              'sha256': sha256.convert(manifest).toString(),
              'files': files,
            },
          ],
        }),
      ),
    );
    assets = _Assets(data);
  });
  tearDown(() => root.delete(recursive: true));
  test(
    'updates selected stale WOR from verified assets, retains old package and other selection',
    () async {
      await Future.wait([
        WorPublisherAudioCorrection.ensure(root, source, assets: assets),
        WorPublisherAudioCorrection.ensure(root, source, assets: assets),
      ]);
      final pointer =
          jsonDecode(
                await File('${root.path}/bundled-current.json').readAsString(),
              )
              as Map;
      expect(pointer['wor'], isNot('bundled-old'));
      expect(pointer['sc'], 'keep-sc');
      expect(
        await File('${root.path}/bundled-old/audio-manifest.json').exists(),
        isTrue,
      );
      final repaired = await File(
        '${root.path}/${pointer['wor']}/audio-manifest.json',
      ).readAsString();
      expect(repaired, contains('up from the dead'));
      await WorPublisherAudioCorrection.ensure(
        root,
        source,
        assets: _Assets({}),
      );
    },
  );
  test('corrupt replacement leaves existing selection intact', () async {
    final key = assets.files.keys.firstWhere(
      (k) => k.startsWith('assets/bundled_library/files/'),
    );
    assets.files[key] = Uint8List.fromList([9]);
    await expectLater(
      WorPublisherAudioCorrection.ensure(root, source, assets: assets),
      throwsFormatException,
    );
    final p =
        jsonDecode(
              await File('${root.path}/bundled-current.json').readAsString(),
            )
            as Map;
    expect(p['wor'], 'bundled-old');
  });
  test('unrecognized source never loads correction assets', () async {
    await WorPublisherAudioCorrection.ensure(
      root,
      'another-source',
      assets: _Assets({}),
    );
    final p =
        jsonDecode(
              await File('${root.path}/bundled-current.json').readAsString(),
            )
            as Map;
    expect(p['wor'], 'bundled-old');
  });
}
