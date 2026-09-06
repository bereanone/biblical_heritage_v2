import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utilities/data/epub_download_validator.dart';
import '../../utilities/data/epub_internal_anchor_section_splitter.dart';
import '../../utilities/data/pioneer_html_capture_folder_scanner.dart';
import 'library_document_import_validator.dart';
import 'library_document_models.dart';
import 'library_xml_html_entities.dart';

/// Separator between hash inputs, built via String.fromCharCode to avoid
/// an unprintable literal in source.
final String _kSep = String.fromCharCode(0);

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
    this.validationFailureReason,
  });

  final bool skipped;
  final int blockCount;
  final String sourceHash;

  /// Non-null when a candidate generation was staged but rejected by
  /// [LibraryDocumentImportValidator]. The prior active generation (if any)
  /// is left untouched and the source file must be retained.
  final String? validationFailureReason;

  bool get activated => validationFailureReason == null;
}

typedef LibraryCanonicalizationFailureHook = void Function(int blockIndex);

class LibraryDocumentCanonicalizer {
  const LibraryDocumentCanonicalizer({this.failureHook});

  /// Bumped when source-preservation or structural parsing changes. Every
  /// change to this file that alters what
  /// canonicalize() produces for existing content MUST bump this constant —
  /// otherwise the version-equality check below silently treats
  /// already-imported books as up to date and the fix never reaches them.
  static const int version = 12;
  final LibraryCanonicalizationFailureHook? failureHook;

