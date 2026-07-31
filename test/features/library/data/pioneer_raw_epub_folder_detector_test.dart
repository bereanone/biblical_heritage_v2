import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:studybible2/features/library/data/pioneer_raw_epub_folder_detector.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pioneer_folder_survey_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('11. a folder of raw Pioneer EPUBs (no HTML captures) is detected as '
      'the deferred raw-EPUB case', () async {
    await File(p.join(tempDir.path, 'book_one.epub')).writeAsString('x');
    await File(p.join(tempDir.path, 'book_two.epub')).writeAsString('x');

    final survey = await surveyPioneerFolderContents(tempDir);

    expect(survey.hasRawEpub, isTrue);
    expect(survey.hasHtml, isFalse);
    expect(survey.isRawEpubFolder, isTrue);
    expect(survey.supportsExistingCaptureImport, isFalse);
  });

  test('a CaptureClipper folder (has HTML captures) is routed through the '
      'existing capture import, even if EPUBs also sit alongside it', () async {
    await File(
      p.join(tempDir.path, 'capture.html'),
    ).writeAsString('<html></html>');
    await File(p.join(tempDir.path, 'unrelated.epub')).writeAsString('x');

    final survey = await surveyPioneerFolderContents(tempDir);

    expect(survey.hasHtml, isTrue);
    expect(survey.supportsExistingCaptureImport, isTrue);
    expect(survey.isRawEpubFolder, isFalse);
  });

  test('an empty folder has neither HTML nor EPUB content', () async {
    final survey = await surveyPioneerFolderContents(tempDir);
    expect(survey.hasHtml, isFalse);
    expect(survey.hasRawEpub, isFalse);
    expect(survey.isRawEpubFolder, isFalse);
    expect(survey.supportsExistingCaptureImport, isFalse);
  });

  test('scanning never writes to or modifies the folder', () async {
    await File(p.join(tempDir.path, 'book.epub')).writeAsString('original');
    final before = await File(p.join(tempDir.path, 'book.epub')).readAsString();

    await surveyPioneerFolderContents(tempDir);

    final after = await File(p.join(tempDir.path, 'book.epub')).readAsString();
    expect(after, before);
  });
}
