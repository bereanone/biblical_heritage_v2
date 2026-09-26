import 'dart:convert';

enum LibraryDocumentBlockType {
  heading,
  paragraph,
  quotation,
  poem,
  listItem,
  image,
  horizontalRule,
  unsupported,
}

LibraryDocumentBlockType libraryDocumentBlockTypeFromStorage(String value) {
  return LibraryDocumentBlockType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => LibraryDocumentBlockType.unsupported,
  );
}

class LibraryFormattedContent {
  const LibraryFormattedContent({
    required this.nodes,
    this.alignment,
    this.metadata = const <String, Object?>{},
  });

  static const int version = 1;
  final List<Map<String, Object?>> nodes;
  final String? alignment;
  final Map<String, Object?> metadata;

  String toJson() => jsonEncode(<String, Object?>{
    'version': version,
    if (alignment != null) 'alignment': alignment,
    if (metadata.isNotEmpty) 'metadata': metadata,
    'nodes': nodes,
  });

  factory LibraryFormattedContent.fromJson(String? source) {
    if (source == null || source.trim().isEmpty) {
      return const LibraryFormattedContent(nodes: <Map<String, Object?>>[]);
    }
    final value = jsonDecode(source) as Map<String, Object?>;
    if (value['version'] != version) {
      throw const FormatException('Unsupported formatted-content version.');
    }
    return LibraryFormattedContent(
      alignment: value['alignment']?.toString(),
      metadata: (value['metadata'] as Map<Object?, Object?>? ?? const {}).map(
        (key, value) => MapEntry('$key', value),
      ),
      nodes: (value['nodes'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map((node) => node.map((key, value) => MapEntry('$key', value)))
          .toList(growable: false),
    );
  }

  static LibraryFormattedContent plain(String text, {String? className}) =>
      LibraryFormattedContent(
        nodes: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'text',
            'text': text,
            if (className != null && className.isNotEmpty) 'class': className,
          },
        ],
      );
}

String libraryFormattedVisibleText(List<Map<String, Object?>> nodes) => nodes
    .map(
      (node) => node['type'] == 'line_break'
          ? '\n'
          : node['type'] == 'text'
          ? node['text']?.toString() ?? ''
          : '',
    )
    .join();

String normalizeLibraryInlineFidelityText(String value) => value
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceAllMapped(
      RegExp(r'\s+([,.;:!?)\]\}])'),
      (match) => match.group(1)!,
    );

bool libraryFormattedTextMatchesPlain({
  required String plainText,
  required List<Map<String, Object?>> nodes,
}) {
  if (nodes.any(
    (node) => node['type'] != 'text' && node['type'] != 'line_break',
  )) {
    return true;
  }
  return normalizeLibraryInlineFidelityText(plainText) ==
      normalizeLibraryInlineFidelityText(libraryFormattedVisibleText(nodes));
}

