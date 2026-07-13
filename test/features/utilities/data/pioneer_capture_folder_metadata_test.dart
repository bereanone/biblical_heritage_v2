import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/data/pioneer_capture_folder_metadata.dart';

void main() {
  const folder = '/temporary/Books/CIS';

  test('parses schema 2 identity, fingerprint, and publication fields', () {
    final metadata = PioneerCaptureFolderMetadata.fromManifestString(
      '''
{
  "schemaVersion": 2,
  "workId": "CIS",
  "packageId": "captureclipper:CIS",
  "createdAt": "2026-07-01T00:00:00Z",
  "updatedAt": "2026-07-10T00:00:00Z",
  "contentHash": "sha256-current",
  "captureApp": "CaptureClipper",
  "captureMode": "book",
  "title": "The Cross and Its Shadow",
  "author": "Stephen N. Haskell",
  "shortCode": "CIS",
  "sourceUrl": "https://example.invalid/cis",
  "fromRef": "CIS 1.1",
  "toRef": "CIS 2.2",
  "coverImage": "images/cover.png",
  "imageCount": 1,
  "htmlFile": "capture.html",
  "futureField": {"isIgnored": true}
}
''',
      folderPath: folder,
      availableFiles: const <String>[],
    );

    expect(metadata.schemaVersion, 2);
    expect(metadata.workId, 'CIS');
    expect(metadata.packageId, 'captureclipper:CIS');
    expect(metadata.contentHash, 'sha256-current');
    expect(metadata.htmlFile, 'capture.html');
    expect(metadata.imageCount, 1);
    expect(metadata.captureApp, 'CaptureClipper');
    expect(metadata.captureMode, 'book');
    expect(metadata.primaryContributorName, 'Stephen N. Haskell');
    expect(metadata.manifestError, isNull);
  });

  test('schema 1 remains supported', () {
    final metadata = PioneerCaptureFolderMetadata.fromManifestString(
      '{"schemaVersion":1,"workId":"CIS","title":"CIS"}',
      folderPath: folder,
    );
    expect(metadata.schemaVersion, 1);
    expect(metadata.workId, 'CIS');
    expect(metadata.manifestError, isNull);
  });

  test('unknown future schema fails visibly', () {
    final metadata = PioneerCaptureFolderMetadata.fromManifestString(
      '{"schemaVersion":3,"workId":"CIS","htmlFile":"capture.html"}',
      folderPath: folder,
    );
    expect(metadata.manifestError, contains('Unsupported manifest'));
  });

  test('schema 2 missing required fields fails visibly', () {
    final metadata = PioneerCaptureFolderMetadata.fromManifestString(
      '{"schemaVersion":2,"workId":"CIS"}',
      folderPath: folder,
    );
    expect(metadata.manifestError, contains('missing required field'));
  });

  test(
    'cover cache filename is bounded and independent of metadata prose',
    () async {
      final root = await Directory.systemTemp.createTemp('bounded-cover-');
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/source 😀.png')
        ..writeAsBytesSync(const <int>[1, 2, 3]);
      final hostileId =
          'library_item_research_pioneer_${'author/\\\n😀'.padRight(10000, 'x')}_WOR';

      final first = await cachePioneerCaptureCoverPath(
        coverPath: source.path,
        itemId: hostileId,
        rootPath: root.path,
      );
      final second = await cachePioneerCaptureCoverPath(
        coverPath: source.path,
        itemId: hostileId,
        rootPath: root.path,
      );

      expect(first, second);
      expect(File(first!).existsSync(), isTrue);
      expect(first.split(Platform.pathSeparator).last.length, lessThan(80));
      expect(first, endsWith('_wor.png'));
      expect(first, isNot(contains('author')));
    },
  );
}
