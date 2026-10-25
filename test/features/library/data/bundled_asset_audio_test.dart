import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/bundled_audio_installer.dart';
import 'package:studybible2/features/library/data/bundled_audio_setup.dart';
import 'package:studybible2/features/library/data/verified_audio_download.dart';

class TestAssets extends CachingAssetBundle {
  TestAssets(this.files);
  final Map<String, List<int>> files;
  final requested = <String>[];
  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    return ByteData.sublistView(Uint8List.fromList(files[key]!));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late VerifiedAudioDownload download;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('brhc-asset-audio-');
    download = VerifiedAudioDownload();
  });
  tearDown(() async {
    download.close();
    await root.delete(recursive: true);
  });
  (Map<String, dynamic>, TestAssets) fixture({
    bool corrupt = false,
    bool missingTrack = false,
  }) {
    final files = {
      'track-001.mp3': <int>[1, 2, 3, 4],
      'audio-manifest.json': utf8.encode(
        jsonEncode({
          'title': 'BRHC',
          'tracks': [
            {'file': missingTrack ? 'absent.mp3' : 'track-001.mp3'},
          ],
        }),
      ),
    };
    final assets = <String, List<int>>{};
    final specs = <Map<String, dynamic>>[];
    for (final entry in files.entries) {
      final hash = sha256.convert(entry.value).toString();
      final asset = 'assets/bundled_library/files/$hash';
      assets[asset] = corrupt && entry.key.endsWith('.mp3')
          ? [8, 9]
          : entry.value;
      specs.add({
        'name': entry.key,
        'bytes': entry.value.length,
        'sha256': hash,
        'asset': asset,
      });
    }
    return (
      {
        'id': 'brhc1914',
        'title': 'BRHC',
        'delivery': 'assets',
        'sha256': 'a' * 64,
        'bytes': 100,
        'files': specs,
      },
      TestAssets(assets),
    );
  }

  test(
    'packaged tracks install offline and verified reinstall does not reload assets',
    () async {
      final (spec, assets) = fixture();
      final installer = BundledAudioInstaller(root, download);
      final result = await installer.installAssets(spec, assets);
      expect(await File('${result.path}/track-001.mp3').readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      expect(await installer.isReady(spec), true);
      expect(assets.requested.length, 2);
      await installer.installAssets(spec, assets);
      expect(assets.requested.length, 2);
    },
  );
  for (final missing in [false, true]) {
    test(
      'invalid asset package retains previous selected audio ${missing ? "missing track" : "hash mismatch"}',
      () async {
        await File(
          '${root.path}/bundled-current.json',
        ).writeAsString('{"other":"preserved"}');
        final (spec, assets) = fixture(
          corrupt: !missing,
          missingTrack: missing,
        );
        await expectLater(
          BundledAudioInstaller(root, download).installAssets(spec, assets),
          throwsFormatException,
        );
        expect(
          await File('${root.path}/bundled-current.json').readAsString(),
          '{"other":"preserved"}',
        );
      },
    );
  }
  test('seven required books include the offline BRHC package', () async {
    final seen = <String>[];
    final setup = BundledAudioSetup.forTesting(
      loadManifest: () async => {
        'core_package_count': 7,
        'packages': [
          for (var i = 0; i < 6; i++)
            {
              'id': 'book$i',
              'title': 'Book $i',
              'sha256': 'hash$i',
              'url': 'https://example.invalid/$i',
            },
          {
            'id': 'brhc1914',
            'title': 'BRHC',
            'sha256': 'brhc-hash',
            'delivery': 'assets',
          },
        ],
      },
      install: (spec) async {
        seen.add(spec['id'] as String);
      },
    );
    addTearDown(setup.dispose);
    await setup.ensure();
    expect(setup.error, isNull);
    expect(setup.complete, true);
    expect(seen.length, 7);
    expect(seen.last, 'brhc1914');
  });
}