/// Restores source-confirmed whitespace omitted by legacy formatted nodes.
///
/// The whole-block [plainText] is the fidelity witness. No space is invented
/// when its non-whitespace characters differ from the formatted nodes, and a
/// source gap before closing punctuation remains suppressed. This preserves
/// intentional zero-space emphasis splits while making old generations read
/// like their intact searchable text.
List<Map<String, Object?>> restoreLibraryInlineBoundaryWhitespace({
  required String plainText,
  required List<Map<String, Object?>> nodes,
}) {
  if (nodes.isEmpty ||
      nodes.any(
        (node) => node['type'] != 'text' && node['type'] != 'line_break',
      )) {
    return nodes;
  }
  final plain = plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
  final visible = libraryFormattedVisibleText(
    nodes,
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  final plainSkeleton = plain.replaceAll(' ', '');
  if (plainSkeleton != visible.replaceAll(' ', '')) return nodes;

  final gaps = List<int>.filled(plainSkeleton.length + 1, 0);
  var skeletonOffset = 0;
  for (final codeUnit in plain.codeUnits) {
    final value = String.fromCharCode(codeUnit);
    if (value == ' ') {
      gaps[skeletonOffset] += 1;
    } else {
      skeletonOffset += 1;
    }
  }

  final restored = <Map<String, Object?>>[];
  var consumed = 0;
  for (var index = 0; index < nodes.length; index++) {
    final node = nodes[index];
    restored.add(node);
    if (node['type'] != 'text') continue;
    final text = node['text']?.toString() ?? '';
    consumed += text.replaceAll(RegExp(r'\s+'), '').length;
    if (index + 1 >= nodes.length) continue;
    final next = nodes[index + 1];
    if (next['type'] != 'text') continue;
    final nextText = next['text']?.toString() ?? '';
    if (text.isEmpty ||
        nextText.isEmpty ||
        RegExp(r'\s$').hasMatch(text) ||
        RegExp(r'^\s').hasMatch(nextText) ||
        consumed >= gaps.length ||
        gaps[consumed] == 0) {
      continue;
    }
    final nextCharacter = nextText.replaceFirst(RegExp(r'^\s+'), '')[0];
    if (RegExp(r'[,.;:!?)\]\}]').hasMatch(nextCharacter)) continue;
    restored.add(const <String, Object?>{'type': 'text', 'text': ' '});
  }
  return restored;
}

class LibraryDocumentBlock {
  const LibraryDocumentBlock({
    required this.id,
    required this.libraryItemId,
    required this.sectionId,
    required this.displayOrder,
    required this.blockType,
    required this.plainText,
    required this.formattedContent,
    required this.contentHash,
    this.sourceRefcode,
    this.sourceHref,
    this.sourceAnchor,
  });

  final String id;
  final String libraryItemId;
  final String sectionId;
  final int displayOrder;
  final LibraryDocumentBlockType blockType;
  final String plainText;
  final String formattedContent;
  final String? sourceRefcode;
  final String? sourceHref;
  final String? sourceAnchor;
  final String contentHash;

  bool get isHeading => blockType == LibraryDocumentBlockType.heading;
  LibraryFormattedContent get formatted =>
      LibraryFormattedContent.fromJson(formattedContent);

  /// Printed source pages are a fallback when the edition has no ref codes.
  /// A paragraph spanning a page break retains both endpoints.
  String? get pageReference {
    final metadata = formatted.metadata;
    final start = metadata['source_page_start'];
    final end = metadata['source_page_end'];
    if (start == null) return end == null ? null : 'p. $end (continued)';
    return end == null || start == end ? 'p. $start' : 'pp. $start–$end';
  }

  String? get visibleReference =>
      sourceRefcode?.trim().isNotEmpty == true ? sourceRefcode : pageReference;

  String? get headingRole =>
      isHeading ? formatted.metadata['heading_role']?.toString() : null;
  bool get isPrimaryChapterHeading => headingRole == 'chapter';

  factory LibraryDocumentBlock.fromRow(Map<String, Object?> row) =>
      LibraryDocumentBlock(
        id: row['id']!.toString(),
        libraryItemId: row['library_item_id']!.toString(),
        sectionId: row['section_id']!.toString(),
        displayOrder: (row['display_order'] as num).toInt(),
        blockType: libraryDocumentBlockTypeFromStorage(
          row['block_type']!.toString(),
        ),
        plainText: row['plain_text']?.toString() ?? '',
        formattedContent: row['formatted_content']?.toString() ?? '',
        sourceRefcode: row['source_refcode']?.toString(),
        sourceHref: row['source_href']?.toString(),
        sourceAnchor: row['source_anchor']?.toString(),
        contentHash: row['content_hash']?.toString() ?? '',
      );
}

class LibraryDocumentLocation {
  const LibraryDocumentLocation({
    required this.block,
    required this.sectionTitle,
    required this.heading,
    this.renderedHeading,
    this.secondaryHeading,
  });

  final LibraryDocumentBlock block;
  final String? sectionTitle;
  final LibraryDocumentBlock? heading;
  final LibraryDocumentBlock? renderedHeading;
  final LibraryDocumentBlock? secondaryHeading;
}
