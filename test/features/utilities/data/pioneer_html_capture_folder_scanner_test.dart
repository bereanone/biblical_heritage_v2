import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:studybible2/features/utilities/data/egw_copied_range_parser.dart';
import 'package:studybible2/features/utilities/data/pioneer_capture_folder_metadata.dart';
import 'package:studybible2/features/utilities/data/pioneer_html_capture_folder_scanner.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';

PioneerSourceCatalog _catalog() {
  return PioneerSourceCatalog.fromJson({
    'authors': [
      {
        'author_id': 'at_jones',
        'author_name': 'A. T. Jones',
        'source_family': 'Pioneer',
        'sort_key': 'a t jones',
        'works': [
          {
            'work_id': 'lessons_on_faith',
            'title': 'Lessons on Faith',
            'abbreviation': 'LOF',
            'group': 'Pioneer Authors',
            'subgroup': 'Righteousness by Faith',
            'availability_status': 'available',
            'source_type': 'epub',
            'source_url': 'https://example.invalid/pioneers.zip',
            'source_label': 'APLIB',
            'verified': true,
            'importable': true,
          },
        ],
      },
    ],
  });
}

PioneerSourceCatalog _darCatalog() {
  return PioneerSourceCatalog.fromJson({
    'authors': [
      {
        'author_id': 'uriah_smith',
        'author_name': 'Uriah Smith',
        'source_family': 'Pioneer',
        'sort_key': 'uriah smith',
        'works': [
          {
            'work_id': 'daniel_and_the_revelation',
            'title': 'Daniel and the Revelation',
            'abbreviation': 'DAR',
            'group': 'Pioneer Authors',
            'subgroup': 'Prophecy',
            'availability_status': 'available',
            'source_type': 'epub',
            'source_url': 'https://example.invalid/pioneers.zip',
            'source_label': 'APLIB',
            'verified': true,
            'importable': true,
          },
        ],
      },
    ],
  });
}

PioneerSourceCatalog _cisCatalog() {
  return PioneerSourceCatalog.fromJson({
    'authors': [
      {
        'author_id': 'sn_haskell',
        'author_name': 'S. N. Haskell',
        'source_family': 'Pioneer',
        'sort_key': 's n haskell',
        'works': [
          {
            'work_id': 'the_cross_and_its_shadow',
            'title': 'The Cross and Its Shadow',
            'abbreviation': 'CIS',
            'group': 'Pioneer Authors',
            'subgroup': 'Sanctuary',
            'availability_status': 'source_needed',
            'source_type': 'capturedHtml',
            'source_label': 'CaptureClipper',
            'verified': false,
            'importable': false,
          },
        ],
      },
    ],
  });
}

const String _lofHtml = '''
<!doctype html>
<html>
  <head><title>Lessons on Faith</title></head>
  <body>
    <div class="clip clip-text">
      <p>Chapter 1 — Living By Faith LOF_ATJ 1 Intro. LOF_ATJ 1.1 Faith matters.</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — The Gift of Righteousness LOF_ATJ 2 Grace is a gift. LOF_ATJ 2.1</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 3 — Walking With God LOF_ATJ 3.1 Faith continues.</p>
    </div>
  </body>
</html>
''';

const String _darHtml = '''
<!doctype html>
<html>
  <head><title>Daniel and the Revelation</title></head>
  <body>
    <div class="clip clip-text">
      <p>Chapter 1 — Daniel in Captivity DAR_US 1.1 A first section. DAR_US 1.2</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — The Great Image DAR_US 2.1 Another section.</p>
    </div>
  </body>
</html>
''';

const String _cisHtml = '''
<!doctype html>
<html>
  <head><title>section_1the_sanctuary_cis_2026-07-01</title></head>
  <body>
    <div class="clip clip-text">
      <p>Section 1-The Sanctuary CIS 14 The Heavenly Sanctuary CIS 14.1 First paragraph. CIS 14.2</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2-The Tabernacle CIS 28 The tabernacle as pitched in the wilderness. CIS 28.1 Second paragraph.</p>
    </div>
  </body>
</html>
''';

const String _cisManifest = '''
{
  "title": "section_1the_sanctuary_cis_2026-07-01",
  "itemCount": 1,
  "imageCount": 1,
  "items": [
    {
      "type": "png_image",
      "imageFileName": "image_0001.png",
      "imagePath": "images/image_0001.png"
    }
  ]
}
''';

const String _sspScannerHtml = '''
<!doctype html>
<html>
  <head><title>SSP</title></head>
  <body>
    <h1>The Story of the Seer of Patmos</h1>
    <h2>Chapter 1 — The Seer of Patmos</h2>
    <div class="clip clip-text">
      <p>SSP 1.1 First paragraph. SSP 1.2 Second paragraph.</p>
    </div>
    <div class="clip clip-text">
      <p>SSP 1.3 Third paragraph. SSP 1.4 Fourth paragraph.</p>
    </div>
  </body>
</html>
''';

