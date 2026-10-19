import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Downloads a pinned recording to a private staging file. Only a complete,
/// verified file replaces the destination; an interrupted transfer can resume.
class VerifiedAudioDownload {
  VerifiedAudioDownload({HttpClient? client})
    : _client = client ?? HttpClient();

  final HttpClient _client;

  void close() => _client.close(force: true);

  Future<void> fetch({
    required Uri url,
    required File destination,
    required int bytes,
    required String digest,
    void Function(int received, int total)? onProgress,
  }) async {
    if (bytes <= 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid recording integrity metadata');
    }
    if (url.scheme != 'https' &&
        !(url.scheme == 'http' &&
            (url.host == '127.0.0.1' || url.host == 'localhost'))) {
      throw const FormatException('Recording download requires HTTPS');
    }
    if (await _matches(destination, bytes, digest)) {
      onProgress?.call(bytes, bytes);
      return;
    }
    await destination.parent.create(recursive: true);
    // A changed recording gets a distinct partial file; never append old bytes
    // to a new revision. Existing playable recordings survive all failures.
    final partial = File('${destination.path}.$digest.part');
    if (await partial.exists() && await partial.length() > bytes) {
      await partial.delete();
    }
    if (await _matches(partial, bytes, digest)) {
      await partial.rename(destination.path);
      onProgress?.call(bytes, bytes);
      return;
    }
    if (await partial.exists() && await partial.length() == bytes) {
      await partial.delete();
    }
    var offset = await partial.exists() ? await partial.length() : 0;
    final request = await _client
        .getUrl(url)
        .timeout(const Duration(seconds: 30));
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (offset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    }
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw HttpException('Recording download failed (${response.statusCode})');
    }
    if (response.statusCode == HttpStatus.partialContent) {
      final range = response.headers.value(HttpHeaders.contentRangeHeader);
      final expected = 'bytes $offset-${bytes - 1}/$bytes';
      if (range != expected) {
        await response.drain<void>();
        throw const FormatException('Recording resume range did not match');
      }
    } else {
      // A server can ignore Range. Restart instead of appending a full file.
      offset = 0;
    }
    if (response.contentLength >= 0 &&
        response.contentLength != bytes - offset) {
      await response.drain<void>();
      throw const FormatException('Recording size did not match');
    }
    final output = await partial.open(
      mode: offset == 0 ? FileMode.write : FileMode.append,
    );
    var received = offset;
    try {
      onProgress?.call(received, bytes);
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        if (received + chunk.length > bytes) {
          throw const FormatException('Recording exceeded expected size');
        }
        await output.writeFrom(chunk);
        received += chunk.length;
        onProgress?.call(received, bytes);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (received != bytes) {
      throw const HttpException('Recording download was interrupted');
    }
    if (!await _matches(partial, bytes, digest)) {
      await partial.delete();
      throw const FormatException('Recording failed integrity verification');
    }
    await partial.rename(destination.path);
  }

  static Future<bool> _matches(File file, int bytes, String digest) async =>
      await file.exists() &&
      await file.length() == bytes &&
      (await sha256.bind(file.openRead()).first).toString() == digest;
}
