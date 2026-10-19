import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/bundled_audio_installer.dart';
import 'package:studybible2/features/library/data/verified_audio_download.dart';

void main() {
  late Directory root;
  late HttpServer server;
  late VerifiedAudioDownload downloader;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('audio-package-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    downloader = VerifiedAudioDownload();
  });
  tearDown(() async {
    downloader.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  });
  Map<String, dynamic> package({
    bool corrupt = false,
    bool extra = false,
    bool missingTrack = false,
  }) {
    final members = <String, List<int>>{
      'chapter.mp3': [1, 2, 3, 4],
      'audio-manifest.json': utf8.encode(
        jsonEncode({
          'title': 'Book',
          'tracks': [
            {'file': missingTrack ? 'missing.mp3' : 'chapter.mp3'},
          ],
        }),
      ),
    };
    final archive = Archive();
    for (final e in members.entries) {
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    if (extra) archive.addFile(ArchiveFile('../outside.mp3', 1, [9]));
    final bytes = ZipEncoder().encode(archive);
    server.listen((request) async {
      request.response.add(bytes);
      await request.response.close();
    });
    return {
      'id': 'book',
      'url': 'http://127.0.0.1:${server.port}/book.zip',
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'files': [
        for (final e in members.entries)
          {
            'name': e.key,
            'bytes': e.value.length,
            'sha256': sha256.convert(corrupt ? [0] : e.value).toString(),
          },
      ],
    };
  }

  test(
    'complete verified package is selected and repeated install is unchanged',
    () async {
      final spec = package();
      final installer = BundledAudioInstaller(root, downloader);
      final dir = await installer.install(spec);
      expect(await File('${dir.path}/chapter.mp3').readAsBytes(), [1, 2, 3, 4]);
      final pointer = File('${root.path}/bundled-current.json');
      final before = await pointer.readAsString();
      expect(jsonDecode(before)['book'], endsWith(spec['sha256']));
      expect((await installer.install(spec)).path, dir.path);
      expect(await pointer.readAsString(), before);
    },
  );
  test(
    'verified receipt survives a new installer without downloading',
    () async {
      final spec = package();
      final dir = await BundledAudioInstaller(root, downloader).install(spec);
      final receipt = File('${dir.path}/.verified.json');
      expect(await receipt.exists(), isTrue);
      await server.close(force: true);
      final restarted = BundledAudioInstaller(root, downloader);
      expect(await restarted.isReady(spec), isTrue);
      expect((await restarted.install(spec)).path, dir.path);
    },
  );
  test(
    'old complete files and interrupted receipt recover quietly offline',
    () async {
      final spec = package();
      final dir = await BundledAudioInstaller(root, downloader).install(spec);
      final track = File('${dir.path}/chapter.mp3');
      final before = await track.stat();
      await File('${dir.path}/.verified.json').delete();
      await File(
        '${dir.path}/.verified.json.new',
      ).writeAsString('{interrupted');
      await server.close(force: true);
      final restarted = BundledAudioInstaller(root, downloader);
      expect(await restarted.verifyInstalled(spec), isTrue);
      expect(await restarted.isReady(spec), isTrue);
      expect((await track.stat()).modified, before.modified);
      expect(await track.readAsBytes(), [1, 2, 3, 4]);
      await track.writeAsBytes([4, 3, 2, 1], flush: true);
      expect(await restarted.verifyInstalled(spec), isFalse);
      expect(await restarted.isReady(spec), isFalse);
    },
  );

  test('changed or missing files invalidate the saved verification', () async {
    final spec = package();
    final installer = BundledAudioInstaller(root, downloader);
    final dir = await installer.install(spec);
    final track = File('${dir.path}/chapter.mp3');
    await track.writeAsBytes([4, 3, 2, 1], flush: true);
    await track.setLastModified(DateTime.utc(2020));
    expect(await installer.isReady(spec), isFalse);
    await installer.install(spec);
    expect(await track.readAsBytes(), [1, 2, 3, 4]);
    expect(await installer.isReady(spec), isTrue);
    await track.delete();
    expect(await installer.isReady(spec), isFalse);
  });
  test(
    'missing or corrupt receipt revalidates existing files without download',
    () async {
      final spec = package();
      final installer = BundledAudioInstaller(root, downloader);
      final dir = await installer.install(spec);
      final receipt = File('${dir.path}/.verified.json');
      await server.close(force: true);
      for (final broken in ['', '{bad json']) {
        await receipt.writeAsString(broken);
        expect(await installer.isReady(spec), isFalse);
        await installer.install(spec);
        expect(await installer.isReady(spec), isTrue);
      }
    },
  );
  test(
    'manifest changes and a lost selection cannot use stale readiness',
    () async {
      final spec = package();
      final installer = BundledAudioInstaller(root, downloader);
      await installer.install(spec);
      final changed = jsonDecode(jsonEncode(spec)) as Map<String, dynamic>;
      (changed['files'] as List).first['sha256'] = '0' * 64;
      expect(await installer.isReady(changed), isFalse);
      await File('${root.path}/bundled-current.json').delete();
      expect(await installer.isReady(spec), isFalse);
      await installer.install(spec);
      expect(await installer.isReady(spec), isTrue);
    },
  );
  for (final kind in ['corrupt', 'extra', 'missing']) {
    test('$kind package never replaces current selection', () async {
      final pointer = File('${root.path}/bundled-current.json');
      await pointer.writeAsString('{"book":"existing"}');
      final spec = package(
        corrupt: kind == 'corrupt',
        extra: kind == 'extra',
        missingTrack: kind == 'missing',
      );
      await expectLater(
        BundledAudioInstaller(root, downloader).install(spec),
        throwsFormatException,
      );
      expect(await pointer.readAsString(), '{"book":"existing"}');
      expect(await File('${root.parent.path}/outside.mp3').exists(), isFalse);
    });
  }
}
