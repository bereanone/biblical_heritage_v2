import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../tool/elibrary_acquisition/import_scans_to_asset_db.dart';

Future<File> _writeImage(File file, img.Image image) async {
  await file.parent.create(recursive: true);
  return file.writeAsBytes(img.encodePng(image), flush: true);
}

img.Image _solidImage({
  required int width,
  required int height,
  required img.Color color,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color);
  return image;
}

void main() {
  test('large cover image creates normalized 300x450 thumbnail', () async {
    final tempDir = await Directory.systemTemp.createTemp('scan_cover_large_');
    try {
      final source = await _writeImage(
        File(p.join(tempDir.path, 'scan', 'cover.png')),
        _solidImage(
          width: 1200,
          height: 1800,
          color: img.ColorRgb8(40, 90, 160),
        ),
      );
      final coverRoot = Directory(p.join(tempDir.path, 'library_covers'));
      final warnings = <String>[];

      final thumbPath = await normalizeScanCoverAssets(
        sourcePath: source.path,
        workId: 'LARGE',
        coverRoot: coverRoot,
        warnings: warnings,
      );

      expect(warnings, isEmpty);
      expect(thumbPath, p.join(coverRoot.path, 'thumbs', 'LARGE.png'));

      final thumb = img.decodePng(await File(thumbPath!).readAsBytes());
      final display = img.decodePng(
        await File(p.join(coverRoot.path, 'LARGE.png')).readAsBytes(),
      );
      expect(thumb?.width, 300);
      expect(thumb?.height, 450);
      expect(display?.width, 600);
      expect(display?.height, 900);
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('odd aspect ratio cover is center-cropped without distortion', () async {
    final tempDir = await Directory.systemTemp.createTemp('scan_cover_odd_');
    try {
      final image = img.Image(width: 900, height: 300);
      img.fill(image, color: img.ColorRgb8(160, 30, 30));
      img.fillRect(
        image,
        x1: 350,
        y1: 0,
        x2: 549,
        y2: 299,
        color: img.ColorRgb8(30, 160, 80),
      );
      final source = await _writeImage(
        File(p.join(tempDir.path, 'scan', 'wide.png')),
        image,
      );
      final coverRoot = Directory(p.join(tempDir.path, 'library_covers'));
      final warnings = <String>[];

      final thumbPath = await normalizeScanCoverAssets(
        sourcePath: source.path,
        workId: 'WIDE',
        coverRoot: coverRoot,
        warnings: warnings,
      );

      expect(warnings, isEmpty);
      final thumb = img.decodePng(await File(thumbPath!).readAsBytes());
      expect(thumb?.width, 300);
      expect(thumb?.height, 450);

      final centerPixel = thumb!.getPixel(150, 225);
      expect(centerPixel.r, lessThan(60));
      expect(centerPixel.g, greaterThan(130));
      expect(centerPixel.b, lessThan(110));
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('missing cover uses fallback tile path', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'scan_cover_missing_',
    );
    try {
      final coverRoot = Directory(p.join(tempDir.path, 'library_covers'));
      final warnings = <String>[];

      final thumbPath = await normalizeScanCoverAssets(
        sourcePath: null,
        workId: 'MISSING',
        coverRoot: coverRoot,
        warnings: warnings,
      );

      expect(thumbPath, isNull);
      expect(warnings.single, contains('generated fallback tile'));
      expect(coverRoot.existsSync(), isFalse);
    } finally {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