Future<Directory> _createCaptureFixtureRoot(
  Directory root, {
  required String folderName,
  required String title,
  required String abbreviation,
  required String author,
  required String workId,
  required String html,
  String? coverImage,
  bool includeExtraImage = false,
}) async {
  final captureDir = Directory(
    p.join(root.path, 'assets', 'scans', folderName),
  );
  final imagesDir = Directory(p.join(captureDir.path, 'images'));
  await imagesDir.create(recursive: true);
  await File(p.join(captureDir.path, 'capture.html')).writeAsString(html);

  final metadata = <String, Object?>{
    'title': title,
    'abbreviation': abbreviation,
    'display_abbreviation': abbreviation,
    'work_id': workId,
    'contributors': [
      {'name': author, 'role': 'author', 'sort_order': 1, 'primary': true},
    ],
    'source_type': 'egw_html_capture',
    'source_site': 'egwwritings.org',
  };
  if (coverImage != null) {
    metadata['cover_image'] = coverImage;
  }
  await File(
    p.join(captureDir.path, 'metadata.json'),
  ).writeAsString(jsonEncode(metadata));

  final coverFile = File(p.join(captureDir.path, coverImage ?? 'cover.jpg'));
  await coverFile.parent.create(recursive: true);
  await coverFile.writeAsString('cover');

  await File(p.join(imagesDir.path, '$folderName.png')).writeAsString('cover');
  if (includeExtraImage) {
    await File(p.join(imagesDir.path, 'image_0001.png')).writeAsString('extra');
  }
  return captureDir;
}

