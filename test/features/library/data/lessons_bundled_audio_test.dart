import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/lessons_bundled_audio.dart';
import 'package:studybible2/features/library/data/lessons_reading_edition.dart';

class TestAssets extends CachingAssetBundle {
  TestAssets(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(files[key]!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late TestAssets assets;
  late String audioAsset;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lof-audio-delivery-');
    await File(
      '${root.path}/bundled-current.json',
    ).writeAsString(jsonEncode({'wor': 'keep-wor'}));
    final values = {
      'audio-manifest.json': Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'source_sha256': LessonsReadingEdition.sourceHash,
            'tracks': [
              {'file': 'one.mp3'},
            ],
          }),
        ),
      ),
      'one.mp3': Uint8List.fromList([1, 2, 3, 4]),
    };
    final data = <String, Uint8List>{};
    final members = <Map<String, dynamic>>[];
    for (final e in values.entries) {
      final hash = sha256.convert(e.value).toString();
      final asset = 'assets/bundled_library/files/$hash';
      data[asset] = e.value;
      members.add({
        'name': e.key,
        'asset': asset,
        'sha256': hash,
        'bytes': e.value.length,
      });
      if (e.key == 'one.mp3') audioAsset = asset;
    }
    data['assets/bundled_library/audio.json'] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'packages': [
            {
              'id': 'lof',
              'requires_source_sha256': LessonsReadingEdition.sourceHash,
              'sha256': members.first['sha256'],
              'files': members,
            },
          ],
        }),
      ),
    );
    assets = TestAssets(data);
  });
  tearDown(() => root.delete(recursive: true));
  test(
    'unrelated editions never install or select the prepared recording',
    () async {
      await LessonsBundledAudio.ensure(root, 'another-source', assets: assets);
      expect(
        jsonDecode(
          await File('${root.path}/bundled-current.json').readAsString(),
        ),
        {'wor': 'keep-wor'},
      );
    },
  );
  test(
    'corrupt assets retain the current selection and successful retry selects verified files',
    () async {
      final original = assets.files[audioAsset]!;
      assets.files[audioAsset] = Uint8List.fromList([9, 9, 9, 9]);
      await expectLater(
        LessonsBundledAudio.ensure(
          root,
          LessonsReadingEdition.sourceHash,
          assets: assets,
        ),
        throwsFormatException,
      );
      expect(
        jsonDecode(
          await File('${root.path}/bundled-current.json').readAsString(),
        ),
        {'wor': 'keep-wor'},
      );
      assets.files[audioAsset] = original;
      assets.clear();
      await LessonsBundledAudio.ensure(
        root,
        LessonsReadingEdition.sourceHash,
        assets: assets,
      );
      final selected =
          jsonDecode(
                await File('${root.path}/bundled-current.json').readAsString(),
              )
              as Map;
      expect(selected['wor'], 'keep-wor');
      expect(selected['lof'], startsWith('bundled-lof-'));
      expect(
        await File('${root.path}/${selected['lof']}/one.mp3').readAsBytes(),
        original,
      );
    },
  );
}
