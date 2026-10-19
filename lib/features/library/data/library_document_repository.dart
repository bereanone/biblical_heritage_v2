import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

import 'library_document_models.dart';
import 'library_search_navigation_target.dart';
import 'library_section_heuristics.dart';

/// Resolve an EPUB-relative link inside the archive, never a URL or disk path.
/// Fragment names are case-sensitive; stored source file paths are normalized.
({String path, String fragment})? resolveLibrarySourceLinkPath(
  String fromHref,
  String href,
) {
  try {
    final link = Uri.parse(href.trim());
    if (href.trim().isEmpty || link.hasScheme || link.hasAuthority) return null;
    final base = Uri.decodeComponent(
      Uri.parse(fromHref).path,
    ).replaceAll('\\', '/');
    final relative = Uri.decodeComponent(link.path).replaceAll('\\', '/');
    final path = p.posix.normalize(
      relative.isEmpty
          ? base
          : relative.startsWith('/')
          ? relative.substring(1)
          : p.posix.join(p.posix.dirname(base), relative),
    );
    if (path == '.' ||
        path == '..' ||
        path.startsWith('../') ||
        path.startsWith('/')) {
      return null;
    }
    return (
      path: path.toLowerCase(),
      fragment: Uri.decodeComponent(link.fragment),
    );
  } on FormatException {
    return null;
  }
}

/// A Contents node whose target has been resolved directly to one canonical
/// content block. Unlike the legacy EPUB navigation rows, this object cannot
/// exist without a real persisted destination.
class LibraryCanonicalNavigationDestination {
  const LibraryCanonicalNavigationDestination({
    required this.id,
    required this.parentId,
    required this.label,
    required this.depth,
    required this.block,
  });

  final String id;
  final String? parentId;
  final String label;
  final int depth;
  final LibraryDocumentBlock block;
}

class LibraryDocumentRepository {
  const LibraryDocumentRepository(this.db);
  final Database db;

  /// Select by explicit work and source location, never a title or ref prefix.
  /// Duplicate anchors are ambiguous and must not silently choose a paragraph.
  Future<LibraryDocumentBlock?> resolveSourceLink(
    String libraryItemId, {
    required String fromHref,
    required String href,
  }) async {
    final link = resolveLibrarySourceLinkPath(fromHref, href);
    if (link == null) return null;
    final rows = await db.query(
      'library_document_blocks',
      where: "library_item_id = ? AND LOWER(COALESCE(source_href, '')) = ?",
      whereArgs: [libraryItemId, link.path],
      orderBy: 'display_order',
    );
    final blocks = rows.map(LibraryDocumentBlock.fromRow).toList();
    if (link.fragment.isEmpty) return blocks.firstOrNull;
    final matches = blocks.where((block) {
      if (block.sourceAnchor == link.fragment) return true;
      final aliases = LibraryFormattedContent.fromJson(
        block.formattedContent,
      ).metadata['source_anchor_aliases'];
      return aliases is List && aliases.contains(link.fragment);
    }).toList();
    return matches.length == 1 ? matches.single : null;
  }

