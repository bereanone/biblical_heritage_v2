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
