import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'library_epub_cover_extractor.dart';
import 'pioneer_cover_generator_service.dart';

/// Write-time cover assignment for freshly-imported Pioneer EPUBs: prefers
/// whatever cover the EPUB itself declares, and only when it has none does
/// it generate a placeholder from the shared Pioneer template. Callers
/// should invoke this once, when a `library_items` row is first created —
/// never as a catalog-read fallback, and never for an item that already has
/// a cover.
class PioneerCoverAssignmentService {
  const PioneerCoverAssignmentService._();

  static const PioneerCoverAssignmentService instance =
      PioneerCoverAssignmentService._();

  /// Returns the path of the cached cover image for [itemId], or `null` if
  /// nothing could be produced (a failure here must never fail the import
  /// itself).
  Future<String?> ensureCoverPath({
    required Uint8List epubBytes,
    required String rootPath,
    required String itemId,
    required String title,
    required String author,
  }) async {
    try {
      final coverDir = Directory(
        p.join(rootPath, 'Graphics', 'eLibraryCovers'),
      );
      await coverDir.create(recursive: true);

      final embedded = LibraryEpubCoverExtractor.extractCoverImage(epubBytes);
      if (embedded != null) {
        final coverPath = p.join(coverDir.path, '$itemId${embedded.extension}');
        await File(coverPath).writeAsBytes(embedded.bytes, flush: true);
        return coverPath;
      }

      final generated = await PioneerCoverGeneratorService.instance
          .generateCoverPng(title: title, author: author);
      final coverPath = p.join(coverDir.path, '$itemId.png');
      await File(coverPath).writeAsBytes(generated, flush: true);
      return coverPath;
    } catch (_) {
      return null;
    }
  }
}
