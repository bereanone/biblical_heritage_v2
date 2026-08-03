import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_zip_extract_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('pioneer_zip_support_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return supportDir.path;
          }
          return supportDir.path;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (supportDir.existsSync()) {
      await supportDir.delete(recursive: true);
    }
  });

  test(
    'extracts files from a ZIP into the app support working folder',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('BookOne.epub', 'epub-one-bytes'))
        ..addFile(ArchiveFile.string('Authors/BookTwo.epub', 'epub-two-bytes'))
        ..addFile(ArchiveFile.string('__MACOSX/._BookOne.epub', 'junk'));
      final zipBytes = ZipEncoder().encode(archive);

      final tempDir = Directory.systemTemp.createTempSync(
        'pioneer_zip_extract_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final zipFile = File('${tempDir.path}/Pioneer-Library-EPUBs.zip');
      await zipFile.writeAsBytes(zipBytes);

      final extractedPath = await PioneerZipExtractService.instance
          .extractToWorkingFolder(zipFile.path);

      final extractedDir = Directory(extractedPath);
      expect(await extractedDir.exists(), isTrue);
      expect(
        await File('$extractedPath/BookOne.epub').readAsString(),
        'epub-one-bytes',
      );
      expect(
        await File('$extractedPath/Authors/BookTwo.epub').readAsString(),
        'epub-two-bytes',
      );
      expect(
        await File('$extractedPath/__MACOSX/._BookOne.epub').exists(),
        isFalse,
      );
    },
  );

  test('re-extracting clears the previous working folder', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pioneer_zip_extract_test2_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    Future<String> writeAndExtract(String fileName) async {
      final archive = Archive()
        ..addFile(ArchiveFile.string(fileName, 'contents'));
      final zipFile = File('${tempDir.path}/$fileName.zip');
      await zipFile.writeAsBytes(ZipEncoder().encode(archive));
      return PioneerZipExtractService.instance.extractToWorkingFolder(
        zipFile.path,
      );
    }

    final firstPath = await writeAndExtract('First.epub');
    expect(await File('$firstPath/First.epub').exists(), isTrue);

    final secondPath = await writeAndExtract('Second.epub');
    expect(secondPath, firstPath);
    expect(await File('$secondPath/First.epub').exists(), isFalse);
    expect(await File('$secondPath/Second.epub').exists(), isTrue);
  });

  test('rejects a file that is not a ZIP archive', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pioneer_zip_extract_test3_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final notAZip = File('${tempDir.path}/not-a-zip.zip');
    await notAZip.writeAsString('just some text, not a zip archive');

    expect(
      () => PioneerZipExtractService.instance.extractToWorkingFolder(
        notAZip.path,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an archive entry outside the working folder', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'pioneer_zip_traversal_test_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final zipFile = File('${tempDir.path}/unsafe.zip');
    final archive = Archive()
      ..addFile(ArchiveFile.string('../escaped.epub', 'unsafe'));
    await zipFile.writeAsBytes(ZipEncoder().encode(archive));

    await expectLater(
      PioneerZipExtractService.instance.extractToWorkingFolder(zipFile.path),
      throwsA(isA<FormatException>()),
    );
    expect(
      File('${supportDir.parent.path}/escaped.epub').existsSync(),
      isFalse,
    );
  });

  test('rejects a missing file', () async {
    expect(
      () => PioneerZipExtractService.instance.extractToWorkingFolder(
        '/nonexistent/path/Missing.zip',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
