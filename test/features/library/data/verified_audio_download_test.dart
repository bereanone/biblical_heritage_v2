import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/verified_audio_download.dart';

void main() {
  late Directory dir;
  late HttpServer server;
  late VerifiedAudioDownload downloader;
  final data = List<int>.generate(1000, (i) => i % 251);
  final digest = sha256.convert(data).toString();
  late Uri url;
  late File target;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('audio-download-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    downloader = VerifiedAudioDownload();
    url = Uri.parse('http://127.0.0.1:${server.port}/recording');
    target = File('${dir.path}/chapter.mp3');
  });
  tearDown(() async {
    downloader.close();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });
  Future<void> fetch() => downloader.fetch(
    url: url,
    destination: target,
    bytes: data.length,
    digest: digest,
  );

  test('downloads, verifies and skips a valid existing recording', () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.contentLength = data.length;
      request.response.add(data);
      await request.response.close();
    });
    await fetch();
    expect(await target.readAsBytes(), data);
    await fetch();
    expect(requests, 1);
  });
  test('resumes a partial recording with a validated range', () async {
    await File(
      '${target.path}.$digest.part',
    ).writeAsBytes(data.take(300).toList());
    server.listen((request) async {
      expect(request.headers.value('range'), 'bytes=300-');
      request.response.statusCode = 206;
      request.response.headers.set('content-range', 'bytes 300-999/1000');
      request.response.contentLength = 700;
      request.response.add(data.skip(300).toList());
      await request.response.close();
    });
    await fetch();
    expect(await target.readAsBytes(), data);
  });
  test('server ignoring range restarts instead of appending', () async {
    await File(
      '${target.path}.$digest.part',
    ).writeAsBytes(data.take(300).toList());
    server.listen((request) async {
      request.response.contentLength = data.length;
      request.response.add(data);
      await request.response.close();
    });
    await fetch();
    expect(await target.readAsBytes(), data);
  });
  test('bad range preserves existing file and partial', () async {
    await target.writeAsString('old playable recording');
    final partial = File('${target.path}.$digest.part');
    await partial.writeAsBytes(data.take(300).toList());
    server.listen((request) async {
      request.response.statusCode = 206;
      request.response.headers.set('content-range', 'bytes 0-699/1000');
      request.response.add(data.take(700).toList());
      await request.response.close();
    });
    await expectLater(fetch(), throwsFormatException);
    expect(await target.readAsString(), 'old playable recording');
    expect(await partial.length(), 300);
  });
  test('corrupt bytes never replace a playable recording', () async {
    await target.writeAsString('old playable recording');
    server.listen((request) async {
      request.response.contentLength = 1000;
      request.response.add(List<int>.filled(1000, 0));
      await request.response.close();
    });
    await expectLater(fetch(), throwsFormatException);
    expect(await target.readAsString(), 'old playable recording');
    expect(await File('${target.path}.$digest.part').exists(), isFalse);
  });
  test('interrupted body keeps its bytes for a later retry', () async {
    var calls = 0;
    server.listen((request) async {
      calls++;
      if (calls == 1) {
        // Unknown-length short response models a connection ending early.
        request.response.add(data.take(400).toList());
      } else {
        expect(request.headers.value('range'), 'bytes=400-');
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 400-999/1000');
        request.response.add(data.skip(400).toList());
      }
      await request.response.close();
    });
    await expectLater(fetch(), throwsA(isA<HttpException>()));
    expect(await target.exists(), isFalse);
    await fetch();
    expect(await target.readAsBytes(), data);
  });
}
