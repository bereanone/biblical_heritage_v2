import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utilities/data/pioneer_html_capture_folder_scanner.dart';
import 'library_document_models.dart';

class LibraryCanonicalSourceSection {
  const LibraryCanonicalSourceSection({
    required this.href,
    required this.title,
    required this.html,
  });

  final String href;
  final String title;
  final String html;
}

class LibraryDocumentCanonicalizationResult {
  const LibraryDocumentCanonicalizationResult({
    required this.skipped,
    required this.blockCount,
    required this.sourceHash,
  });

  final bool skipped;
  final int blockCount;
  final String sourceHash;
}

typedef LibraryCanonicalizationFailureHook = void Function(int blockIndex);

class LibraryDocumentCanonicalizer {
  const LibraryDocumentCanonicalizer({this.failureHook});

  static const int version = 3;
  final LibraryCanonicalizationFailureHook? failureHook;

  Future<LibraryDocumentCanonicalizationResult> canonicalize({
    required Database db,
    required String libraryItemId,
    required File source,
  }) async {
    final bytes = await source.readAsBytes();
    final sourceHash = sha256.convert(bytes).toString();
    final current = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    if (current.isNotEmpty &&
        current.first['status'] == 'complete' &&
        current.first['canonicalizer_version'] == version &&
        current.first['source_hash'] == sourceHash) {
      final count = _firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM library_document_blocks WHERE library_item_id = ?',
          <Object?>[libraryItemId],
        ),
      );
      return LibraryDocumentCanonicalizationResult(
        skipped: true,
        blockCount: count,
        sourceHash: sourceHash,
      );
    }

    try {
      final sections = _readSections(source.path, bytes);
      var written = 0;
      await db.transaction((txn) async {
        await txn.insert(
          'library_document_conversion',
          <String, Object?>{
            'library_item_id': libraryItemId,
            'canonicalizer_version': version,
            'source_hash': sourceHash,
            'status': 'converting',
            'completed_at': null,
            'error_message': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.delete(
          'library_block_source_map',
          where: 'library_item_id = ?',
          whereArgs: <Object?>[libraryItemId],
        );
        await txn.delete(
          'library_document_blocks',
          where: 'library_item_id = ?',
          whereArgs: <Object?>[libraryItemId],
        );
        await txn.delete(
          'library_document_sections',
          where: 'library_item_id = ?',
          whereArgs: <Object?>[libraryItemId],
        );

        var globalOrder = 0;
        for (
          var sectionIndex = 0;
          sectionIndex < sections.length;
          sectionIndex++
        ) {
          final section = sections[sectionIndex];
          final normalizedHref = normalizeLibrarySourceHref(section.href);
          final sectionId = _stableId(<String>[
            'section',
            libraryItemId,
            normalizedHref,
            '$sectionIndex',
          ]);
          final parsed = _parseHtmlBlocks(section.html);
          await txn.insert('library_document_sections', <String, Object?>{
            'id': sectionId,
            'library_item_id': libraryItemId,
            'display_order': sectionIndex,
            'title': section.title,
            'source_href': normalizedHref,
            'content_hash': sha256
                .convert(utf8.encode(section.html))
                .toString(),
          });
          var paragraphOrdinal = 0;
          for (var blockIndex = 0; blockIndex < parsed.length; blockIndex++) {
            failureHook?.call(written);
            final block = parsed[blockIndex];
            if (block.type == LibraryDocumentBlockType.paragraph) {
              paragraphOrdinal++;
            }
            final blockId = stableLibraryDocumentBlockId(
              libraryItemId: libraryItemId,
              sourceHref: normalizedHref,
              sourceAnchor: block.anchor,
              blockType: block.type,
              sourceBlockOrdinal: blockIndex,
            );
            final contentHash = sha256
                .convert(
                  utf8.encode(
                    '${block.type.name}\u0000${block.text}\u0000${block.formatted.toJson()}',
                  ),
                )
                .toString();
            await txn.insert('library_document_blocks', <String, Object?>{
              'id': blockId,
              'library_item_id': libraryItemId,
              'section_id': sectionId,
              'display_order': globalOrder++,
              'block_type': block.type.name,
              'plain_text': block.text,
              'formatted_content': block.formatted.toJson(),
              'source_refcode': block.refcode,
              'source_href': normalizedHref,
              'source_anchor': block.anchor,
              'content_hash': contentHash,
            });
            await txn.insert('library_block_source_map', <String, Object?>{
              'library_item_id': libraryItemId,
              'block_id': blockId,
              'source_href': normalizedHref,
              'legacy_block_index': blockIndex,
              'legacy_paragraph_index': paragraphOrdinal == 0
                  ? null
                  : paragraphOrdinal,
              'source_anchor': block.anchor,
            });
            written++;
          }
        }
        await txn.update(
          'library_document_conversion',
          <String, Object?>{
            'status': 'complete',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
            'error_message': null,
          },
          where: 'library_item_id = ?',
          whereArgs: <Object?>[libraryItemId],
        );
      });
      return LibraryDocumentCanonicalizationResult(
        skipped: false,
        blockCount: written,
        sourceHash: sourceHash,
      );
    } catch (error) {
      await db.insert(
        'library_document_conversion',
        <String, Object?>{
          'library_item_id': libraryItemId,
          'canonicalizer_version': version,
          'source_hash': sourceHash,
          'status': 'failed',
          'completed_at': null,
          'error_message': error.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      rethrow;
    }
  }

  List<LibraryCanonicalSourceSection> _readSections(
    String path,
    List<int> bytes,
  ) {
    if (p.extension(path).toLowerCase() != '.epub') {
      return <LibraryCanonicalSourceSection>[
        LibraryCanonicalSourceSection(
          href: p.basename(path),
          title: p.basenameWithoutExtension(path),
          html: utf8.decode(bytes, allowMalformed: true),
        ),
      ];
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final entries =
        archive.files
            .where(
              (entry) =>
                  entry.isFile &&
                  RegExp(
                    r'\.(xhtml|html|htm)$',
                    caseSensitive: false,
                  ).hasMatch(entry.name),
            )
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));
    return entries
        .map((entry) {
          final html = utf8.decode(
            entry.content as List<int>,
            allowMalformed: true,
          );
          final title =
              RegExp(
                r'<title\b[^>]*>(.*?)</title>',
                caseSensitive: false,
                dotAll: true,
              ).firstMatch(html)?.group(1) ??
              p.basenameWithoutExtension(entry.name);
          return LibraryCanonicalSourceSection(
            href: entry.name,
            title: _plain(title),
            html: html,
          );
        })
        .toList(growable: false);
  }
}

class _ParsedCanonicalBlock {
  const _ParsedCanonicalBlock({
    required this.type,
    required this.text,
    required this.formatted,
    this.anchor,
    this.refcode,
  });
  final LibraryDocumentBlockType type;
  final String text;
  final LibraryFormattedContent formatted;
  final String? anchor;
  final String? refcode;

  _ParsedCanonicalBlock withRefcode(String value) => _ParsedCanonicalBlock(
    type: type,
    text: text,
    formatted: formatted,
    anchor: anchor,
    refcode: value,
  );
}

List<_ParsedCanonicalBlock> _parseHtmlBlocks(String html) {
  if (RegExp(
    r'''class\s*=\s*["'][^"']*\bclip-text\b''',
    caseSensitive: false,
  ).hasMatch(html)) {
    final captured = _parseCapturedEgwBlocks(html);
    if (captured.isNotEmpty) return captured;
  }
  return _parseSemanticHtmlBlocks(html);
}

List<_ParsedCanonicalBlock> _parseCapturedEgwBlocks(String html) {
  final extraction = const EgwHtmlCaptureExtractor().extract(html);
  if (extraction.text.trim().isEmpty) return const <_ParsedCanonicalBlock>[];
  final abbreviation = extraction.detectedAbbreviation?.trim() ?? '';
  if (abbreviation.isEmpty) return const <_ParsedCanonicalBlock>[];

  final blocks = <_ParsedCanonicalBlock>[];
  final imagePattern = RegExp(
    r'<img\b([^>]*)>',
    caseSensitive: false,
    dotAll: true,
  );
  for (final match in imagePattern.allMatches(html)) {
    final attrs = match.group(1) ?? '';
    final alt = _attribute(attrs, 'alt') ?? '';
    blocks.add(
      _ParsedCanonicalBlock(
        type: LibraryDocumentBlockType.image,
        text: alt,
        formatted: LibraryFormattedContent(
          nodes: <Map<String, Object?>>[
            <String, Object?>{
              'type': 'image',
              'source': _attribute(attrs, 'src') ?? '',
              'alt': alt,
            },
          ],
        ),
      ),
    );
  }

  final lines = extraction.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  final pagePattern = RegExp(
    '^${RegExp.escape(abbreviation)} \\d+'
    r'$',
  );
  final refPattern = RegExp(
    '^${RegExp.escape(abbreviation)} \\d+\\.\\d+'
    r'$',
  );
  final primaryChapterLineIndexes = <int>{};
  final chapterPattern = RegExp(
    r'^CHAPTER\s+([IVXLCDM]+)\.\s+\S',
    caseSensitive: false,
  );
  var expectedChapter = 1;
  for (var index = 0; index < lines.length; index++) {
    final match = chapterPattern.firstMatch(lines[index]);
    if (match == null) continue;
    final number = _romanNumeralValue(match.group(1)!);
    if (number == expectedChapter) {
      primaryChapterLineIndexes.add(index);
      expectedChapter++;
    }
  }
  final firstChapterIndex = primaryChapterLineIndexes.isEmpty
      ? lines.length
      : primaryChapterLineIndexes.first;
  final lastChapterIndex = primaryChapterLineIndexes.isEmpty
      ? -1
      : primaryChapterLineIndexes.last;
  final firstRepeatedChapterIndex = List<int>.generate(lines.length, (i) => i)
      .where(
        (index) =>
            index > lastChapterIndex && chapterPattern.hasMatch(lines[index]),
      )
      .firstOrNull;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (pagePattern.hasMatch(line)) continue;
    if (refPattern.hasMatch(line)) {
      if (blocks.isNotEmpty &&
          blocks.last.type == LibraryDocumentBlockType.paragraph &&
          blocks.last.refcode == null) {
        blocks[blocks.length - 1] = blocks.last.withRefcode(line);
      }
      continue;
    }
    final next = index + 1 < lines.length ? lines[index + 1] : '';
    final previous = index > 0 ? lines[index - 1] : '';
    final afterNext = index + 2 < lines.length ? lines[index + 2] : '';
    final followedByPage = pagePattern.hasMatch(next);
    final isPrimaryChapter = primaryChapterLineIndexes.contains(index);
    final isChapterLike = chapterPattern.hasMatch(line);
    final isolatedBetweenReferencedProse =
        refPattern.hasMatch(previous) && refPattern.hasMatch(afterNext);
    final introducesReferencedProse =
        !pagePattern.hasMatch(next) &&
        !refPattern.hasMatch(next) &&
        refPattern.hasMatch(afterNext);
    final immediatelyAfterPrimaryChapter =
        index > 0 && primaryChapterLineIndexes.contains(index - 1);
    var previousReadableIndex = index - 1;
    while (previousReadableIndex >= 0 &&
        (pagePattern.hasMatch(lines[previousReadableIndex]) ||
            refPattern.hasMatch(lines[previousReadableIndex]))) {
      previousReadableIndex--;
    }
    final followsPrimaryChapter = primaryChapterLineIndexes.contains(
      previousReadableIndex,
    );
    final frontMatterPosition = index < firstChapterIndex;
    final postBodySectionPosition =
        index > lastChapterIndex &&
        (firstRepeatedChapterIndex == null ||
            index < firstRepeatedChapterIndex);
    final hasCombinedWeakSignals =
        line.length <= 120 &&
        line == line.toUpperCase() &&
        (followedByPage ||
            isolatedBetweenReferencedProse ||
            introducesReferencedProse ||
            immediatelyAfterPrimaryChapter ||
            followsPrimaryChapter ||
            frontMatterPosition ||
            postBodySectionPosition);
    final isStructuralHeading =
        isPrimaryChapter || (hasCombinedWeakSignals && !isChapterLike);
    final headingRole = isPrimaryChapter
        ? 'chapter'
        : index < firstChapterIndex
        ? 'front_matter'
        : index > lastChapterIndex
        ? 'minor'
        : 'section';
    final reason = isPrimaryChapter
        ? 'monotonic numbered chapter sequence'
        : followedByPage
        ? 'page boundary + uppercase + short line'
        : immediatelyAfterPrimaryChapter
        ? 'chapter adjacency + uppercase + short line'
        : followsPrimaryChapter
        ? 'nearest readable predecessor is chapter + uppercase + short line'
        : frontMatterPosition
        ? 'front-matter position + uppercase + short line'
        : postBodySectionPosition
        ? 'post-body pre-study position + uppercase + short line'
        : introducesReferencedProse
        ? 'introduces referenced prose + uppercase + short line'
        : 'isolated between referenced prose + uppercase + short line';
    blocks.add(
      _ParsedCanonicalBlock(
        type: isStructuralHeading
            ? LibraryDocumentBlockType.heading
            : LibraryDocumentBlockType.paragraph,
        text: line,
        formatted: LibraryFormattedContent(
          nodes: <Map<String, Object?>>[
            <String, Object?>{
              'type': 'text',
              'text': line,
              'class': isStructuralHeading ? 'capture-heading' : 'capture-text',
            },
          ],
          metadata: <String, Object?>{
            'source_tag': 'p',
            'source_class': 'clip-text',
            'source_ordinal': index,
            'classification_reason': isStructuralHeading
                ? reason
                : isChapterLike
                ? 'non-monotonic repeated chapter label retained as text'
                : 'readable capture text',
            if (isStructuralHeading) 'heading_role': headingRole,
          },
        ),
      ),
    );
  }
  return blocks;
}