  /// Builds a candidate generation of canonical sections/blocks in the
  /// staging tables, validates it, and only then atomically activates it in
  /// place of the current generation. If validation fails (or an exception
  /// is thrown while staging), the previously-active generation — if any —
  /// is left completely untouched, so the reader and the EPUB storage
  /// policy can keep treating the book as usable.
  Future<LibraryDocumentCanonicalizationResult> canonicalize({
    required Database db,
    required String libraryItemId,
    required File source,
    bool force = false,
  }) async {
    final bytes = await source.readAsBytes();
    final sourceHash = sha256.convert(bytes).toString();
    final current = await db.query(
      'library_document_conversion',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    final hadPriorComplete =
        current.isNotEmpty && current.first['status'] == 'complete';
    if (!force &&
        hadPriorComplete &&
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

    final isEpub = p.extension(source.path).toLowerCase() == '.epub';

    // Structural validity is a precondition for parsing at all: an EPUB
    // that would be rejected by the downloader (missing OPF/spine, no
    // readable spine content, a placeholder/teaser package, etc.) must
    // never be walked for sections/blocks here either — see
    // EpubDownloadValidator, the single authoritative structural check
    // shared by the download path and this canonical import path.
    if (isEpub) {
      final structural = EpubDownloadValidator.validate(bytes);
      if (!structural.isValid) {
        final priorVersionMatches =
            hadPriorComplete &&
            (current.first['canonicalizer_version'] as num?)?.toInt() ==
                version;
        return _rejectStructurallyInvalidEpub(
          db: db,
          libraryItemId: libraryItemId,
          sourceHash: sourceHash,
          priorGenerationTrustworthy: priorVersionMatches,
          structural: structural,
        );
      }
    }

    final archive = isEpub
        ? ZipDecoder().decodeBytes(bytes, verify: false)
        : null;
    final assetDirectory = isEpub
        ? Directory(
            p.join(source.parent.path, '_canonical_assets', libraryItemId),
          )
        : source.parent;

    await db.transaction((txn) async {
      await _clearStaging(txn, libraryItemId);
      await txn.insert(
        'library_document_conversion_staging',
        <String, Object?>{
          'library_item_id': libraryItemId,
          'canonicalizer_version': version,
          'source_hash': sourceHash,
          'status': 'converting',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'error_message': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    try {
      final sections = _readSections(source.path, bytes, archive);
      final refCodeTracker = _EpubRefCodeTracker.fromSource(
        source.path,
        sections,
      );
      final ocrHeadingTracker = _needsOcrChapterHeadingRecovery(sections)
          ? _OcrChapterHeadingTracker()
          : null;
      var written = 0;
      // A single href now split into multiple sections (see _readSections's
      // internal-anchor splitting) still needs a stable-id ordinal that's
      // unique across all of that href's blocks, not just within whichever
      // split section a block landed in -- otherwise two sections sharing an
      // href each restart `blockIndex` at 0 and their same-type,
      // same-anchor(null) blocks (most plain paragraphs) collide on the same
      // stable id. Tracked per normalized href so ordinary, unsplit sections
      // (each with a distinct href) are unaffected.
      final blockOrdinalByHref = <String, int>{};
      await db.transaction((txn) async {
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
          var parsed = _parseHtmlBlocks(
            section.html,
            refCodeTracker: refCodeTracker,
          );
          if (ocrHeadingTracker != null) {
            parsed = ocrHeadingTracker.recoverHeadings(parsed);
          }
          if (archive != null) {
            parsed = _extractSectionImages(
              parsed,
              archive: archive,
              sectionHref: normalizedHref,
              assetDirectory: assetDirectory,
            );
          }
          await txn
              .insert('library_document_sections_staging', <String, Object?>{
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
            final stableBlockOrdinal = blockOrdinalByHref[normalizedHref] ?? 0;
            blockOrdinalByHref[normalizedHref] = stableBlockOrdinal + 1;
            final blockId = stableLibraryDocumentBlockId(
              libraryItemId: libraryItemId,
              sourceHref: normalizedHref,
              sourceAnchor: block.anchor,
              blockType: block.type,
              sourceBlockOrdinal: stableBlockOrdinal,
            );
            final contentHash = sha256
                .convert(
                  utf8.encode(
                    '${block.type.name}$_kSep${block.text}$_kSep${block.formatted.toJson()}',
                  ),
                )
                .toString();
            await txn
                .insert('library_document_blocks_staging', <String, Object?>{
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
            await txn
                .insert('library_block_source_map_staging', <String, Object?>{
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
      });

      final stagedSections = await db.query(
        'library_document_sections_staging',
        where: 'library_item_id = ?',
        whereArgs: <Object?>[libraryItemId],
      );
      final stagedBlocks = await db.query(
        'library_document_blocks_staging',
        where: 'library_item_id = ?',
        whereArgs: <Object?>[libraryItemId],
      );
      final validation = const LibraryDocumentImportValidator().validate(
        sections: stagedSections,
        blocks: stagedBlocks,
        imageAssetRoot: assetDirectory,
      );

      if (!validation.passed) {
        await db.transaction((txn) async {
          await _clearStaging(txn, libraryItemId, keepConversionRow: true);
          await txn.update(
            'library_document_conversion_staging',
            <String, Object?>{
              'status': 'failed',
              'error_message': validation.summary,
            },
            where: 'library_item_id = ?',
            whereArgs: <Object?>[libraryItemId],
          );
          if (!hadPriorComplete) {
            await txn.insert(
              'library_document_conversion',
              <String, Object?>{
                'library_item_id': libraryItemId,
                'canonicalizer_version': version,
                'source_hash': sourceHash,
                'status': 'failed',
                'completed_at': null,
                'error_message': validation.summary,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
        return LibraryDocumentCanonicalizationResult(
          skipped: false,
          blockCount: 0,
          sourceHash: sourceHash,
          validationFailureReason: validation.summary,
        );
      }

      await db.transaction((txn) async {
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
        for (final row in stagedSections) {
          await txn.insert('library_document_sections', row);
        }
        for (final row in stagedBlocks) {
          await txn.insert('library_document_blocks', row);
        }
        final stagedSourceMap = await txn.query(
          'library_block_source_map_staging',
          where: 'library_item_id = ?',
          whereArgs: <Object?>[libraryItemId],
        );
        for (final row in stagedSourceMap) {
          await txn.insert('library_block_source_map', row);
        }
        await _clearStaging(txn, libraryItemId);
        await txn.insert(
          'library_document_conversion',
          <String, Object?>{
            'library_item_id': libraryItemId,
            'canonicalizer_version': version,
            'source_hash': sourceHash,
            'status': 'complete',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
            'error_message': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      return LibraryDocumentCanonicalizationResult(
        skipped: false,
        blockCount: written,
        sourceHash: sourceHash,
      );
    } catch (error) {
      await db.transaction((txn) async {
        await _clearStaging(txn, libraryItemId);
        await txn.insert(
          'library_document_conversion_staging',
          <String, Object?>{
            'library_item_id': libraryItemId,
            'canonicalizer_version': version,
            'source_hash': sourceHash,
            'status': 'failed',
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'error_message': error.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (!hadPriorComplete) {
          await txn.insert(
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
        }
      });
      rethrow;
    }
  }

  /// Rejects [source] before any parsing happens, because
  /// [EpubDownloadValidator] found it structurally incomplete (missing
  /// OPF/spine, no readable spine content, a placeholder/teaser package,
  /// etc.). Never stages, never activates, never creates a placeholder
  /// canonical row for a brand-new item. When [priorGenerationTrustworthy]
  /// is true (a prior generation exists and was itself built by the
  /// current canonicalizer version, so it already passed this same gate),
  /// that generation is left completely untouched — this rejection only
  /// concerns whatever now sits on disk, not what is already active.
  /// Otherwise, any stale active generation (necessarily from before this
  /// structural gate existed) is removed so it can never keep serving
  /// content that was never actually validated. The library item is always
  /// marked Needs Attention with the validator's failure reason so it
  /// surfaces in the catalog regardless of which branch applies.
  Future<LibraryDocumentCanonicalizationResult> _rejectStructurallyInvalidEpub({
    required Database db,
    required String libraryItemId,
    required String sourceHash,
    required bool priorGenerationTrustworthy,
    required EpubDownloadValidationResult structural,
  }) async {
    final reason = _structuralRejectionMessage(structural);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await _clearStaging(txn, libraryItemId);
      await txn.insert(
        'library_document_conversion_staging',
        <String, Object?>{
          'library_item_id': libraryItemId,
          'canonicalizer_version': version,
          'source_hash': sourceHash,
          'status': 'failed',
          'created_at': now,
          'error_message': reason,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (!priorGenerationTrustworthy) {
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
        await txn.insert(
          'library_document_conversion',
          <String, Object?>{
            'library_item_id': libraryItemId,
            'canonicalizer_version': version,
            'source_hash': sourceHash,
            'status': 'failed',
            'completed_at': null,
            'error_message': reason,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.update(
        'library_items',
        <String, Object?>{
          'index_status': 'needs_attention',
          'index_error': reason,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: <Object?>[libraryItemId],
      );
    });
    return LibraryDocumentCanonicalizationResult(
      skipped: false,
      blockCount: 0,
      sourceHash: sourceHash,
      validationFailureReason: reason,
    );
  }

  String _structuralRejectionMessage(EpubDownloadValidationResult structural) {
    final reasonName = structural.rejectionReason?.name;
    final detail = structural.detail?.trim();
    final label = reasonName == null
        ? 'Structurally invalid EPUB'
        : 'Structurally invalid EPUB ($reasonName)';
    return detail == null || detail.isEmpty ? '$label.' : '$label: $detail';
  }

  /// Clears staged blocks/sections/source-map rows for [libraryItemId].
  /// When [keepConversionRow] is false (the default), the staging
  /// conversion row itself is cleared too; pass true to keep it so a
  /// caller can immediately update it with a failure status/reason.
  Future<void> _clearStaging(
    Transaction txn,
    String libraryItemId, {
    bool keepConversionRow = false,
  }) async {
    await txn.delete(
      'library_block_source_map_staging',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
    );
    await txn.delete(
      'library_document_blocks_staging',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
    );
    await txn.delete(
      'library_document_sections_staging',
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
    );
    if (!keepConversionRow) {
      await txn.delete(
        'library_document_conversion_staging',
        where: 'library_item_id = ?',
        whereArgs: <Object?>[libraryItemId],
      );
    }
  }

  List<LibraryCanonicalSourceSection> _readSections(
    String path,
    List<int> bytes,
    Archive? archive,
  ) {
    if (archive == null) {
      return <LibraryCanonicalSourceSection>[
        LibraryCanonicalSourceSection(
          href: p.basename(path),
          title: p.basenameWithoutExtension(path),
          html: utf8.decode(bytes, allowMalformed: true),
        ),
      ];
    }
    final entries = _epubSpineEntries(archive);
    // A book authored as one physical file per book rather than one per
    // chapter (e.g. a Capture Clipper full-work capture) has all of its
    // chapters living inside a single entry here. Left as one section, every
    // block in it inherits whichever heading happens to be extracted above
    // as the section title, so distinct chapters (e.g. INTRODUCTION and
    // APPENDIX A) end up misattributed to the same section identity. Where
    // the book's own NCX/nav.xhtml places 2+ authored destinations inside
    // one entry via distinct internal anchors, split that entry into one
    // section per destination instead.
    final targetsByPath = EpubInternalAnchorSectionSplitter.readTargetsByPath(
      archive: archive,
      fallbackTitle: p.basenameWithoutExtension(path),
    );
    final sections = <LibraryCanonicalSourceSection>[];
    for (final entry in entries) {
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
      final wholeFileTitle = _plain(title);
      final targets =
          targetsByPath[EpubInternalAnchorSectionSplitter.normalizedEpubPathKey(
            entry.name,
          )];
      final splitSections = targets == null || targets.length < 2
          ? <EpubAnchorSplitSection>[
              EpubAnchorSplitSection(title: wholeFileTitle, html: html),
            ]
          : EpubInternalAnchorSectionSplitter.splitByAnchors(
              rawHtml: html,
              targets: targets,
              wholeFileTitle: wholeFileTitle,
            );
      for (final split in splitSections) {
        sections.add(
          LibraryCanonicalSourceSection(
            href: entry.name,
            title: split.title,
            html: split.html,
          ),
        );
      }
    }
    return List<LibraryCanonicalSourceSection>.unmodifiable(sections);
  }

  List<ArchiveFile> _epubSpineEntries(Archive archive) {
    final container = _findArchiveEntry(archive, 'META-INF/container.xml');
    if (container == null) return _sortedHtmlEntries(archive);
    final containerXml = utf8.decode(
      container.content as List<int>,
      allowMalformed: true,
    );
    final opfPath = RegExp(
      r'''<rootfile\b[^>]*\bfull-path\s*=\s*(["'])([^"']+)\1''',
      caseSensitive: false,
    ).firstMatch(containerXml)?.group(2)?.trim();
    if (opfPath == null || opfPath.isEmpty) {
      return _sortedHtmlEntries(archive);
    }
    final opfEntry = _findArchiveEntry(archive, opfPath);
    if (opfEntry == null) return _sortedHtmlEntries(archive);
    final opfXml = utf8.decode(
      opfEntry.content as List<int>,
      allowMalformed: true,
    );
    final manifestBody = RegExp(
      r'<manifest\b[^>]*>(.*?)</manifest>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(opfXml)?.group(1);
    final spineBody = RegExp(
      r'<spine\b[^>]*>(.*?)</spine>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(opfXml)?.group(1);
    if (manifestBody == null || spineBody == null) {
      return _sortedHtmlEntries(archive);
    }

    final hrefById = <String, String>{};
    for (final match in RegExp(
      r'<item\b([^>]*)/?>',
      caseSensitive: false,
    ).allMatches(manifestBody)) {
      final attributes = match.group(1) ?? '';
      final id = _xmlAttribute(attributes, 'id');
      final href = _xmlAttribute(attributes, 'href');
      if (id != null && href != null) hrefById[id] = href;
    }

    final opfDirectory = p.posix.dirname(opfPath.replaceAll('\\', '/'));
    final entries = <ArchiveFile>[];
    for (final match in RegExp(
      r'<itemref\b([^>]*)/?>',
      caseSensitive: false,
    ).allMatches(spineBody)) {
      final idref = _xmlAttribute(match.group(1) ?? '', 'idref');
      final href = idref == null ? null : hrefById[idref];
      if (href == null ||
          !RegExp(
            r'\.(xhtml|html|htm)(?:[?#].*)?$',
            caseSensitive: false,
          ).hasMatch(href)) {
        continue;
      }
      final hrefPath = href.split(RegExp(r'[?#]')).first;
      final resolved = p.posix.normalize(
        p.posix.join(opfDirectory == '.' ? '' : opfDirectory, hrefPath),
      );
      final entry = _findArchiveEntry(archive, resolved);
      if (entry != null) entries.add(entry);
    }
    return entries.isEmpty ? _sortedHtmlEntries(archive) : entries;
  }

  List<ArchiveFile> _sortedHtmlEntries(Archive archive) =>
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

  ArchiveFile? _findArchiveEntry(Archive archive, String path) {
    final normalized = path
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+'), '')
        .toLowerCase();
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final candidate = entry.name
          .trim()
          .replaceAll('\\', '/')
          .replaceAll(RegExp(r'^/+'), '')
          .toLowerCase();
      if (candidate == normalized) return entry;
    }
    return null;
  }

  String? _xmlAttribute(String attributes, String name) {
    final match = RegExp(
      '''\\b${RegExp.escape(name)}\\s*=\\s*(["'])(.*?)\\1''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(attributes);
    return match?.group(2)?.trim();
  }

  /// Extracts the bytes of every referenced `<img src>` from [archive] into
  /// [assetDirectory] and rewrites each image block's `source` to the bare
  /// extracted filename, so the reader can resolve it the same way it
  /// resolves CaptureClipper-adjacent images (join against a plain root
  /// directory) without needing the EPUB archive present.
  List<_ParsedCanonicalBlock> _extractSectionImages(
    List<_ParsedCanonicalBlock> blocks, {
    required Archive archive,
    required String sectionHref,
    required Directory assetDirectory,
  }) {
    if (!blocks.any((block) => block.type == LibraryDocumentBlockType.image)) {
      return blocks;
    }
    return blocks
        .map((block) {
          if (block.type != LibraryDocumentBlockType.image) return block;
          final nodes = block.formatted.nodes;
          if (nodes.isEmpty) return block;
          final node = nodes.first;
          final rawSource = node['source']?.toString() ?? '';
          final resolvedEntryPath = _resolveEpubInternalPath(
            sectionHref: sectionHref,
            src: rawSource,
          );
          if (resolvedEntryPath == null) return block;
          ArchiveFile? entry;
          for (final candidate in archive.files) {
            if (!candidate.isFile) continue;
            if (candidate.name.toLowerCase() ==
                resolvedEntryPath.toLowerCase()) {
              entry = candidate;
              break;
            }
          }
          if (entry == null) return block;
          final content = entry.content as List<int>;
          final assetHash = sha256.convert(content).toString();
          final extension = p.extension(resolvedEntryPath).toLowerCase();
          final fileName = '$assetHash$extension';
          final assetFile = File(p.join(assetDirectory.path, fileName));
          try {
            if (!assetDirectory.existsSync()) {
              assetDirectory.createSync(recursive: true);
            }
            if (!assetFile.existsSync()) {
              assetFile.writeAsBytesSync(content, flush: true);
            }
          } on FileSystemException {
            return block;
          }
          final rewrittenNode = Map<String, Object?>.of(node)
            ..['source'] = fileName;
          return _ParsedCanonicalBlock(
            type: block.type,
            text: block.text,
            formatted: LibraryFormattedContent(
              nodes: <Map<String, Object?>>[rewrittenNode],
              alignment: block.formatted.alignment,
              metadata: block.formatted.metadata,
            ),
            anchor: block.anchor,
            refcode: block.refcode,
          );
        })
        .toList(growable: false);
  }
}

/// Resolves an `<img src>` value against the EPUB-internal path of the
/// section that referenced it, returning a normalized zip-entry path or
/// null for external/absolute references that aren't part of the archive.
String? _resolveEpubInternalPath({
  required String sectionHref,
  required String src,
}) {
  final trimmed = src.trim();
  if (trimmed.isEmpty) return null;
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(trimmed)) {
    return null;
  }
  final withoutFragment = trimmed.split(RegExp(r'[?#]')).first;
  final base = p.posix.dirname(sectionHref);
  final joined = p.posix.normalize(p.posix.join(base, withoutFragment));
  return joined.startsWith('/') ? joined.substring(1) : joined;
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

List<_ParsedCanonicalBlock> _parseHtmlBlocks(
  String html, {
  _EpubRefCodeTracker? refCodeTracker,
}) {
  if (RegExp(
    r'''class\s*=\s*["'][^"']*\bclip-text\b''',
    caseSensitive: false,
  ).hasMatch(html)) {
    final captured = _parseCapturedEgwBlocks(html);
    if (captured.isNotEmpty) return captured;
  }
  return _parseSemanticHtmlBlocks(html, refCodeTracker: refCodeTracker);
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

List<_ParsedCanonicalBlock> _parseSemanticHtmlBlocks(
  String html, {
  _EpubRefCodeTracker? refCodeTracker,
}) {
  final pattern = RegExp(
    r'<(h[1-6]|p|blockquote|pre|li|img|hr)\b([^>]*)>(?:(.*?)</\1\s*>)?',
    caseSensitive: false,
    dotAll: true,
  );
  final result = <_ParsedCanonicalBlock>[];
  // EPUB navigation commonly targets an empty named anchor immediately
  // preceding a heading (`<a id="chapter-1"></a><h1>…`).  The anchor is a
  // real document location, even though it is not part of the heading node.
  // Carry it forward to the next readable block rather than replacing it with
  // that block's unrelated `id` (or a generated one).
  var anchorScanOffset = 0;
  String? pendingAnchor;
  for (final match in pattern.allMatches(html)) {
    final tag = match.group(1)!.toLowerCase();
    final attrs = match.group(2) ?? '';
    final inner = match.group(3) ?? '';
    final prefix = html.substring(anchorScanOffset, match.start);
    final leadingAnchors = RegExp(
      r'''<a\b[^>]*(?:\bid|\bname)\s*=\s*(["'])([^"']+)\1[^>]*>\s*</a\s*>''',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(prefix);
    for (final anchor in leadingAnchors) {
      final value = anchor.group(2)?.trim();
      if (value != null && value.isNotEmpty) pendingAnchor = value;
    }
    anchorScanOffset = match.end;
    // Keep `inner` unstripped for the pagebreak refcode tracker below (it
    // needs to see pagebreak markers), but derive prose text/nodes from a
    // copy with any refcode marker span removed.
    final proseInner = _stripRefCodeSpans(inner);
    final text = tag == 'img'
        ? (_attribute(attrs, 'alt') ?? '')
        : _plain(proseInner);
    // A bare 1-4 digit heading (post entity-decoding, trimmed) is a printed
    // page number from the source layout (common in Apple Pages EPUB
    // exports), not a real chapter/section heading — "Chapter 71" or "71."
    // still classify as headings since they contain non-digit characters.
    final isStandaloneNumber = RegExp(r'^\d{1,4}$').hasMatch(text);
    final isBarePageNumber = tag.startsWith('h') && isStandaloneNumber;
    // These elements are print-layout anchors, not reader content. Keeping
    // them as paragraphs made books such as Acts of the Apostles render
    // hundreds of consecutive page numbers, one per line. A real numbered
    // heading remains intact when it has punctuation or descriptive text.
    if (isBarePageNumber || (tag == 'li' && isStandaloneNumber)) continue;
    final type = switch (tag) {
      'blockquote' => LibraryDocumentBlockType.quotation,
      'pre' => LibraryDocumentBlockType.poem,
      'li' => LibraryDocumentBlockType.listItem,
      'img' => LibraryDocumentBlockType.image,
      'hr' => LibraryDocumentBlockType.horizontalRule,
      _ when tag.startsWith('h') => LibraryDocumentBlockType.heading,
      _ => LibraryDocumentBlockType.paragraph,
    };
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
        : _inlineNodes(proseInner, className: className);
    final headingRole = switch (tag) {
      'h1' => 'book_title',
      'h2' => 'chapter',
      'h3' => 'section',
      'h4' || 'h5' || 'h6' => 'minor',
      _ => null,
    };
    if (headingRole == 'chapter') refCodeTracker?.beginBody();
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
        anchor: pendingAnchor ?? _attribute(attrs, 'id'),
        refcode:
            _attribute(attrs, 'data-refcode') ??
            (type == LibraryDocumentBlockType.paragraph
                ? refCodeTracker?.referenceCodeFor(inner)
                : null),
      ),
    );
    pendingAnchor = null;
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

class _EpubRefCodeTracker {
  factory _EpubRefCodeTracker.fromSource(
    String sourcePath,
    List<LibraryCanonicalSourceSection> sections,
  ) {
    final stem = p.basenameWithoutExtension(sourcePath);
    final match = RegExp(
      r'^(?:[a-z]{2,3}[_-])?([a-z][a-z0-9]{0,9})$',
      caseSensitive: false,
    ).firstMatch(stem);
    int? initialPage;
    for (final section in sections) {
      final marker = RegExp(
        r'''<[^>]*\bepub:type\s*=\s*["']pagebreak["'][^>]*>''',
        caseSensitive: false,
      ).firstMatch(section.html);
      if (marker == null) continue;
      final tag = marker.group(0) ?? '';
      final value =
          _attribute(tag, 'title') ??
          _attribute(tag, 'id')?.replaceFirst(RegExp(r'^[pP]'), '');
      final page = int.tryParse(value ?? '');
      if (page != null && page > 0) {
        initialPage = page > 1 ? page - 1 : page;
        break;
      }
    }
    return _EpubRefCodeTracker(
      match?.group(1)?.toUpperCase(),
      initialPage: initialPage,
    );
  }

  final String? abbreviation;
  _EpubRefCodeTracker(this.abbreviation, {int? initialPage})
    : _page = initialPage;
  int? _page;
  int _paragraphOnPage = 0;
  bool _bodyStarted = false;

  void beginBody() => _bodyStarted = true;

  String? referenceCodeFor(String paragraphHtml) {
    final code = abbreviation;
    if (!_bodyStarted || code == null || code.isEmpty) return null;
    final markers = RegExp(
      r'''<[^>]*\bepub:type\s*=\s*["']pagebreak["'][^>]*>''',
      caseSensitive: false,
    ).allMatches(paragraphHtml).toList();
    final markerPages = <({int page, bool textBefore})>[];
    for (final marker in markers) {
      final tag = marker.group(0) ?? '';
      final pageValue =
          _attribute(tag, 'title') ??
          _attribute(tag, 'id')?.replaceFirst(RegExp(r'^[pP]'), '');
      final page = int.tryParse(pageValue ?? '');
      if (page == null || page <= 0) continue;
      markerPages.add((
        page: page,
        textBefore: _plain(paragraphHtml.substring(0, marker.start)).isNotEmpty,
      ));
    }
    if (_page == null && markerPages.isNotEmpty) {
      final first = markerPages.first;
      _page = first.textBefore && first.page > 1 ? first.page - 1 : first.page;
      _paragraphOnPage = 0;
    }
    if (_page == null) return null;

    final leadingMarker = markerPages.firstOrNull;
    if (leadingMarker != null && !leadingMarker.textBefore) {
      _page = leadingMarker.page;
      _paragraphOnPage = 0;
    }
    _paragraphOnPage++;
    final result = '$code $_page.$_paragraphOnPage';

    for (final marker in markerPages) {
      if (!marker.textBefore) continue;
      _page = marker.page;
      _paragraphOnPage = 0;
    }
    return result;
  }
}

/// Detects EPUBs with no semantic heading markup anywhere in their spine —
/// the shape of a raw archive.org OCR page-scan export (one `<p>` per
/// scanned page, no `<h1>`-`<h6>` tags at all, and typically a `nav.xhtml`
/// with no real chapter list). Gated on the absence of any heading tag
/// across the *whole* book, not on source type or provenance, so any future
/// import with the same shape is recovered automatically and real semantic
/// EPUBs (which always carry at least one heading somewhere) are never
/// affected. The `sections.length > 3` floor keeps this from misfiring on
/// tiny single/few-page imports where "no headings" is simply correct.
///
/// The navigation document itself (identified by the EPUB3
/// `epub:type="toc"` marker, not by filename) is excluded from this scan:
/// it commonly carries its own real heading for the TOC page's title (e.g.
/// "<h2>Adventist Pioneer Authors - Uriah Smith</h2>") and, per the spine
/// order these archive.org exports use, is itself the book's first spine
/// entry — so without this exclusion that one structural heading would
/// wrongly count as "this book has real semantic headings" for every OCR
/// scan in the cohort, even though not a single page of actual content has
/// any heading markup at all.
bool _needsOcrChapterHeadingRecovery(
  List<LibraryCanonicalSourceSection> sections,
) {
  final contentSections = sections
      .where((section) => !_isEpubNavigationDocument(section.html))
      .toList(growable: false);
  return contentSections.length > 3 &&
      !contentSections.any(
        (section) =>
            RegExp(r'<h[1-6]\b', caseSensitive: false).hasMatch(section.html),
      );
}

bool _isEpubNavigationDocument(String html) => RegExp(
  '''epub:type\\s*=\\s*["'][^"']*\\btoc\\b[^"']*["']''',
  caseSensitive: false,
).hasMatch(html);

/// Recovers chapter headings for OCR-scanned EPUBs whose page text carries
/// no semantic markup at all: chapter titles exist only as an unmarked
/// "number - TITLE" run that OCR left sitting mid-paragraph (e.g. "07 -
/// THE FOUR BEASTS Chronological Connection..."), immediately followed by
/// unrelated outline/body text with no boundary marker of any kind.
///
/// Recovery requires the number to match the next expected chapter in
/// strict monotonic sequence — the same technique already used for the
/// "CHAPTER (roman numeral)." tracker in [_parseCapturedEgwBlocks] above —
/// so a "number - CAPS" run that happens to occur elsewhere in body prose
/// can only be misread as a heading if it lands on the exact next chapter
/// number in order, which is effectively never in practice. The title
/// itself is bounded by the run of ALL-CAPS/numeral words that follows,
/// stopping at the first mixed-case word — the same "line == uppercase"
/// signal [_parseCapturedEgwBlocks] uses, applied to a word run instead of
/// a whole line since OCR text here has no line breaks to key off.
///
/// Only ever touches paragraph blocks whose formatted content is a single
/// plain, unstyled text node (exactly what an OCR page's flat `<p>`
/// produces) — a block with links/marks/multiple nodes is left completely
/// alone rather than risk corrupting real formatting this heuristic can't
/// see.
class _OcrChapterHeadingTracker {
  int _expectedChapter = 1;

  List<_ParsedCanonicalBlock> recoverHeadings(
    List<_ParsedCanonicalBlock> blocks,
  ) {
    var changed = false;
    final result = <_ParsedCanonicalBlock>[];
    for (final block in blocks) {
      if (block.type != LibraryDocumentBlockType.paragraph ||
          !_isSimplePlainTextParagraph(block)) {
        result.add(block);
        continue;
      }
      final split = _splitForHeadings(block);
      if (split.length != 1 || split.first != block) changed = true;
      result.addAll(split);
    }
    return changed ? result : blocks;
  }

  bool _isSimplePlainTextParagraph(_ParsedCanonicalBlock block) {
    final nodes = block.formatted.nodes;
    if (nodes.length != 1) return false;
    final node = nodes.first;
    return node['type'] == 'text' &&
        node['text'] == block.text &&
        node['marks'] == null &&
        node['link'] == null;
  }

  List<_ParsedCanonicalBlock> _splitForHeadings(_ParsedCanonicalBlock block) {
    final text = block.text;
    final className = block.formatted.nodes.first['class'] as String?;
    final pieces = <_ParsedCanonicalBlock>[];
    var cursor = 0;
    while (true) {
      final match = _nextOcrChapterHeadingMatch(text, cursor, _expectedChapter);
      if (match == null) break;
      final before = text.substring(cursor, match.start).trim();
      if (before.isNotEmpty) {
        pieces.add(_ocrPlainParagraph(before, className: className));
      }
      pieces.add(_ocrRecoveredHeading(match.text, className: className));
      cursor = match.end;
      _expectedChapter++;
    }
    if (pieces.isEmpty) return <_ParsedCanonicalBlock>[block];
    final tail = text.substring(cursor).trim();
    if (tail.isNotEmpty) {
      pieces.add(_ocrPlainParagraph(tail, className: className));
    }
    return pieces;
  }
}

class _OcrHeadingMatch {
  const _OcrHeadingMatch({
    required this.start,
    required this.end,
    required this.text,
  });
  final int start;
  final int end;
  final String text;
}

final RegExp _ocrChapterAnchorPattern = RegExp(
  r'(?:^|\s)(\d{1,3})\s*-\s*(?=[A-Z])',
);

_OcrHeadingMatch? _nextOcrChapterHeadingMatch(
  String text,
  int fromIndex,
  int expectedChapter,
) {
  for (final anchor in _ocrChapterAnchorPattern.allMatches(text, fromIndex)) {
    if (int.tryParse(anchor.group(1)!) != expectedChapter) continue;
    final digitStart = text.indexOf(anchor.group(1)!, anchor.start);
    final titleEnd = _consumeOcrUppercaseTitleRun(text, anchor.end);
    if (titleEnd == null) continue;
    return _OcrHeadingMatch(
      start: digitStart,
      end: titleEnd,
      text: text.substring(digitStart, titleEnd).trim(),
    );
  }
  return null;
}

/// Consumes a run of whitespace-separated tokens starting at [from] that
/// are each either all-uppercase (ignoring surrounding punctuation, at
/// least 2 letters/digits) or purely numeric, stopping at the first token
/// that is neither — the boundary between a printed ALL-CAPS chapter title
/// and the mixed-case outline/body text that immediately follows it with no
/// other separator in the raw OCR text. Returns null (no usable title) if
/// not even one qualifying word follows, or caps the run at a sane word
/// count as a defensive backstop against pathological input.
///
/// A bare number immediately followed by a "-" token is never consumed,
/// even though it would otherwise pass the "purely numeric" test: that
/// shape is the *next* chapter's own "NN - TITLE" anchor sitting right
/// after this one with no body text in between (short back-to-back
/// chapters, or a page that starts one chapter and ends another) — without
/// this guard, chapter 1's recovered title would swallow chapter 2's
/// leading number, e.g. "01 - DANIEL IN CAPTIVITY 02" instead of stopping
/// cleanly at "CAPTIVITY".
///
/// A handful of structural back-matter markers (APPENDIX/INDEX/PART) also
/// end the run before being consumed, even though each is itself a
/// qualifying all-caps word: the last real chapter in a pioneer book is
/// routinely followed immediately (no page/body boundary at all in the OCR
/// text) by the start of the back matter, e.g. "...THE TREE AND THE RIVER
/// OF LIFE APPENDIX 1. RESEMBLANCE..." — without this the final chapter's
/// title would run on into the appendix listing.
const Set<String> _ocrTitleRunStopWords = <String>{'APPENDIX', 'INDEX', 'PART'};

int? _consumeOcrUppercaseTitleRun(String text, int from) {
  final tokens = RegExp(r'\S+').allMatches(text.substring(from)).toList();
  var end = from;
  var words = 0;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final word = token.group(0)!;
    final core = word.replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'), '');
    final isDigits = core.isNotEmpty && RegExp(r'^\d+$').hasMatch(core);
    final isUpperWord =
        core.length >= 2 &&
        core == core.toUpperCase() &&
        core.toUpperCase() != core.toLowerCase();
    if (isUpperWord && words > 0 && _ocrTitleRunStopWords.contains(core)) {
      break;
    }
    if (isDigits) {
      final next = i + 1 < tokens.length ? tokens[i + 1].group(0)! : '';
      if (next.startsWith('-')) break;
    }
    if (!isDigits && !isUpperWord) break;
    end = from + token.end;
    words++;
    if (words >= 12) break;
  }
  return words == 0 ? null : end;
}

_ParsedCanonicalBlock _ocrPlainParagraph(String text, {String? className}) =>
    _ParsedCanonicalBlock(
      type: LibraryDocumentBlockType.paragraph,
      text: text,
      formatted: LibraryFormattedContent.plain(text, className: className),
    );

_ParsedCanonicalBlock _ocrRecoveredHeading(String text, {String? className}) =>
    _ParsedCanonicalBlock(
      type: LibraryDocumentBlockType.heading,
      text: text,
      formatted: LibraryFormattedContent(
        nodes: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'text',
            'text': text,
            if (className != null && className.isNotEmpty) 'class': className,
          },
        ],
        metadata: const <String, Object?>{
          'source_tag': 'p',
          'heading_role': 'chapter',
          'classification_reason':
              'recovered from unmarked OCR chapter-number title run',
        },
      ),
    );

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
    sha256.convert(utf8.encode(parts.join(_kSep))).toString();
int _firstIntValue(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? 0 : (rows.first.values.first as num?)?.toInt() ?? 0;
String? _attribute(String attrs, String name) => RegExp(
  '''\\b$name\\s*=\\s*["']([^"']*)["']''',
  caseSensitive: false,
).firstMatch(attrs)?.group(1);

// A `class="refcode"` marker span carries the same citation the paragraph's
// own `data-refcode` attribute (or the pagebreak tracker) already exposes as
// separate, toggleable `source_refcode` metadata. Left in place, its visible
// text (e.g. "{SL27 iii.1}") survives into plain prose and gets rendered a
// second time, unconditionally, alongside the toggleable copy.
final RegExp _refCodeSpanPattern = RegExp(
  '''<(\\w+)\\b[^>]*\\bclass\\s*=\\s*["'][^"']*\\brefcode\\b[^"']*["'][^>]*>.*?</\\1\\s*>''',
  caseSensitive: false,
  dotAll: true,
);

String _stripRefCodeSpans(String html) =>
    html.replaceAll(_refCodeSpanPattern, '');

String? _alignment(String attrs, String? className) {
  final value = '${_attribute(attrs, 'style') ?? ''} ${className ?? ''}'
      .toLowerCase();
  for (final alignment in <String>['center', 'right', 'justify', 'left']) {
    if (value.contains(alignment)) return alignment;
  }
  return null;
}

String _plain(String html) =>
    decodeXmlHtmlEntities(
          html
              .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
              .replaceAll(RegExp(r'<[^>]+>'), ''),
        )
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