Future<String> Function(String) _assetLoaderForRoot(String rootPath) {
  return (assetKey) async {
    final relativePath = assetKey.replaceFirst('assets/scans/', '');
    final filePath = p.join(rootPath, 'assets', 'scans', relativePath);
    return File(filePath).readAsString();
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('finds LOF_ATJ when passed explicit repo root', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_root_');
    try {
      await File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsString('name: studybible2');
      await _createCaptureFixtureRoot(
        tempDir,
        folderName: 'LOF_ATJ',
        title: 'Lessons on Faith',
        abbreviation: 'LOF_ATJ',
        author: 'A. T. Jones',
        workId: 'lessons_on_faith',
        html: _lofHtml,
        coverImage: 'cover.jpg',
        includeExtraImage: true,
      );
      final result = await PioneerHtmlCaptureFolderScanner(
        projectRootPath: tempDir.path,
        currentDirectoryPath: p.join(tempDir.path, 'build'),
        preferAssetManifest: false,
      ).scanWithReport(catalog: _catalog());

      expect(result.usedFileSystemFallback, isTrue);
      expect(result.usedAssetManifest, isFalse);
      expect(
        result.currentWorkingDirectory,
        p.normalize(p.join(tempDir.path, 'build')),
      );
      expect(
        result.absolutePathChecked,
        p.normalize(p.join(tempDir.path, 'assets/scans')),
      );
      expect(result.fileSystemPathExists, isTrue);
      expect(result.immediateChildFolderCount, greaterThanOrEqualTo(1));
      expect(result.htmlFileCount, greaterThanOrEqualTo(1));
      expect(
        result.fallbackAttemptsTried.first,
        contains('explicit project root'),
      );

      final lof = result.previews.singleWhere(
        (preview) => preview.folderName == 'LOF_ATJ',
      );
      expect(
        lof.htmlFiles.single,
        endsWith('assets/scans/LOF_ATJ/capture.html'),
      );
      expect(lof.isValid, isTrue);
      expect(lof.detectedTitle, 'Lessons on Faith');
      expect(lof.detectedAuthor, 'A. T. Jones');
      expect(lof.detectedAbbreviation, 'LOF_ATJ');
      expect(lof.refCount, greaterThanOrEqualTo(2));
      expect(lof.duplicateRefCount, 0);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'reports invalid capture folders with explicit validation reasons',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('scanner_invalid_');
      try {
        await File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsString('name: studybible2');
        await _createCaptureFixtureRoot(
          tempDir,
          folderName: 'BAD_CAPTURE',
          title: 'Broken Capture',
          abbreviation: 'BC',
          author: 'Unknown',
          workId: 'broken_capture',
          html: '''
<!doctype html>
<html>
  <head><title>Broken Capture</title></head>
  <body>
    <p>No parseable ref codes here.</p>
  </body>
</html>
''',
          coverImage: 'cover.jpg',
        );

        final result = await PioneerHtmlCaptureFolderScanner(
          projectRootPath: tempDir.path,
          currentDirectoryPath: p.join(tempDir.path, 'build'),
          preferAssetManifest: false,
        ).scanWithReport(catalog: _catalog());

        final preview = result.previews.singleWhere(
          (candidate) => candidate.folderName == 'BAD_CAPTURE',
        );
        expect(preview.isValid, isFalse);
        expect(preview.validationReasons, isNotEmpty);
        expect(preview.validationReasons.join(' '), contains('ref'));
        expect(preview.availableFileNames, contains('capture.html'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('ignores Backup folders during filesystem scans', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_backup_');
    try {
      await File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsString('name: studybible2');
      await _createCaptureFixtureRoot(
        tempDir,
        folderName: 'LOF_ATJ',
        title: 'Lessons on Faith',
        abbreviation: 'LOF_ATJ',
        author: 'A. T. Jones',
        workId: 'lessons_on_faith',
        html: _lofHtml,
        coverImage: 'cover.jpg',
        includeExtraImage: true,
      );
      await _createCaptureFixtureRoot(
        tempDir,
        folderName: 'Backup',
        title: 'Backup Book',
        abbreviation: 'BKP',
        author: 'Backup Author',
        workId: 'backup_book',
        html: _lofHtml,
      );

      final result = await PioneerHtmlCaptureFolderScanner(
        projectRootPath: tempDir.path,
        currentDirectoryPath: p.join(tempDir.path, 'build'),
        preferAssetManifest: false,
        ignoredFolderNames: const <String>{'Backup'},
      ).scanWithReport(catalog: _catalog());

      expect(
        result.previews.any((preview) => preview.folderName == 'Backup'),
        isFalse,
      );
      expect(
        result.previews.map((preview) => preview.folderName),
        contains('LOF_ATJ'),
      );
      expect(result.previews, hasLength(1));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'reads manifest image candidates without using slug titles as metadata',
    () {
      final metadata = PioneerCaptureFolderMetadata.fromManifestString(
        _cisManifest,
        folderPath: '/tmp/CIS',
        availableFiles: const ['/tmp/CIS/images/image_0001.png'],
      );

      expect(metadata.title, isNull);
      expect(metadata.coverImagePath, '/tmp/CIS/images/image_0001.png');
    },
  );

  test(
    'prefers catalog metadata and preserves the final section for CIS-style captures',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('scanner_cis_');
      try {
        await File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsString('name: studybible2');
        await _createCaptureFixtureRoot(
          tempDir,
          folderName: 'CIS',
          title: 'section_1the_sanctuary_cis_2026-07-01',
          abbreviation: 'CIS',
          author: 'Unknown',
          workId: 'cis_capture',
          html: _cisHtml,
          coverImage: 'image_0001.png',
        );

        final result = await PioneerHtmlCaptureFolderScanner(
          projectRootPath: tempDir.path,
          currentDirectoryPath: p.join(tempDir.path, 'build'),
          preferAssetManifest: false,
        ).scanWithReport(catalog: _cisCatalog());

        final cis = result.previews.singleWhere(
          (preview) => preview.folderName == 'CIS',
        );
        expect(cis.detectedTitle, 'The Cross and Its Shadow');
        expect(cis.detectedAuthor, anyOf('S. N. Haskell', 'Unknown'));
        expect(cis.extractedText, isNotNull);
        expect(cis.firstChapterLabel, isNotNull);
        expect(cis.lastChapterLabel, isNotNull);
        expect(cis.sourceFileHash, isNotNull);
        expect(cis.preferredCoverImagePath, contains('image_0001.png'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'treats SDP metadata as a placeholder and uses the catalog title',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('scanner_sdp_');
      try {
        await File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsString('name: studybible2');
        await _createCaptureFixtureRoot(
          tempDir,
          folderName: 'DAR',
          title: 'SDP',
          abbreviation: 'DAR',
          author: 'Uriah Smith',
          workId: 'daniel_and_the_revelation',
          html: _darHtml,
          coverImage: 'cover.jpg',
        );

        final result = await PioneerHtmlCaptureFolderScanner(
          projectRootPath: tempDir.path,
          currentDirectoryPath: p.join(tempDir.path, 'build'),
          preferAssetManifest: false,
        ).scanWithReport(catalog: _darCatalog());

        final dar = result.previews.singleWhere(
          (preview) => preview.folderName == 'DAR',
        );
        expect(dar.isValid, isTrue);
        expect(dar.bestEffortWork.title, 'Daniel and the Revelation');
        expect(dar.importWork.title, 'Daniel and the Revelation');
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'treats SSP metadata as a placeholder and uses the catalog title',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('scanner_ssp_');
      try {
        await File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsString('name: studybible2');
        await _createCaptureFixtureRoot(
          tempDir,
          folderName: 'SSP',
          title: 'SSP',
          abbreviation: 'SSP',
          author: 'Unknown',
          workId: 'the_story_of_the_seer_of_patmos',
          html: _sspScannerHtml,
          coverImage: 'cover.jpg',
        );

        final catalog = await PioneerSourceCatalog.load();
        final result = await PioneerHtmlCaptureFolderScanner(
          projectRootPath: tempDir.path,
          currentDirectoryPath: p.join(tempDir.path, 'build'),
          preferAssetManifest: false,
        ).scanWithReport(catalog: catalog);

        final ssp = result.previews.singleWhere(
          (preview) => preview.folderName == 'SSP',
        );
        expect(ssp.isValid, isTrue);
        expect(ssp.bestEffortWork.title, 'The Story of the Seer of Patmos');
        expect(ssp.importWork.title, 'The Story of the Seer of Patmos');
        expect(ssp.bestEffortWork.authorName, 'S. N. Haskell');
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'normalizes brace-wrapped SSP refs into importable extracted text',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'scanner_ssp_refs_',
      );
      try {
        await File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsString('name: studybible2');
        await _createCaptureFixtureRoot(
          tempDir,
          folderName: 'SSP',
          title: 'SSP',
          abbreviation: 'SSP',
          author: 'Unknown',
          workId: 'the_story_of_the_seer_of_patmos',
          html: '''
<!doctype html>
<html>
  <head><title>SSP</title></head>
  <body>
    <h1>The Story of the Seer of Patmos</h1>
    <div class="clip clip-text">
      <p>First paragraph. {SSP 1.1}</p>
    </div>
    <div class="clip clip-text">
      <p>Second paragraph. {SSP 1.2}</p>
    </div>
  </body>
</html>
''',
          coverImage: 'cover.jpg',
        );

        final catalog = await PioneerSourceCatalog.load();
        final result = await PioneerHtmlCaptureFolderScanner(
          projectRootPath: tempDir.path,
          currentDirectoryPath: p.join(tempDir.path, 'build'),
          preferAssetManifest: false,
        ).scanWithReport(catalog: catalog);

        final ssp = result.previews.singleWhere(
          (preview) => preview.folderName == 'SSP',
        );
        expect(ssp.isValid, isTrue);
        expect(ssp.refCount, greaterThan(0));
        expect(ssp.firstRef, 'SSP 1.1');
        expect(ssp.lastRef, 'SSP 1.2');
        expect(ssp.extractedText, isNotNull);
        expect(ssp.extractedText, contains('SSP 1.1'));
        expect(ssp.extractedText, isNot(contains('{SSP 1.1}')));
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('finds repo root by walking upward to pubspec.yaml', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_walk_');
    try {
      await File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsString('name: studybible2');
      final nestedWorkingDirectory = p.join(
        tempDir.path,
        'assets',
        'scans',
        'LOF_ATJ',
        'images',
      );
      await _createCaptureFixtureRoot(
        tempDir,
        folderName: 'LOF_ATJ',
        title: 'Lessons on Faith',
        abbreviation: 'LOF_ATJ',
        author: 'A. T. Jones',
        workId: 'lessons_on_faith',
        html: _lofHtml,
        coverImage: 'cover.jpg',
        includeExtraImage: true,
      );
      final result = await PioneerHtmlCaptureFolderScanner(
        currentDirectoryPath: nestedWorkingDirectory,
        preferAssetManifest: false,
      ).scanWithReport(catalog: _catalog());

      expect(result.usedFileSystemFallback, isTrue);
      expect(
        result.fallbackAttemptsTried.first,
        contains('walked up from ${p.normalize(nestedWorkingDirectory)}'),
      );
      expect(
        result.absolutePathChecked,
        p.normalize(p.join(tempDir.path, 'assets/scans')),
      );
      expect(result.fileSystemPathExists, isTrue);
      expect(
        result.previews.map((preview) => preview.folderName),
        contains('LOF_ATJ'),
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('scans LOF_ATJ staged HTML capture metadata', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_stage_');
    try {
      await _createCaptureFixtureRoot(
        tempDir,
        folderName: 'LOF_ATJ',
        title: 'Lessons on Faith',
        abbreviation: 'LOF_ATJ',
        author: 'A. T. Jones',
        workId: 'lessons_on_faith',
        html: _lofHtml,
        coverImage: 'cover.jpg',
        includeExtraImage: true,
      );
      final previews = await PioneerHtmlCaptureFolderScanner(
        projectRootPath: tempDir.path,
        currentDirectoryPath: tempDir.path,
        preferAssetManifest: false,
      ).scan(catalog: _catalog());
      final lof = previews.singleWhere(
        (preview) => preview.folderName == 'LOF_ATJ',
      );

      expect(lof.isValid, isTrue);
      expect(lof.detectedTitle, 'Lessons on Faith');
      expect(lof.detectedAuthor, 'A. T. Jones');
      expect(lof.detectedAbbreviation, 'LOF_ATJ');
      expect(lof.htmlFileCount, 1);
      expect(lof.imageFileCount, 3);
      expect(lof.preferredCoverImagePath, endsWith('cover.jpg'));
      expect(lof.firstRef, isNotNull);
      expect(lof.lastRef, isNotNull);
      expect(lof.refCount, greaterThanOrEqualTo(2));
      expect(lof.duplicateRefCount, 0);
      expect(lof.chapterHeadingCount, greaterThan(0));
      expect(lof.extractedText, contains('Chapter 1 — Living By Faith'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('groups asset manifest keys under assets/scans/LOF_ATJ', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_assets_');
    try {
      await _createCaptureFixtureRoot(
        tempDir,
        folderName: 'LOF_ATJ',
        title: 'Lessons on Faith',
        abbreviation: 'LOF_ATJ',
        author: 'A. T. Jones',
        workId: 'lessons_on_faith',
        html: _lofHtml,
        coverImage: 'cover.jpg',
        includeExtraImage: true,
      );
      final result = await PioneerHtmlCaptureFolderScanner(
        currentDirectoryPath: '/tmp/studybible2-missing-cwd',
        knownDevScanPath: null,
        assetManifestKeys: const <String>[
          'assets/scans/LOF_ATJ/capture.html',
          'assets/scans/LOF_ATJ/metadata.json',
          'assets/scans/LOF_ATJ/images/LOF_ATJ.png',
          'assets/scans/LOF_ATJ/images/image_0001.png',
          'assets/scans/LOF_ATJ/manifest.json',
        ],
        assetStringLoader: _assetLoaderForRoot(tempDir.path),
      ).scanWithReport(catalog: _catalog());

      expect(result.usedAssetManifest, isTrue);
      expect(result.usedFileSystemFallback, isFalse);
      expect(result.assetKeyCount, 5);
      expect(result.scanAssetKeyCount, 5);

      final lof = result.previews.single;
      expect(lof.folderName, 'LOF_ATJ');
      expect(lof.htmlFiles, contains('assets/scans/LOF_ATJ/capture.html'));
      expect(
        lof.imageFiles,
        contains('assets/scans/LOF_ATJ/images/LOF_ATJ.png'),
      );
      expect(lof.isValid, isTrue);
      expect(lof.detectedTitle, 'Lessons on Faith');
      expect(lof.detectedAuthor, 'A. T. Jones');
      expect(lof.detectedAbbreviation, 'LOF_ATJ');
      expect(lof.refCount, greaterThanOrEqualTo(2));
      expect(lof.duplicateRefCount, 0);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('empty result includes useful filesystem diagnostics', () async {
    final result = await PioneerHtmlCaptureFolderScanner(
      rootPath: 'assets/missing_scans',
      currentDirectoryPath: '/tmp',
      knownDevScanPath: null,
      preferAssetManifest: false,
      assetStringLoader: _assetLoaderForRoot('/tmp'),
    ).scanWithReport(catalog: _catalog());

    expect(result.previews, isEmpty);
    expect(result.usedFileSystemFallback, isTrue);
    expect(result.fileSystemPathExists, isFalse);
    expect(result.immediateChildFolderCount, 0);
    expect(result.htmlFileCount, 0);
    expect(result.absolutePathChecked, contains('/tmp/assets/missing_scans'));
    expect(result.emptyStateMessage, contains('CWD: /tmp'));
    expect(result.emptyStateMessage, contains('absolute path checked:'));
    expect(result.emptyStateMessage, contains('exists: false'));
    expect(result.emptyStateMessage, contains('child folders: 0'));
    expect(result.emptyStateMessage, contains('HTML files: 0'));
    expect(result.emptyStateMessage, contains('fallback attempts:'));
  });

  test(
    'falls back to filesystem scanning when asset manifest has no scan keys',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('scanner_fs_');
      try {
        await _createCaptureFixtureRoot(
          tempDir,
          folderName: 'LOF_ATJ',
          title: 'Lessons on Faith',
          abbreviation: 'LOF_ATJ',
          author: 'A. T. Jones',
          workId: 'lessons_on_faith',
          html: _lofHtml,
          coverImage: 'cover.jpg',
          includeExtraImage: true,
        );
        final previews = await PioneerHtmlCaptureFolderScanner(
          projectRootPath: tempDir.path,
          currentDirectoryPath: tempDir.path,
          assetManifestKeys: const <String>[],
          preferAssetManifest: false,
        ).scan(catalog: _catalog());

        expect(
          previews.map((preview) => preview.folderName),
          contains('LOF_ATJ'),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test('extractor converts inline capture refs to copied-range lines', () {
    const html = '''
<!doctype html>
<html><body>
  <div class="clip clip-text">
    <p>Chapter 1—Opening  ABC_DEF 2 A. T. Jones Body one.  ABC_DEF 2.1 Body two &amp; more.  ABC_DEF 2.2</p>
  </div>
</body></html>
''';

    final result = const EgwHtmlCaptureExtractor().extract(html);

    expect(result.detectedAbbreviation, 'ABC_DEF');
    expect(result.firstRef, 'ABC_DEF 2.1');
    expect(result.lastRef, 'ABC_DEF 2.2');
    expect(result.duplicateRefCount, 0);
    expect(result.text, contains('Chapter 1 — Opening'));
    expect(result.text, contains('ABC_DEF 2\nBody one.\nABC_DEF 2.1'));
    expect(result.text, contains('Body two & more.\nABC_DEF 2.2'));
  });

  test(
    'extractor strips copied-EGW prefixes and detects real book headings',
    () {
      const html = '''
<!doctype html>
<html>
  <head>
    <title>SSP</title>
    <meta name="generator" content="CaptureClipper">
    <meta name="author" content="Stephen Nelson Haskell">
  </head>
  <body>
    <section class="capture-session" data-app="CaptureClipper" data-mode="clipboard-html">
      <div class="clip clip-image" data-index="1" data-type="image">
        <img src="images/image_0001.png" alt="Captured image 1">
      </div>
      <div class="clip clip-text" data-index="2" data-type="text">
        <p>The Story of the Seer of Patmos, p. 3 (Stephen Nelson Haskell) AUTHOR’S PREFACE  SSP 3 The Story of the Seer of Patmos, p. 3.1 (Stephen Nelson Haskell) Prophecy is often considered dark and mysterious.  SSP 3.1 The Story of the Seer of Patmos, p. 3.2 (Stephen Nelson Haskell) God has given the book of Revelation a title.  SSP 3.2</p>
      </div>
      <div class="clip clip-text" data-index="3" data-type="text">
        <p>The Story of the Seer of Patmos, p. 11 (Stephen Nelson Haskell) CHAPTER I. THE SEER OF PATMOS.  SSP 11 The Story of the Seer of Patmos, p. 11.1 (Stephen Nelson Haskell) The Revelation opens with a blessing on the reader.  SSP 11.1</p>
      </div>
      <div class="clip clip-text" data-index="4" data-type="text">
        <p>The Story of the Seer of Patmos, p. 28 (Stephen Nelson Haskell) CHAPTER II. THE AUTHOR OF THE REVELATION.  SSP 28 The Story of the Seer of Patmos, p. 28.1 (Stephen Nelson Haskell) John was in the isle that is called Patmos.  SSP 28.1</p>
      </div>
    </section>
  </body>
</html>
''';

      final result = const EgwHtmlCaptureExtractor().extract(
        html,
        fallbackAbbreviation: 'SSP',
        fallbackTitle: 'SSP',
      );

      expect(result.detectedAbbreviation, 'SSP');
      expect(result.detectedTitle, 'The Story of the Seer of Patmos');
      expect(result.detectedAuthor, 'Stephen Nelson Haskell');
      expect(result.chapterHeadingCount, 3);
      expect(result.text, isNot(contains(', p.')));
      expect(result.text, isNot(contains('(Stephen Nelson Haskell)')));
      expect(result.text, isNot(contains('Chapter 1 — SSP')));

      final parsed = parseEgwCopiedRangeText(
        result.text,
        workAbbreviation: 'SSP',
      );
      final sectionTitles = parsed.document.sections
          .map((section) => section.title)
          .toList(growable: false);
      expect(sectionTitles, [
        'AUTHOR’S PREFACE.',
        'CHAPTER I. THE SEER OF PATMOS.',
        'CHAPTER II. THE AUTHOR OF THE REVELATION.',
      ]);
      final preface = parsed.document.sections.first;
      expect(preface.paragraphs, hasLength(2));
      expect(
        preface.paragraphs.first.text,
        'Prophecy is often considered dark and mysterious.',
      );
      expect(preface.paragraphs.first.ref, 'SSP 3.1');
      expect(parsed.report.isValid, isTrue);
    },
  );

  test(
    'extractor dedupes repeated copied-EGW headings and skips unreferenced front matter',
    () {
      const html = '''
<!doctype html>
<html>
  <head><title>FP187</title></head>
  <body>
    <div class="clip clip-text" data-index="2" data-type="text">
      <p>Fundamental Principles, p. 3 (General Conference of SDA) Fundamental Principles  FP1872 3  A DECLARATION OF THE Fundamental Principles TAUGHT AND PRACTICED -BY- THE SEVENTH-DAY ADVENTISTS. STEAM PRESS OF THE SEVENTH-DAY ADVENTIST PUBLISHING ASSOCIATION, BATTLE CREEK, MICH.: 1872.</p>
    </div>
    <div class="clip clip-text" data-index="3" data-type="text">
      <p>Fundamental Principles, p. 3 (General Conference of SDA) Fundamental Principles  FP1872 3 Fundamental Principles, p. 3.1 (General Conference of SDA) In presenting to the public this synopsis of our faith, we wish to have it distinctly understood.  FP1872 3.1 Fundamental Principles, p. 3.2 (General Conference of SDA) As Seventh-day Adventists we desire simply that our position shall be understood.  FP1872 3.2</p>
    </div>
  </body>
</html>
''';

      final result = const EgwHtmlCaptureExtractor().extract(
        html,
        fallbackAbbreviation: 'FP',
        fallbackTitle: 'FP187',
      );

      expect(result.detectedAbbreviation, 'FP1872');
      expect(result.detectedTitle, 'Fundamental Principles');
      expect(result.detectedAuthor, 'General Conference of SDA');
      expect(result.chapterHeadingCount, 1);
      expect(result.text, isNot(contains(', p.')));
      expect(result.text, isNot(contains('STEAM PRESS')));
      expect(
        result.warnings.any(
          (warning) => warning.contains('Skipped unreferenced front matter'),
        ),
        isTrue,
      );

      final parsed = parseEgwCopiedRangeText(
        result.text,
        workAbbreviation: 'FP1872',
      );
      expect(parsed.document.sections, hasLength(1));
      expect(parsed.document.sections.single.title, 'FUNDAMENTAL PRINCIPLES.');
      expect(parsed.document.sections.single.paragraphs, hasLength(2));
      expect(
        parsed.document.sections.single.paragraphs.first.text,
        startsWith('In presenting to the public'),
      );
      expect(parsed.report.isValid, isTrue);
    },
  );

  test('counts a synthetic capture.html written to a temp directory', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_fake_');
    try {
      final captureDir = Directory(
        p.join(tempDir.path, 'assets', 'scans', 'LOF_ATJ'),
      );
      await captureDir.create(recursive: true);
      await File(p.join(captureDir.path, 'capture.html')).writeAsString('''
<!doctype html>
<html><head><title>Lessons on Faith</title></head><body>
  <div class="clip clip-text">
    <p>Chapter 1 — Living By Faith  LOF_ATJ 4 Living by faith requires trust.  LOF_ATJ 4.1 Faith itself is the key.  LOF_ATJ 4.2</p>
  </div>
  <div class="clip clip-text">
    <p>Chapter 2 — The Gift of Righteousness  LOF_ATJ 5 Righteousness is a gift.  LOF_ATJ 5.1</p>
  </div>
</body></html>
''');
      await File(p.join(captureDir.path, 'metadata.json')).writeAsString('''
{
  "title": "Lessons on Faith",
  "abbreviation": "LOF_ATJ",
  "display_abbreviation": "LOF_ATJ",
  "work_id": "lessons_on_faith",
  "contributors": [
    {
      "name": "A. T. Jones",
      "role": "author",
      "sort_order": 1,
      "primary": true
    }
  ],
  "source_type": "egw_html_capture",
  "source_site": "egwwritings.org",
  "cover_image": "cover.jpg"
}
''');
      await File(p.join(captureDir.path, 'cover.jpg')).writeAsString('cover');

      final result = await PioneerHtmlCaptureFolderScanner(
        projectRootPath: tempDir.path,
        currentDirectoryPath: tempDir.path,
        preferAssetManifest: false,
      ).scanWithReport(catalog: _catalog());

      expect(result.usedFileSystemFallback, isTrue);
      expect(result.fileSystemPathExists, isTrue);
      expect(result.immediateChildFolderCount, 1);
      expect(result.htmlFileCount, 1);
      expect(result.previews, hasLength(1));

      final preview = result.previews.single;
      expect(preview.folderName, 'LOF_ATJ');
      expect(preview.htmlFileCount, 1);
      expect(preview.isValid, isTrue);
      expect(preview.detectedAbbreviation, 'LOF_ATJ');
      expect(preview.refCount, greaterThanOrEqualTo(2));
      expect(preview.chapterHeadingCount, greaterThanOrEqualTo(2));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('prefers root cover image before other scan images', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_cover_');
    try {
      final captureDir = Directory(
        p.join(tempDir.path, 'assets', 'scans', 'LOF_ATJ'),
      );
      final imageDir = Directory(p.join(captureDir.path, 'images'));
      await imageDir.create(recursive: true);
      await File(p.join(captureDir.path, 'capture.html')).writeAsString('''
<!doctype html><html><body>
  <div class="clip clip-text">
    <p>Lessons on Faith  LOF_ATJ 1 Intro. LOF_ATJ 1.1</p>
  </div>
</body></html>
''');
      await File(p.join(captureDir.path, 'metadata.json')).writeAsString('''
{
  "title": "Lessons on Faith",
  "abbreviation": "LOF_ATJ",
  "display_abbreviation": "LOF_ATJ",
  "work_id": "lessons_on_faith",
  "contributors": [
    {
      "name": "A. T. Jones",
      "role": "author",
      "sort_order": 1,
      "primary": true
    }
  ],
  "source_type": "egw_html_capture",
  "source_site": "egwwritings.org",
  "cover_image": "cover.jpg"
}
''');
      await File(p.join(captureDir.path, 'cover.jpg')).writeAsString('cover');
      await File(p.join(imageDir.path, 'LOF_ATJ.png')).writeAsString('other');

      final preview = (await PioneerHtmlCaptureFolderScanner(
        projectRootPath: tempDir.path,
        currentDirectoryPath: tempDir.path,
        preferAssetManifest: false,
      ).scan(catalog: _catalog())).single;

      expect(preview.preferredCoverImagePath, endsWith('cover.jpg'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('metadata cover_image wins over default cover filenames', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_metadata_');
    try {
      final captureDir = Directory(
        p.join(tempDir.path, 'assets', 'scans', 'LOF_ATJ'),
      );
      final imageDir = Directory(p.join(captureDir.path, 'images'));
      await imageDir.create(recursive: true);
      await File(p.join(captureDir.path, 'capture.html')).writeAsString('''
<!doctype html><html><body>
  <div class="clip clip-text">
    <p>Lessons on Faith  LOF_ATJ 1 Intro. LOF_ATJ 1.1</p>
  </div>
</body></html>
''');
      await File(p.join(captureDir.path, 'metadata.json')).writeAsString('''
{
  "title": "Lessons on Faith",
  "abbreviation": "LOF_ATJ",
  "display_abbreviation": "LOF_ATJ",
  "work_id": "lessons_on_faith",
  "contributors": [
    {
      "name": "A. T. Jones",
      "role": "author",
      "sort_order": 1,
      "primary": true
    }
  ],
  "source_type": "egw_html_capture",
  "source_site": "egwwritings.org",
  "cover_image": "images/custom.jpg"
}
''');
      await File(p.join(captureDir.path, 'cover.png')).writeAsString('cover');
      await File(p.join(imageDir.path, 'custom.jpg')).writeAsString('custom');

      final preview = (await PioneerHtmlCaptureFolderScanner(
        projectRootPath: tempDir.path,
        currentDirectoryPath: tempDir.path,
        preferAssetManifest: false,
      ).scan(catalog: _catalog())).single;

      expect(preview.preferredCoverImagePath, endsWith('images/custom.jpg'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'DAR metadata controls the import identity instead of the EPUB row',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('scanner_dar_');
      try {
        await _createCaptureFixtureRoot(
          tempDir,
          folderName: 'DAR',
          title: 'Daniel and the Revelation',
          abbreviation: 'DAR_US',
          author: 'Uriah Smith',
          workId: 'DAR_US',
          html: _darHtml,
          coverImage: 'images/image_0001.png',
          includeExtraImage: true,
        );
        final previews = await PioneerHtmlCaptureFolderScanner(
          projectRootPath: tempDir.path,
          currentDirectoryPath: tempDir.path,
          preferAssetManifest: false,
        ).scan(catalog: _darCatalog());
        final dar = previews.singleWhere(
          (preview) => preview.folderName == 'DAR',
        );

        expect(dar.isValid, isTrue);
        expect(dar.metadata.workId, 'DAR_US');
        expect(dar.metadata.primaryContributorName, 'Uriah Smith');
        expect(dar.catalogWork?.id, 'daniel_and_the_revelation');
        expect(dar.importWork.id, 'DAR_US');
        expect(dar.importWork.title, 'Daniel and the Revelation');
        expect(dar.importWork.authorName, 'Uriah Smith');
        expect(dar.importWork.cachedCoverPath, contains('image_0001.png'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );
}
