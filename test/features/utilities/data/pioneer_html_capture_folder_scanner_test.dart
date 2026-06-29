import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
      {
        'name': author,
        'role': 'author',
        'sort_order': 1,
        'primary': true,
      },
    ],
    'source_type': 'egw_html_capture',
    'source_site': 'egwwritings.org',
  };
  if (coverImage != null) {
    metadata['cover_image'] = coverImage;
  }
  await File(p.join(captureDir.path, 'metadata.json')).writeAsString(
    jsonEncode(metadata),
  );

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
  test('finds LOF_ATJ when passed explicit repo root', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_root_');
    try {
      await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString(
        'name: studybible2',
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
      expect(lof.htmlFiles.single, endsWith('assets/scans/LOF_ATJ/capture.html'));
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

  test('finds repo root by walking upward to pubspec.yaml', () async {
    final tempDir = await Directory.systemTemp.createTemp('scanner_walk_');
    try {
      await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString(
        'name: studybible2',
      );
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
      expect(lof.imageFiles, contains('assets/scans/LOF_ATJ/images/LOF_ATJ.png'));
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
      expect(preview.refCount, 3);
      expect(preview.chapterHeadingCount, 3);
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