int _romanNumeralValue(String source) {
  const values = <String, int>{
    'I': 1,
    'V': 5,
    'X': 10,
    'L': 50,
    'C': 100,
    'D': 500,
    'M': 1000,
  };
  var result = 0;
  var previous = 0;
  for (final rune in source.toUpperCase().runes.toList().reversed) {
    final value = values[String.fromCharCode(rune)] ?? 0;
    if (value < previous) {
      result -= value;
    } else {
      result += value;
      previous = value;
    }
  }
  return result;
}

List<_ParsedCanonicalBlock> _parseSemanticHtmlBlocks(String html) {
  final pattern = RegExp(
    r'<(h[1-6]|p|blockquote|pre|li|img|hr)\b([^>]*)>(?:(.*?)</\1\s*>)?',
    caseSensitive: false,
    dotAll: true,
  );
  final result = <_ParsedCanonicalBlock>[];
  for (final match in pattern.allMatches(html)) {
    final tag = match.group(1)!.toLowerCase();
    final attrs = match.group(2) ?? '';
    final inner = match.group(3) ?? '';
    final type = switch (tag) {
      'blockquote' => LibraryDocumentBlockType.quotation,
      'pre' => LibraryDocumentBlockType.poem,
      'li' => LibraryDocumentBlockType.listItem,
      'img' => LibraryDocumentBlockType.image,
      'hr' => LibraryDocumentBlockType.horizontalRule,
      _ when tag.startsWith('h') => LibraryDocumentBlockType.heading,
      _ => LibraryDocumentBlockType.paragraph,
    };
    final text = type == LibraryDocumentBlockType.image
        ? (_attribute(attrs, 'alt') ?? '')
        : _plain(inner);
    if (text.isEmpty &&
        type != LibraryDocumentBlockType.image &&
        type != LibraryDocumentBlockType.horizontalRule) {
      continue;
    }
    final className = _attribute(attrs, 'class');
    final alignment = _alignment(attrs, className);
    final nodes = type == LibraryDocumentBlockType.image
        ? <Map<String, Object?>>[
            <String, Object?>{
              'type': 'image',
              'source': _attribute(attrs, 'src') ?? '',
              'alt': text,
            },
          ]
        : _inlineNodes(inner, className: className);
    final headingRole = switch (tag) {
      'h1' => 'book_title',
      'h2' => 'chapter',
      'h3' => 'section',
      'h4' || 'h5' || 'h6' => 'minor',
      _ => null,
    };
    result.add(
      _ParsedCanonicalBlock(
        type: type,
        text: text,
        formatted: LibraryFormattedContent(
          nodes: nodes,
          alignment: alignment,
          metadata: (<String, Object?>{
            'source_tag': tag,
            'source_class': className,
            'classification_reason': tag.startsWith('h')
                ? 'explicit semantic heading element'
                : 'semantic HTML block',
            'heading_role': headingRole,
          }..removeWhere((_, value) => value == null)),
        ),
        anchor: _attribute(attrs, 'id'),
        refcode: _attribute(attrs, 'data-refcode'),
      ),
    );
  }
  if (result.isEmpty) {
    final text = _plain(html);
    if (text.isNotEmpty) {
      result.add(
        _ParsedCanonicalBlock(
          type: LibraryDocumentBlockType.paragraph,
          text: text,
          formatted: LibraryFormattedContent.plain(text),
        ),
      );
    }
  }
  return result;
}

