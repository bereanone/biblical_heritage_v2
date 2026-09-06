import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/features/utilities/data/pioneer_book_package_import_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_folder_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_html_capture_folder_scanner.dart';

Future<void> _installPathProviderMocks({
  required Directory supportDir,
  required Directory documentsDir,
}) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getApplicationSupportDirectory':
            return supportDir.path;
          case 'getApplicationDocumentsDirectory':
            return documentsDir.path;
        }
        return supportDir.path;
      });
}

Uint8List _zipBytes(Map<String, String> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<File> _writePackage(
  Directory sourceDir,
  String fileName,
  Uint8List bytes,
) async {
  final file = File(p.join(sourceDir.path, fileName));
  await file.writeAsBytes(bytes);
  return file;
}

const String _captureHtml = '''
<!doctype html>
<html>
  <head>
    <title>The Story of the Seer of Patmos</title>
    <meta name="author" content="Stephen Nelson Haskell" />
  </head>
  <body>
    <h1>The Story of the Seer of Patmos</h1>
    <p>Prophecy is often considered dark and mysterious.</p>
    <h2>Chapter 1</h2>
    <p>The Revelation opens with a blessing on the reader.</p>
  </body>
</html>
''';

const String _manifestJsonWithShortCode = '''
{
  "schemaVersion": 2,
  "workId": "SSP",
  "packageId": "captureclipper:SSP",
  "contentHash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "createdAt": "2026-07-01T00:00:00.000Z",
  "updatedAt": "2026-07-10T00:00:00.000Z",
  "captureApp": "CaptureClipper",
  "title": "The Story of the Seer of Patmos",
  "author": "Stephen Nelson Haskell",
  "shortCode": "SSP",
  "htmlFile": "capture.html"
}
''';

// Matches a real-world legacy CaptureClipper manifest: no workId,
// packageId, contentHash, or author fields, which predate schema 2.
const String _legacySchema1ManifestJson = '''
{
  "schemaVersion": 1,
  "createdAt": "2026-07-05T16:13:30.739907Z",
  "captureApp": "CaptureClipper",
  "captureMode": "clipboard-html",
  "title": "CWCP",
  "shortCode": "CWCP",
  "fromRef": "19",
  "toRef": "23",
  "coverImage": "images/image_0001.png",
  "imageCount": 1,
  "htmlFile": "capture.html"
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  late Directory documentsDir;
  late Directory sourceDir;
  late PioneerBookPackageImportService service;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('package_support_');
    documentsDir = await Directory.systemTemp.createTemp('package_documents_');
    sourceDir = await Directory.systemTemp.createTemp('package_cloud_source_');
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    service = PioneerBookPackageImportService();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    for (final dir in [supportDir, documentsDir, sourceDir]) {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    }
  });

  group('studybookBookCodeFromPackageName', () {
    test('strips trailing capture-date suffixes', () {
      expect(
        studybookBookCodeFromPackageName('/cloud/CSCP07-5-2026.studybook'),
        'CSCP',
      );
      expect(
        studybookBookCodeFromPackageName('/cloud/SDP07-5-2026.studybook'),
        'SDP',
      );
    });

    test('keeps year-bearing book codes without a date suffix', () {
      expect(
        studybookBookCodeFromPackageName('/cloud/DAR1897.studybook'),
        'DAR1897',
      );
      expect(
        studybookBookCodeFromPackageName('/cloud/DAR1897-07-5-2026.zip'),
        'DAR1897',
      );
    });

    test('strips a redundant .zip suffix appended after .studybook', () {
      // Some export/backup tools produce a double extension like this.
      expect(
        studybookBookCodeFromPackageName('/cloud/CWCP07-05-2026.studybook.zip'),
        'CWCP',
      );
    });
  });

  test(
    'imports a valid .studybook package, preserves nested folders, and leaves '
    'the source package untouched',
    () async {
      final bytes = _zipBytes({
        'manifest.json': _manifestJsonWithShortCode,
        'capture.html': _captureHtml,
        'Graphics/cover.png': 'png-bytes',
        'images/image_0001.png': 'png-bytes',
        'css/style.css': 'body {}',
      });
      final package = await _writePackage(
        sourceDir,
        'SSP07-5-2026.studybook',
        bytes,
      );
      final sourceBytesBefore = await package.readAsBytes();
      final sourceModifiedBefore = (await package.stat()).modified;

      final result = await service.importPackage(package.path);

      final managedRoot = p.join(
        supportDir.path,
        PioneerCapturedHtmlImportFolderService.managedImportFolderName,
      );
      expect(result.managedRootPath, managedRoot);
      expect(result.bookCode, 'SSP');
      expect(result.destinationFolderPath, p.join(managedRoot, 'SSP'));
      expect(result.htmlFileCount, 1);
      expect(result.extractedFilePaths, hasLength(5));
      for (final relative in const <String>[
        'manifest.json',
        'capture.html',
        'Graphics/cover.png',
        'images/image_0001.png',
        'css/style.css',
      ]) {
        expect(
          File(p.join(result.destinationFolderPath, relative)).existsSync(),
          isTrue,
          reason: '$relative should be unpacked',
        );
      }

      // Configured CaptureClipper root becomes the ImportedCaptureClipper
      // parent folder, not the book folder itself.
      expect(
        await LocalSettingsStore.instance.loadPioneerCapturedHtmlFolderPath(),
        managedRoot,
      );
      expect(p.basename(managedRoot), 'ImportedCaptureClipper');

      // The source package is a read-only input.
      expect(package.existsSync(), isTrue);
      expect(await package.readAsBytes(), sourceBytesBefore);
      expect((await package.stat()).modified, sourceModifiedBefore);
    },
  );

  test('imports a flat-root .studybook package', () async {
    final bytes = _zipBytes({
      'manifest.json': _manifestJsonWithShortCode,
      'capture.html': _captureHtml,
      'images/pic.png': 'png-bytes',
    });
    final package = await _writePackage(sourceDir, 'SSP.studybook', bytes);

    final result = await service.importPackage(package.path);

    expect(result.bookCode, 'SSP');
    expect(result.destinationFolderPath, p.join(result.managedRootPath, 'SSP'));
    expect(
      File(p.join(result.destinationFolderPath, 'capture.html')).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(result.destinationFolderPath, 'images', 'pic.png'),
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'imports a package with a redundant .studybook.zip double extension',
    () async {
      // Some export/backup tools append a redundant .zip suffix on top of
      // .studybook; the importer must still accept and correctly name it.
      final bytes = _zipBytes({
        'manifest.json': _manifestJsonWithShortCode,
        'capture.html': _captureHtml,
      });
      final package = await _writePackage(
        sourceDir,
        'CWCP07-05-2026.studybook.zip',
        bytes,
      );

      final result = await service.importPackage(package.path);

      expect(result.bookCode, 'SSP');
      expect(
        result.destinationFolderPath,
        p.join(result.managedRootPath, 'SSP'),
      );
    },
  );

  test('imports a package wrapped in a single top-level folder '
      '(e.g. macOS Finder "Compress")', () async {
    final bytes = _zipBytes({
      'CWCP07-05-2026/manifest.json': _manifestJsonWithShortCode,
      'CWCP07-05-2026/capture.html': _captureHtml,
      'CWCP07-05-2026/images/image_0001.png': 'png-bytes',
    });
    final package = await _writePackage(
      sourceDir,
      'CWCP07-05-2026.studybook',
      bytes,
    );

    final result = await service.importPackage(package.path);

    expect(result.bookCode, 'SSP');
    expect(result.destinationFolderPath, p.join(result.managedRootPath, 'SSP'));
    expect(
      File(p.join(result.destinationFolderPath, 'capture.html')).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(result.destinationFolderPath, 'images', 'image_0001.png'),
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'imports a legacy schema-1 package by synthesizing its identity',
    () async {
      final bytes = _zipBytes({
        'manifest.json': _legacySchema1ManifestJson,
        'capture.html': _captureHtml,
        'images/image_0001.png': 'png-bytes',
      });
      final package = await _writePackage(
        sourceDir,
        'CWCP07-05-2026.studybook',
        bytes,
      );

      final result = await service.importPackage(package.path);

      expect(result.bookCode, 'CWCP');
      expect(result.workId, 'CWCP');
      expect(result.packageId, isNotEmpty);
      expect(
        result.destinationFolderPath,
        p.join(result.managedRootPath, 'CWCP'),
      );
      expect(
        File(p.join(result.destinationFolderPath, 'capture.html')).existsSync(),
        isTrue,
      );
    },
  );

  test('prefers the metadata shortCode over the package file name', () async {
    final bytes = _zipBytes({
      'manifest.json': _manifestJsonWithShortCode,
      'capture.html': _captureHtml,
    });
    final package = await _writePackage(
      sourceDir,
      'randomly-named-export.studybook',
      bytes,
    );

    final result = await service.importPackage(package.path);

    expect(result.bookCode, 'SSP');
    expect(result.destinationFolderPath, p.join(result.managedRootPath, 'SSP'));
  });

  test('rejects a package that is not a valid ZIP archive', () async {
    final package = await _writePackage(
      sourceDir,
      'broken.studybook',
      Uint8List.fromList('this is not a zip file'.codeUnits),
    );

    await expectLater(
      service.importPackage(package.path),
      throwsA(
        isA<PioneerBookPackageImportException>().having(
          (error) => error.message,
          'message',
          contains('not a valid ZIP'),
        ),
      ),
    );
  });

  test('rejects an empty package', () async {
    final package = await _writePackage(
      sourceDir,
      'empty.studybook',
      _zipBytes(const {}),
    );

    await expectLater(
      service.importPackage(package.path),
      throwsA(
        isA<PioneerBookPackageImportException>().having(
          (error) => error.message,
          'message',
          contains('empty'),
        ),
      ),
    );
  });

  test('rejects a package without any HTML files', () async {
    final package = await _writePackage(
      sourceDir,
      'nohtml.studybook',
      _zipBytes({
        'SSP/metadata.json': '{"title": "No HTML"}',
        'SSP/images/pic.png': 'png-bytes',
      }),
    );

    await expectLater(
      service.importPackage(package.path),
      throwsA(
        isA<PioneerBookPackageImportException>().having(
          (error) => error.message,
          'message',
          contains('manifest.json'),
        ),
      ),
    );
  });

  test(
    'rejects ../ path traversal entries without unpacking anything',
    () async {
      final package = await _writePackage(
        sourceDir,
        'traversal.studybook',
        _zipBytes({
          'SSP/capture.html': _captureHtml,
          '../evil.html': '<html></html>',
        }),
      );

      await expectLater(
        service.importPackage(package.path),
        throwsA(
          isA<PioneerBookPackageImportException>().having(
            (error) => error.message,
            'message',
            contains('".."'),
          ),
        ),
      );
      expect(
        File(p.join(supportDir.path, '..', 'evil.html')).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          p.join(
            supportDir.path,
            PioneerCapturedHtmlImportFolderService.managedImportFolderName,
          ),
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('rejects absolute path entries', () async {
    final package = await _writePackage(
      sourceDir,
      'absolute.studybook',
      _zipBytes({
        'SSP/capture.html': _captureHtml,
        '/tmp/evil.html': '<html></html>',
      }),
    );

    await expectLater(
      service.importPackage(package.path),
      throwsA(
        isA<PioneerBookPackageImportException>().having(
          (error) => error.message,
          'message',
          contains('absolute path'),
        ),
      ),
    );
  });

  test('rejects unsupported package extensions', () async {
    final package = await _writePackage(
      sourceDir,
      'notes.txt',
      _zipBytes({'capture.html': _captureHtml}),
    );

    await expectLater(
      service.importPackage(package.path),
      throwsA(
        isA<PioneerBookPackageImportException>().having(
          (e) => e.message,
          'message',
          contains('Please select a .zip CaptureClipper package'),
        ),
      ),
    );
    // The rejected file is untouched.
    expect(package.existsSync(), isTrue);
  });

  test('the CaptureClipper scanner sees the unpacked package', () async {
    final bytes = _zipBytes({
      'manifest.json': _manifestJsonWithShortCode,
      'capture.html': _captureHtml,
    });
    final package = await _writePackage(
      sourceDir,
      'SSP07-5-2026.studybook',
      bytes,
    );

    final result = await service.importPackage(package.path);

    final previews = await PioneerHtmlCaptureFolderScanner(
      rootPath: result.managedRootPath,
      preferAssetManifest: false,
      knownDevScanPath: null,
    ).scan();

    expect(
      previews.map((preview) => preview.folderPath),
      contains(result.destinationFolderPath),
    );
    final preview = previews.singleWhere(
      (preview) => preview.folderPath == result.destinationFolderPath,
    );
    expect(preview.htmlFileCount, 1);
  });
}
