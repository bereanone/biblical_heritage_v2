import 'dart:io';

import '../presentation/canonical_local_image.dart';
import 'library_document_models.dart';

class LibraryDocumentValidationResult {
  const LibraryDocumentValidationResult({
    required this.passed,
    required this.reasons,
  });

  static const LibraryDocumentValidationResult ok =
      LibraryDocumentValidationResult(passed: true, reasons: <String>[]);

  final bool passed;
  final List<String> reasons;

  String get summary => reasons.join('; ');
}

/// Validates a staged canonical document generation before it is allowed to
/// replace the active generation (and, by extension, before any EPUB storage
/// policy is permitted to remove the source archive). Fails closed: any
/// unmet check keeps the prior usable generation active and the EPUB
/// retained.
class LibraryDocumentImportValidator {
  const LibraryDocumentImportValidator();

  LibraryDocumentValidationResult validate({
    required List<Map<String, Object?>> sections,
    required List<Map<String, Object?>> blocks,
    Directory? imageAssetRoot,
  }) {
    final reasons = <String>[];

    if (sections.isEmpty) {
      reasons.add('No sections were produced from the source.');
    }
    if (blocks.isEmpty) {
      reasons.add('No content blocks were produced from the source.');
      return LibraryDocumentValidationResult(passed: false, reasons: reasons);
    }

    final ordered = List<Map<String, Object?>>.of(blocks)
      ..sort(
        (a, b) => (a['display_order']! as num).toInt().compareTo(
          (b['display_order']! as num).toInt(),
        ),
      );
    for (var i = 0; i < ordered.length; i++) {
      final order = (ordered[i]['display_order']! as num).toInt();
      if (order != i) {
        reasons.add(
          'Block order is not contiguous starting at 0 (expected $i, found $order).',
        );
        break;
      }
    }

    final hasReadableContent = ordered.any((row) {
      final type = libraryDocumentBlockTypeFromStorage(
        row['block_type']!.toString(),
      );
      if (type == LibraryDocumentBlockType.image ||
          type == LibraryDocumentBlockType.horizontalRule) {
        return false;
      }
      return (row['plain_text']?.toString() ?? '').trim().isNotEmpty;
    });
    if (!hasReadableContent) {
      reasons.add('No readable main content was found in the source.');
    }

    final hasMainContentAfterFrontMatter = ordered.any((row) {
      final formatted = LibraryFormattedContent.fromJson(
        row['formatted_content']?.toString(),
      );
      if (formatted.metadata['heading_role']?.toString() == 'front_matter') {
        return false;
      }
      final type = libraryDocumentBlockTypeFromStorage(
        row['block_type']!.toString(),
      );
      final hasText = (row['plain_text']?.toString() ?? '').trim().isNotEmpty;
      return hasText || type == LibraryDocumentBlockType.image;
    });
    if (!hasMainContentAfterFrontMatter) {
      reasons.add(
        'No main-content block was found after front matter; the book would open to a dead end.',
      );
    }

    if (imageAssetRoot != null) {
      for (final row in ordered) {
        final type = libraryDocumentBlockTypeFromStorage(
          row['block_type']!.toString(),
        );
        if (type != LibraryDocumentBlockType.image) continue;
        final formatted = LibraryFormattedContent.fromJson(
          row['formatted_content']?.toString(),
        );
        final imageNode = formatted.nodes
            .cast<Map<String, Object?>>()
            .where((node) => node['type'] == 'image')
            .firstOrNull;
        final source = imageNode?['source']?.toString().trim() ?? '';
        if (source.isEmpty) continue;
        final resolution = resolveCanonicalLocalImage(
          sourceRoot: imageAssetRoot,
          source: source,
        );
        if (resolution.status != CanonicalLocalImageStatus.resolved) {
          reasons.add('Referenced image asset is unavailable: $source');
        }
      }
    }

    return LibraryDocumentValidationResult(
      passed: reasons.isEmpty,
      reasons: reasons,
    );
  }
}