/// Normalization is intentionally locator-only: backslashes become slashes,
/// query/fragment parts are removed, dot segments are collapsed, leading
/// slashes are removed, and ASCII case is folded. Text never participates.
String normalizeLibrarySourceHref(String sourceHref) {
  var value = sourceHref.trim().replaceAll('\\', '/');
  value = value.split(RegExp(r'[?#]')).first;
  value = p.posix.normalize(value);
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  return value.toLowerCase();
}

/// Stable identity is SHA-256 over version, work, normalized locator,
/// optional source anchor, semantic type, and zero-based source ordinal.
/// Content is deliberately excluded and is tracked by content_hash instead.
String stableLibraryDocumentBlockId({
  required String libraryItemId,
  required String sourceHref,
  required String? sourceAnchor,
  required LibraryDocumentBlockType blockType,
  required int sourceBlockOrdinal,
}) =>
    'ldb_${_stableId(<String>['block-v1', libraryItemId.trim(), normalizeLibrarySourceHref(sourceHref), sourceAnchor?.trim() ?? '', blockType.name, '$sourceBlockOrdinal'])}';

String _stableId(List<String> parts) =>
    sha256.convert(utf8.encode(parts.join('\u0000'))).toString();
int _firstIntValue(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? 0 : (rows.first.values.first as num?)?.toInt() ?? 0;
String? _attribute(String attrs, String name) => RegExp(
  '''\\b$name\\s*=\\s*["']([^"']*)["']''',
  caseSensitive: false,
).firstMatch(attrs)?.group(1);
String? _alignment(String attrs, String? className) {
  final value = '${_attribute(attrs, 'style') ?? ''} ${className ?? ''}'
      .toLowerCase();
  for (final alignment in <String>['center', 'right', 'justify', 'left']) {
    if (value.contains(alignment)) return alignment;
  }
  return null;
}

String _plain(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ')
    .replaceAll(RegExp(r' *\n *'), '\n')
    .trim();

List<Map<String, Object?>> _inlineNodes(String html, {String? className}) {
  final nodes = <Map<String, Object?>>[];
  final tokens = RegExp(r'(<[^>]+>|[^<]+)', dotAll: true).allMatches(html);
  final styles = <String>[];
  String? linkHref;
  for (final token in tokens) {
    final value = token.group(0)!;
    if (value.startsWith('<')) {
      final lower = value.toLowerCase();
      if (RegExp(r'^<br\b').hasMatch(lower)) {
        nodes.add(<String, Object?>{'type': 'line_break'});
        continue;
      }
      if (lower.startsWith('</a')) {
        linkHref = null;
        continue;
      }
      if (lower.startsWith('</')) {
        if (styles.isNotEmpty) styles.removeLast();
        continue;
      }
      final tag = RegExp(r'^<([a-z0-9]+)').firstMatch(lower)?.group(1);
      if (tag == 'a') {
        linkHref = _attribute(value, 'href');
        continue;
      }
      final style = switch (tag) {
        'b' || 'strong' => 'bold',
        'i' || 'em' => 'italic',
        'u' => 'underline',
        'sup' => 'superscript',
        'sub' => 'subscript',
        _ => null,
      };
      if (style != null) styles.add(style);
      continue;
    }
    final text = _plain(value);
    if (text.isEmpty) continue;
    nodes.add(<String, Object?>{
      'type': 'text',
      'text': text,
      if (styles.isNotEmpty) 'marks': List<String>.of(styles),
      if (className != null && className.isNotEmpty) 'class': className,
      if (linkHref != null && linkHref.isNotEmpty) ...<String, Object?>{
        'link': linkHref,
        'link_kind':
            RegExp(
              r'^[a-z][a-z0-9+.-]*:',
              caseSensitive: false,
            ).hasMatch(linkHref)
            ? 'external'
            : 'internal',
      },
    });
  }
  return nodes;
}