  Future<bool> isComplete(String libraryItemId) async {
    final rows = await db.query(
      'library_document_conversion',
      columns: const <String>['status'],
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    return rows.isNotEmpty &&
        rows.first['status'] == 'complete' &&
        await blockCount(libraryItemId) > 0;
  }

  Future<bool> isCurrentComplete(
    String libraryItemId, {
    required int canonicalizerVersion,
  }) async {
    final rows = await db.query(
      'library_document_conversion',
      columns: const <String>['status', 'canonicalizer_version'],
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    return rows.isNotEmpty &&
        rows.first['status'] == 'complete' &&
        rows.first['canonicalizer_version'] == canonicalizerVersion &&
        await blockCount(libraryItemId) > 0;
  }

  /// Updates only the catalog title/author for an already-imported item —
  /// never touches canonical content, `source_work_id`, or anything in the
  /// separate user database. `null` leaves a field unchanged.
  Future<void> updateCatalogMetadata(
    String libraryItemId, {
    String? title,
    String? author,
  }) async {
    final values = <String, Object?>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (title != null) 'title': title,
      if (author != null) 'author': author,
    };
    await db.update(
      'library_items',
      values,
      where: 'id = ?',
      whereArgs: <Object?>[libraryItemId],
    );
  }

  Future<int> blockCount(String libraryItemId) async => _firstIntValue(
    await db.rawQuery(
      'SELECT COUNT(*) FROM library_document_blocks WHERE library_item_id = ?',
      <Object?>[libraryItemId],
    ),
  );

  /// Older canonical generations can contain a print-layout page index as
  /// dozens or hundreds of numeric TOC list items. Besides being useless
  /// reader content, long zero-height runs of those rows can prevent the
  /// virtualized canonical list from mounting its initial chapter. Those
  /// books should use the legacy EPUB reader until they are recanonicalized.
  Future<bool> hasPathologicalNumericTocMarkers(
    String libraryItemId, {
    int threshold = 20,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS marker_count
      FROM library_document_blocks
      WHERE library_item_id = ?
        AND block_type = ?
        AND TRIM(plain_text) GLOB '[0-9]*'
        AND TRIM(plain_text) NOT GLOB '*[^0-9]*'
        AND LENGTH(TRIM(plain_text)) BETWEEN 1 AND 4
        AND (
          LOWER(COALESCE(source_href, '')) LIKE '%/toc.%'
          OR LOWER(COALESCE(source_href, '')) LIKE '%/nav.%'
        )
      ''',
      <Object?>[libraryItemId, LibraryDocumentBlockType.listItem.name],
    );
    final count = (rows.firstOrNull?['marker_count'] as num?)?.toInt() ?? 0;
    return count >= threshold;
  }

  Future<List<LibraryDocumentBlock>> loadWindow(
    String libraryItemId, {
    required int centerOrder,
    int radius = 50,
  }) async {
    final first = (centerOrder - radius).clamp(0, 1 << 30);
    final last = centerOrder + radius;
    final rows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND display_order BETWEEN ? AND ?',
      whereArgs: <Object?>[libraryItemId, first, last],
      orderBy: 'display_order ASC',
    );
    return rows.map(LibraryDocumentBlock.fromRow).toList(growable: false);
  }

  Future<List<LibraryDocumentBlock>> loadHeadings(String libraryItemId) async {
    final rows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>[
        libraryItemId,
        LibraryDocumentBlockType.heading.name,
      ],
      orderBy: 'display_order ASC',
    );
    return rows.map(LibraryDocumentBlock.fromRow).toList(growable: false);
  }

  /// Resolves EPUB TOC rows by their package-relative source identity.
  /// Explicit file-only links open that file's first block (scanned page EPUBs
  /// often have no headings). A broken fragment never falls back to the file,
  /// a matching label, or an unrelated heading.
  Future<List<LibraryCanonicalNavigationDestination>>
  loadCanonicalNavigationDestinations(String libraryItemId) async {
    final authoredTable = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'library_document_navigation'",
    );
    if (authoredTable.isNotEmpty) {
      final authored = await db.rawQuery(
        '''
        SELECT b.*, n.id AS nav_id, n.parent_id AS nav_parent_id,
               n.label AS nav_label, n.depth AS nav_depth, n.source_anchor AS nav_anchor
        FROM library_document_navigation n
        JOIN library_document_blocks b ON b.id = n.target_block_id
          AND b.library_item_id = n.library_item_id
        WHERE n.library_item_id = ?
        ORDER BY n.display_order
      ''',
        [libraryItemId],
      );
      if (authored.isNotEmpty &&
          (authored.length > 1 ||
              (authored.single['nav_anchor']?.toString() ?? '').isNotEmpty)) {
        final ids = authored.map((row) => row['nav_id'].toString()).toSet();
        final authoredHeadings = await loadHeadings(libraryItemId);
        return authored
            .map((row) {
              final parent = row['nav_parent_id']?.toString();
              var target = LibraryDocumentBlock.fromRow(row);
              // A file-only authored destination may precede the chapter's
              // actual heading (for example, editorial epigraphs). Preserve
              // explicit fragments; refine only a unique same-file heading.
              if ((row['nav_anchor']?.toString() ?? '').isEmpty &&
                  !target.isHeading) {
                final matching = authoredHeadings
                    .where(
                      (heading) =>
                          _canonicalNavigationPath(heading.sourceHref) ==
                              _canonicalNavigationPath(target.sourceHref) &&
                          _normalizedCanonicalOpeningLabel(heading.plainText) ==
                              _normalizedCanonicalOpeningLabel(
                                row['nav_label'].toString(),
                              ),
                    )
                    .toList(growable: false);
                if (matching.length == 1) target = matching.single;
              }
              return LibraryCanonicalNavigationDestination(
                id: row['nav_id'].toString(),
                parentId: ids.contains(parent) ? parent : null,
                label: row['nav_label'].toString(),
                depth: parent != null && !ids.contains(parent)
                    ? 0
                    : (row['nav_depth'] as num).toInt(),
                block: target,
              );
            })
            .toList(growable: false);
      }
    }
    final rows = await db.query(
      'library_navigation_items',
      columns: const <String>[
        'id',
        'parent_id',
        'label',
        'href',
        'anchor_id',
        'depth',
      ],
      where: 'library_item_id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[libraryItemId],
      orderBy: 'sort_order ASC',
    );
    final fileStarts = <String, LibraryDocumentBlock>{};
    if (rows.any((row) => (row['anchor_id']?.toString() ?? '').isEmpty)) {
      final blocks = await db.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: [libraryItemId],
        orderBy: 'display_order ASC',
      );
      for (final row in blocks) {
        final block = LibraryDocumentBlock.fromRow(row);
        final path = _canonicalNavigationPath(block.sourceHref);
        if (path.isNotEmpty) fileStarts.putIfAbsent(path, () => block);
      }
    }
    final headings = await loadHeadings(libraryItemId);
    final headingByTarget = <String, LibraryDocumentBlock>{};
    final headingsByAnchor = <String, List<LibraryDocumentBlock>>{};
    for (final heading in headings) {
      final href = _canonicalNavigationPath(heading.sourceHref);
      final anchor = heading.sourceAnchor?.trim();
      if (href.isEmpty || anchor == null || anchor.isEmpty) continue;
      headingByTarget.putIfAbsent('$href#$anchor', () => heading);
      headingsByAnchor
          .putIfAbsent(anchor, () => <LibraryDocumentBlock>[])
          .add(heading);
    }
    final result = <LibraryCanonicalNavigationDestination>[];
    final resolvedIds = <String>{};
    for (final row in rows) {
      final href = _canonicalNavigationPath(row['href']?.toString());
      final anchor = row['anchor_id']?.toString().trim() ?? '';
      if (href.isEmpty) continue;
      // Some producers write nav hrefs relative to the package while their
      // OPF/spine resolution stores a different-but-equivalent path prefix.
      // A fragment is still an exact canonical identity when unique within
      // the publication; ambiguity is rejected, never resolved by position.
      final byAnchor = headingsByAnchor[anchor] ?? const [];
      final heading = anchor.isEmpty
          ? fileStarts[href]
          : headingByTarget['$href#$anchor'] ??
                (byAnchor.length == 1 ? byAnchor.single : null);
      if (heading == null) continue;
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      resolvedIds.add(id);
      result.add(
        LibraryCanonicalNavigationDestination(
          id: id,
          parentId: row['parent_id']?.toString(),
          label: row['label']?.toString() ?? heading.plainText,
          depth: (row['depth'] as num?)?.toInt() ?? 0,
          block: heading,
        ),
      );
    }
    // Preserve a usable tree when an invalid parent was omitted: promote the
    // valid child rather than retaining a dangling hierarchy reference.
    return result
        .map(
          (entry) =>
              entry.parentId == null || resolvedIds.contains(entry.parentId)
              ? entry
              : LibraryCanonicalNavigationDestination(
                  id: entry.id,
                  parentId: null,
                  label: entry.label,
                  depth: 0,
                  block: entry.block,
                ),
        )
        .toList(growable: false);
  }

  Future<List<LibraryDocumentBlock>> searchCurrentBook(
    String libraryItemId,
    String query,
  ) async {
    final term = query.trim();
    if (term.isEmpty) return const <LibraryDocumentBlock>[];
    final escaped = term
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await db.rawQuery(
      '''
      SELECT * FROM library_document_blocks
      WHERE library_item_id = ?
        AND plain_text LIKE ? ESCAPE '\\'
      ORDER BY display_order ASC
      ''',
      <Object?>[libraryItemId, '%$escaped%'],
    );
    return rows.map(LibraryDocumentBlock.fromRow).toList(growable: false);
  }

  Future<int?> displayOrderForBlock(
    String libraryItemId,
    String blockId,
  ) async {
    final rows = await db.query(
      'library_document_blocks',
      columns: const <String>['display_order'],
      where: 'library_item_id = ? AND id = ?',
      whereArgs: <Object?>[libraryItemId, blockId],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['display_order'] as num).toInt();
  }

  /// Returns the first substantive canonical block while leaving all front
  /// matter in the document and Contents tree.
  Future<int?> openingDisplayOrder(
    String libraryItemId, {
    String? bookTitle,
  }) async {
    final headingRows = await db.query(
      'library_document_blocks',
      columns: const <String>[
        'display_order',
        'plain_text',
        'source_href',
        'formatted_content',
      ],
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>[
        libraryItemId,
        LibraryDocumentBlockType.heading.name,
      ],
      orderBy: 'display_order ASC',
    );
    // First inspect the complete heading sequence for an authored body start.
    // Do not let an earlier poem/subtitle whose CSS happened to infer a
    // chapter role hide a later explicit "Chapter 1" heading.
    for (final heading in headingRows) {
      final label = heading['plain_text']?.toString() ?? '';
      final href = heading['source_href']?.toString() ?? '';
      if (libraryIsFrontMatterOpeningLabel(label) ||
          libraryIsFrontMatterOpeningLabel(href)) {
        continue;
      }
      if (_isFirstCanonicalBodyLabel(label)) {
        return (heading['display_order'] as num?)?.toInt();
      }
    }
    // Only after every explicit body-start heading has been considered may
    // an inferred chapter role act as the fallback for books without a
    // conventional Chapter 1 label.
    for (final heading in headingRows) {
      final label = heading['plain_text']?.toString() ?? '';
      final href = heading['source_href']?.toString() ?? '';
      if (libraryIsFrontMatterOpeningLabel(label) ||
          libraryIsFrontMatterOpeningLabel(href)) {
        continue;
      }
      final formatted = LibraryFormattedContent.fromJson(
        heading['formatted_content']?.toString(),
      );
      if (formatted.metadata['heading_role'] == 'chapter') {
        return (heading['display_order'] as num?)?.toInt();
      }
    }

    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.title, s.source_href, MIN(b.display_order) AS first_order
      FROM library_document_sections s
      JOIN library_document_blocks b
        ON b.library_item_id = s.library_item_id AND b.section_id = s.id
      WHERE s.library_item_id = ?
      GROUP BY s.id, s.display_order
      ORDER BY s.display_order ASC
      ''',
      <Object?>[libraryItemId],
    );
    // Some EGW EPUBs (including editions of Acts of the Apostles) put the
    // chapter number in the section/TOC title while the first heading inside
    // the XHTML contains only the chapter's descriptive title. Resolve that
    // structural Chapter 1 identity before considering any readable-looking
    // title or introductory section.
    for (final row in rows) {
      final title = row['title']?.toString() ?? '';
      if (_isFirstCanonicalBodyLabel(title)) {
        return (row['first_order'] as num?)?.toInt();
      }
    }
    for (final row in rows) {
      final sectionId = row['id']?.toString() ?? '';
      final title = row['title']?.toString() ?? '';
      final href = row['source_href']?.toString() ?? '';
      if (libraryIsFrontMatterOpeningLabel(title) ||
          libraryIsFrontMatterOpeningLabel(href)) {
        continue;
      }
      if (_normalizedCanonicalOpeningLabel(title) ==
          _normalizedCanonicalOpeningLabel(bookTitle ?? '')) {
        continue;
      }
      final blockRows = await db.query(
        'library_document_blocks',
        columns: const <String>['display_order', 'block_type', 'plain_text'],
        where: 'library_item_id = ? AND section_id = ?',
        whereArgs: <Object?>[libraryItemId, sectionId],
        orderBy: 'display_order ASC',
      );
      final paragraphs = blockRows
          .map((block) => block['plain_text']?.toString() ?? '')
          .toList(growable: false);
      if (libraryIsMeaningfulReadingSection(
        title: title,
        href: href,
        paragraphs: paragraphs,
        bookTitle: bookTitle,
      )) {
        for (final block in blockRows) {
          if (block['block_type'] != LibraryDocumentBlockType.heading.name) {
            continue;
          }
          final heading = block['plain_text']?.toString() ?? '';
          if (!libraryIsFrontMatterOpeningLabel(heading)) {
            return (block['display_order'] as num?)?.toInt();
          }
        }
        return (row['first_order'] as num?)?.toInt();
      }
    }
    return null;
  }

  static String _normalizedCanonicalOpeningLabel(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static bool _isFirstCanonicalBodyLabel(String value) => RegExp(
    r'^(?:(?:chapter|chap|article|sermon|part)\s*)?(?:1|i|one)(?:\s|$)',
  ).hasMatch(_normalizedCanonicalOpeningLabel(value));

  Future<bool> containsDisplayOrder(
    String libraryItemId,
    int displayOrder,
  ) async {
    final rows = await db.query(
      'library_document_blocks',
      columns: const <String>['id'],
      where: 'library_item_id = ? AND display_order = ?',
      whereArgs: <Object?>[libraryItemId, displayOrder],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int?> displayOrderForBlockId(String itemId, String blockId) async {
    final rows = await db.query(
      'library_document_blocks',
      columns: const ['display_order'],
      where: 'library_item_id = ? AND id = ?',
      whereArgs: [itemId, blockId],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.single['display_order'] as num).toInt();
  }

  Future<int?> displayOrderForSearchTarget(
    LibrarySearchNavigationTarget target,
  ) async {
    final canonicalId = target.canonicalBlockId;
    if (canonicalId != null) {
      final rows = await db.query(
        'library_document_blocks',
        columns: const ['display_order', 'content_hash'],
        where: 'library_item_id = ? AND id = ?',
        whereArgs: [target.libraryItemId, canonicalId],
        limit: 1,
      );
      if (rows.isEmpty ||
          (target.canonicalContentHash != null &&
              rows.single['content_hash'] != target.canonicalContentHash)) {
        return null;
      }
      return (rows.single['display_order'] as num).toInt();
    }
    final rows = await db.rawQuery(
      '''
      SELECT b.display_order, b.block_type, b.plain_text
      FROM library_block_source_map sm
      INNER JOIN library_document_blocks b
        ON b.library_item_id = sm.library_item_id
        AND b.id = sm.block_id
      WHERE sm.library_item_id = ?
        AND LOWER(COALESCE(sm.source_href, '')) = LOWER(?)
        AND sm.legacy_paragraph_index = ?
      ''',
      <Object?>[
        target.libraryItemId,
        target.href,
        target.paragraphOnSection ?? target.paragraphIndex,
      ],
    );
    if (rows.isEmpty) return null;
    if (rows.length == 1) {
      return (rows.single['display_order'] as num?)?.toInt();
    }

    // Some generated source maps assign the same legacy paragraph index to
    // the paragraph and to the heading immediately following it. A Bible
    // commentary hit refers to the paragraph, never that adjacent heading.
    // Prefer unique textual evidence first, then the unique non-heading row;
    // remain unresolved rather than opening unrelated front matter.
    final evidence = _normalizedSearchEvidence(
      target.matchedText ?? target.stableSourceReference ?? '',
    );
    if (evidence.length >= 24) {
      final textMatches = rows.where((row) {
        final text = _normalizedSearchEvidence(
          row['plain_text']?.toString() ?? '',
        );
        return text == evidence ||
            text.contains(evidence) ||
            evidence.contains(text);
      }).toList();
      if (textMatches.length == 1) {
        return (textMatches.single['display_order'] as num?)?.toInt();
      }
    }
    final paragraphs = rows
        .where(
          (row) => row['block_type'] != LibraryDocumentBlockType.heading.name,
        )
        .toList();
    return paragraphs.length == 1
        ? (paragraphs.single['display_order'] as num?)?.toInt()
        : null;
  }

  static String _normalizedSearchEvidence(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]+'), '')
      .trim();

  Future<LibraryDocumentLocation?> resolveLocation(
    String libraryItemId,
    int displayOrder,
  ) async {
    final blocks = await db.rawQuery(
      '''
      SELECT b.*, s.title AS section_title
      FROM library_document_blocks b
      JOIN library_document_sections s ON s.id = b.section_id
      WHERE b.library_item_id = ? AND b.display_order = ? LIMIT 1
    ''',
      <Object?>[libraryItemId, displayOrder],
    );
    if (blocks.isEmpty) return null;
    final block = LibraryDocumentBlock.fromRow(blocks.first);
    final headingRows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND display_order <= ? AND block_type = ?',
      whereArgs: <Object?>[
        libraryItemId,
        displayOrder,
        LibraryDocumentBlockType.heading.name,
      ],
      orderBy: 'display_order DESC',
      limit: 16,
    );
    final headings = headingRows.map(LibraryDocumentBlock.fromRow).toList();
    final primaryRows = await db.rawQuery(
      '''
      SELECT * FROM library_document_blocks
      WHERE library_item_id = ? AND display_order <= ? AND block_type = ?
        AND json_extract(formatted_content, '\$.metadata.heading_role') = 'chapter'
      ORDER BY display_order DESC LIMIT 1
      ''',
      <Object?>[
        libraryItemId,
        displayOrder,
        LibraryDocumentBlockType.heading.name,
      ],
    );
    final selectedHeading = primaryRows.isNotEmpty
        ? LibraryDocumentBlock.fromRow(primaryRows.first)
        : headings.firstOrNull;
    final secondary = headings.where(
      (heading) =>
          heading.headingRole == 'section' || heading.headingRole == 'minor',
    );
    return LibraryDocumentLocation(
      block: block,
      sectionTitle: blocks.first['section_title']?.toString(),
      heading: selectedHeading,
      renderedHeading: headings.firstOrNull,
      secondaryHeading: secondary.firstOrNull,
    );
  }
}

String _canonicalNavigationPath(String? value) {
  final path = (value ?? '').trim().split('#').first.replaceAll('\\', '/');
  if (path.isEmpty) return '';
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return parts.join('/').toLowerCase();
}

int _firstIntValue(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? 0 : (rows.first.values.first as num?)?.toInt() ?? 0;
