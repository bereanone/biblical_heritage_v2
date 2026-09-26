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
import 'library_document_assets.dart';
import 'library_document_block_identity.dart';
import 'library_captured_reference_alignment.dart';
import 'library_document_models.dart';
import 'library_epub_text_styles.dart';
import 'library_citation_links.dart';
import 'library_xml_html_entities.dart';

/// Separator between hash inputs, built via String.fromCharCode to avoid
/// an unprintable literal in source.
final String _kSep = String.fromCharCode(0);

class LibraryCanonicalSourceSection {
  const LibraryCanonicalSourceSection({
    required this.href,
    required this.title,
    required this.html,
    this.textStyles = const EpubTextStyles.empty(),
    this.numericHeadingTargets = const <EpubAnchorTarget>[],
  });

  final String href;
  final String title;
  final String html;
  final EpubTextStyles textStyles;
  // Scoped to this exact EPUB file/fragment; these labels never identify works.
  final List<EpubAnchorTarget> numericHeadingTargets;
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
  // v41 links chapter references and distinguishes numbered books from verse lists.
  static const int version = 42;
  final LibraryCanonicalizationFailureHook? failureHook;

  Future<void> _reconcileStagedBlockIds(
    Database db,
    String itemId,
    String sourceHash,
  ) async {
    await db.transaction((txn) async {
      final previous = await txn.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      if (previous.isEmpty) return;
      final candidate = await txn.query(
        'library_document_blocks_staging',
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      final identities = reconcileLibraryBlockIds(
        libraryItemId: itemId,
        sourceHash: sourceHash,
        previous: previous,
        candidate: candidate,
      );
      final changes = identities.entries
          .where((entry) => entry.key != entry.value)
          .toList();
      // Two phases permit ID swaps without UNIQUE collisions. Only scratch
      // staging rows move; active blocks and user locators are untouched.
      for (var phase = 0; phase < 2; phase++) {
        final batch = txn.batch();
        for (final entry in changes) {
          final temporary = 'identity-staging:${entry.key}';
          final from = phase == 0 ? entry.key : temporary;
          final to = phase == 0 ? temporary : entry.value;
          batch.update(
            'library_document_blocks_staging',
            {'id': to},
            where: 'library_item_id = ? AND id = ?',
            whereArgs: [itemId, from],
          );
          batch.update(
            'library_block_source_map_staging',
            {'block_id': to},
            where: 'library_item_id = ? AND block_id = ?',
            whereArgs: [itemId, from],
          );
        }
        await batch.commit(noResult: true);
      }
    });
  }

  /// Builds a candidate generation of canonical sections/blocks in the
  /// staging tables, validates it, and only then atomically activates it in
  /// place of the current generation. If validation fails (or an exception
  /// is thrown while staging), the previously-active generation — if any —
  /// is left completely untouched, so the reader and the EPUB storage
  /// policy can keep treating the book as usable.
  /// A retained row is not preserved markup if its selected words move.
  /// Reject a candidate before activation when an existing canonical range
  /// cannot be proven unchanged. The prior readable generation remains active;
  /// explicit reconciliation can later supply a reviewed relocation.
  Future<void> _requirePreservedMarkupTargets(
    DatabaseExecutor txn,
    String itemId,
    List<Map<String, Object?>> staged,
  ) async {
    final markups = await txn.query(
      'elibrary_markups',
      where:
          "library_item_id = ? AND deleted_at IS NULL AND epub_href LIKE 'canonical:%'",
      whereArgs: [itemId],
    );
    if (markups.isEmpty) return;
    final byId = {for (final b in staged) b['id'].toString(): b};
    for (final m in markups) {
      final id = m['epub_href'].toString().substring('canonical:'.length);
      final block = byId[id];
      final text = block?['plain_text']?.toString() ?? '';
      final start = (m['start_char_offset'] as num).toInt();
      final end = (m['end_char_offset'] as num).toInt();
      if (block == null ||
          m['start_block_index'] != 0 ||
          m['end_block_index'] != 0 ||
          start < 0 ||
          end <= start ||
          end > text.length ||
          text.substring(start, end) != m['selected_text_snapshot']) {
        throw StateError(
          'Content update retained the previous generation: '
          'markup ${m['id']} needs an explicit location mapping.',
        );
      }
    }
  }

  Future<void> _requirePreservedSavedPosition(
    DatabaseExecutor txn,
    String itemId,
    List<Map<String, Object?>> staged,
  ) async {
    final rows = await txn.query(
      'library_items',
      columns: ['anchor_id'],
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    final anchor = rows.firstOrNull?['anchor_id']?.toString() ?? '';
    if (!anchor.startsWith('canonical:')) return;
    final blockId = anchor.substring('canonical:'.length);
    if (!staged.any((block) => block['id'] == blockId)) {
      throw StateError(
        'Content update retained the previous generation: '
        'saved reading position needs an explicit location mapping.',
      );
    }
  }

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
    final syntheticReferenceDesignator =
        await _pioneerSyntheticReferenceDesignator(db, libraryItemId);
    final capturedReferenceAlignment = await CapturedReferenceAlignment.load(
      db,
      libraryItemId,
    );

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
      final referenceRows = await db.query(
        'library_source_reference_map',
        where: 'source_hash = ?',
        whereArgs: [sourceHash],
      );
      final referenceMap = {
        for (final row in referenceRows)
          '${row['source_href']}#${row['source_block_ordinal']}': row,
      };
      final pageProfiles = await db.query(
        'library_source_page_profiles',
        where: 'source_hash = ?',
        whereArgs: [sourceHash],
        limit: 1,
      );
      final sourcePageTracker = _SourcePageTracker(
        spanClass: pageProfiles.firstOrNull?['page_marker_span_class']
            ?.toString(),
      );
      final refCodeTracker = _EpubRefCodeTracker.fromSource(
        source.path,
        sections,
      );
      final syntheticReferenceTracker = syntheticReferenceDesignator == null
          ? null
          : _SyntheticPageMarkerReferenceTracker(syntheticReferenceDesignator);
      final hasAuthoredChapters =
          archive != null &&
          EpubInternalAnchorSectionSplitter.readNavigationTargets(
                archive: archive,
                fallbackTitle: '',
              ).length >
              1;
      final ocrHeadingTracker =
          !hasAuthoredChapters && _needsOcrChapterHeadingRecovery(sections)
          ? _OcrChapterHeadingTracker()
          : null;
      var written = 0;
      var appliedReferences = 0;
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
            textStyles: section.textStyles,
            refCodeTracker: refCodeTracker,
            sourcePageTracker: sourcePageTracker,
            numericHeadingTargets: section.numericHeadingTargets,
            linkCitations: ocrHeadingTracker == null,
          );
          if (ocrHeadingTracker != null) {
            // Detect structure before generated links split plain OCR nodes.
            // Relink the resulting nodes without flattening authored formatting.
            parsed = ocrHeadingTracker
                .recoverHeadings(parsed)
                .map(
                  (block) => _ParsedCanonicalBlock(
                    type: block.type,
                    text: block.text,
                    anchor: block.anchor,
                    refcode: block.refcode,
                    formatted: LibraryFormattedContent(
                      alignment: block.formatted.alignment,
                      metadata: block.formatted.metadata,
                      nodes: linkLibraryCitations(block.formatted.nodes),
                    ),
                  ),
                )
                .toList();
          }
          if (archive != null) {
            parsed = _extractSectionImages(
              parsed,
              archive: archive,
              sectionHref: normalizedHref,
              assetDirectory: assetDirectory,
            );
          }
          if (syntheticReferenceTracker != null) {
            parsed = parsed
                .map(syntheticReferenceTracker.referenceCodeFor)
                .toList(growable: false);
          }
          if (capturedReferenceAlignment != null) {
            parsed = parsed
                .map((block) {
                  if (block.refcode?.trim().isNotEmpty == true ||
                      !_isCitableBodyBlock(block)) {
                    return block;
                  }
                  final code = capturedReferenceAlignment.nextCodeFor(
                    block.text,
                  );
                  return code == null
                      ? block
                      : block.withSyntheticReferenceCode(
                          code,
                          origin: capturedReferenceOrigin,
                        );
                })
                .toList(growable: false);
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
            var block = parsed[blockIndex];
            if (block.type == LibraryDocumentBlockType.paragraph) {
              paragraphOrdinal++;
            }
            final stableBlockOrdinal = blockOrdinalByHref[normalizedHref] ?? 0;
            blockOrdinalByHref[normalizedHref] = stableBlockOrdinal + 1;
            final verifiedReference =
                referenceMap['$normalizedHref#$stableBlockOrdinal'];
            if (verifiedReference != null) {
              final textHash = sha256
                  .convert(utf8.encode(block.text))
                  .toString();
              if (verifiedReference['source_text_hash'] != textHash) {
                throw StateError(
                  'Verified reference alignment no longer matches source paragraph $normalizedHref#$stableBlockOrdinal',
                );
              }
              final code =
                  '${verifiedReference['work_prefix']} ${verifiedReference['page_number']}.${verifiedReference['paragraph_number']}';
              block = block.withVerifiedReferenceCode(code, verifiedReference);
              appliedReferences++;
            }

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
                  ...block.referenceColumns,
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

      if (appliedReferences != referenceRows.length) {
        throw StateError(
          'Verified reference alignment contains missing source paragraphs.',
        );
      }
      await _reconcileStagedBlockIds(db, libraryItemId, sourceHash);
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
      final stagedNavigation = _navigationRows(
        libraryItemId,
        archive,
        stagedBlocks,
      );
      final validation = const LibraryDocumentImportValidator().validate(
        sections: stagedSections,
        blocks: stagedBlocks,
        navigation: stagedNavigation,
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

      // Persistence of image bytes is part of activation, not a later cleanup.
      // Capture/HTML sources retain their existing adjacent-image contract.
      final embeddedAssets = isEpub
          ? await LibraryDocumentAssets.collect(
              blocks: stagedBlocks,
              directory: assetDirectory,
            )
          : null;
      final previousAssets = isEpub
          ? await db.rawQuery(
              'SELECT a.cover_asset_name FROM library_document_asset_sets a '
              'JOIN library_document_conversion c ON c.library_item_id=a.library_item_id '
              'AND c.source_hash=a.source_hash WHERE a.library_item_id=?',
              [libraryItemId],
            )
          : <Map<String, Object?>>[];
      final previousCover =
          previousAssets.firstOrNull?['cover_asset_name'] as String?;
      final retainedCover =
          embeddedAssets?.any((asset) => asset.name == previousCover) == true
          ? previousCover
          : null;
      await db.transaction((txn) async {
        if (embeddedAssets != null) {
          await LibraryDocumentAssets.store(
            txn,
            itemId: libraryItemId,
            sourceHash: sourceHash,
            assets: embeddedAssets,
            coverAssetName: retainedCover,
          );
        }
        await _requirePreservedMarkupTargets(txn, libraryItemId, stagedBlocks);
        await _requirePreservedSavedPosition(txn, libraryItemId, stagedBlocks);
        await txn.delete(
          'library_document_navigation',
          where: 'library_item_id = ?',
          whereArgs: [libraryItemId],
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
        for (final row in stagedSections) {
          await txn.insert('library_document_sections', row);
        }
        for (final row in stagedBlocks) {
          await txn.insert('library_document_blocks', row);
        }
        for (final row in stagedNavigation) {
          await txn.insert('library_document_navigation', row);
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

  List<Map<String, Object?>> _navigationRows(
    String itemId,
    Archive? archive,
    List<Map<String, Object?>> blocks,
  ) {
    if (archive == null) return [];
    final targets = EpubInternalAnchorSectionSplitter.readNavigationTargets(
      archive: archive,
      fallbackTitle: 'Contents',
    );
    final byTarget = <String, List<String>>{};
    final firstByFile = <String, String>{};
    final ordered = blocks.toList()
      ..sort(
        (a, b) =>
            (a['display_order'] as int).compareTo(b['display_order'] as int),
      );
    for (final block in ordered) {
      final href = block['source_href']?.toString() ?? '';
      final id = block['id'].toString();
      firstByFile.putIfAbsent(href, () => id);
      final anchor = block['source_anchor']?.toString() ?? '';
      final formatted = LibraryFormattedContent.fromJson(
        block['formatted_content']?.toString(),
      );
      final aliases =
          formatted.metadata['source_anchor_aliases'] as List? ?? const [];
      for (final sourceAnchor in {
        anchor,
        ...aliases.whereType<String>(),
      }.where((value) => value.isNotEmpty)) {
        byTarget.putIfAbsent('$href#$sourceAnchor', () => []).add(id);
      }
    }
    final parents = <({int depth, String id})>[];
    return [
      for (var index = 0; index < targets.length; index++)
        (() {
          final target = targets[index];
          final href = normalizeLibrarySourceHref(target.path);
          final id = _stableId([
            'navigation',
            itemId,
            href,
            target.anchor,
            '$index',
          ]);
          while (parents.isNotEmpty && parents.last.depth >= target.depth) {
            parents.removeLast();
          }
          final parentId = parents.isEmpty ? null : parents.last.id;
          final matches = byTarget['$href#${target.anchor}'] ?? [];
          final blockId = target.anchor.isEmpty
              ? firstByFile[href]
              : matches.length == 1
              ? matches.single
              : null;
          final row = <String, Object?>{
            'id': id, 'library_item_id': itemId, 'parent_id': parentId,
            'label': target.title,
            'depth': target.depth,
            'display_order': index,
            'source_href': href, 'source_anchor': target.anchor,
            // Keep unresolved authored destinations visible to import audits.
            'target_block_id': blockId,
          };
          parents.add((depth: target.depth, id: id));
          return row;
        })(),
    ];
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
          textStyles: EpubTextStyles.read(
            utf8.decode(bytes, allowMalformed: true),
            p.basename(path),
            null,
          ),
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
      final textStyles = EpubTextStyles.read(html, entry.name, archive);
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
      for (
        var splitIndex = 0;
        splitIndex < splitSections.length;
        splitIndex++
      ) {
        final split = splitSections[splitIndex];
        sections.add(
          LibraryCanonicalSourceSection(
            href: entry.name,
            title: split.title,
            html: split.html,
            textStyles: textStyles,
            numericHeadingTargets: [
              for (final target in targets ?? const <EpubAnchorTarget>[])
                if (RegExp(r'^\d{1,4}$').hasMatch(target.title.trim()) &&
                    (target.anchor.isNotEmpty || splitIndex == 0))
                  target,
            ],
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
      final encodedPath = href.split(RegExp(r'[?#]')).first;
      String hrefPath;
      try {
        hrefPath = Uri.decodeComponent(encodedPath);
      } on FormatException {
        hrefPath = encodedPath;
      }
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

  Map<String, Object?> get referenceColumns {
    final parts = RegExp(
      r'^([A-Za-z0-9]+)\s+(\d+)\.(\d+)$',
    ).firstMatch(refcode?.trim() ?? '');
    return {
      'reference_prefix': parts?.group(1),
      'reference_page': parts == null ? null : int.parse(parts.group(2)!),
      'reference_paragraph': parts == null ? null : int.parse(parts.group(3)!),
      'reference_origin': refcode == null
          ? null
          : formatted.metadata['reference_origin'] ?? 'source_embedded',
      'reference_witness': formatted.metadata['reference_witness'],
      'reference_context': formatted.metadata['reference_context'],
      'content_role': formatted.metadata['content_role'],
    };
  }

  _ParsedCanonicalBlock withRefcode(String value) => _ParsedCanonicalBlock(
    type: type,
    text: text,
    formatted: formatted,
    anchor: anchor,
    refcode: value,
  );

  _ParsedCanonicalBlock withVerifiedReferenceCode(
    String code,
    Map<String, Object?> witness,
  ) => _ParsedCanonicalBlock(
    type: type,
    text: text,
    anchor: anchor,
    refcode: code,
    formatted: LibraryFormattedContent(
      nodes: formatted.nodes,
      alignment: formatted.alignment,
      metadata: {
        ...formatted.metadata,
        'reference_origin': 'verified_source_alignment',
        'reference_prefix': witness['work_prefix'],
        'reference_page': witness['page_number'],
        'reference_paragraph': witness['paragraph_number'],
        'reference_witness': witness['witness_uri'],
        'reference_match_method': witness['match_method'],
        if (witness['reference_context'] != null)
          'reference_context': witness['reference_context'],
      },
    ),
  );

  _ParsedCanonicalBlock withPageMarker(String value) => _ParsedCanonicalBlock(
    type: type,
    text: text,
    formatted: LibraryFormattedContent(
      nodes: formatted.nodes,
      alignment: formatted.alignment,
      metadata: <String, Object?>{
        ...formatted.metadata,
        // A printed-page boundary that immediately precedes this readable
        // block. It stays available to a future page-aware reader without
        // becoming a disruptive line in the reading flow.
        'source_page_marker': value,
      },
    ),
    anchor: anchor,
    refcode: refcode,
  );

  _ParsedCanonicalBlock withSyntheticReferenceCode(
    String value, {
    String origin = 'synthetic_source_page_marker',
  }) => _ParsedCanonicalBlock(
    type: type,
    text: text,
    formatted: LibraryFormattedContent(
      nodes: formatted.nodes,
      alignment: formatted.alignment,
      metadata: <String, Object?>{
        ...formatted.metadata,
        'reference_origin': origin,
      },
    ),
    anchor: anchor,
    refcode: value,
  );
}

const Map<String, String>
_pioneerSyntheticReferenceDesignators = <String, String>{
  'a tract, showing that the seventh day should be observed as the sabbath, instead of the first day':
      'TSD',
  'american sentinel articles (1886-1899)': 'ASA',
  'christ our righteousness': 'COR',
  'general conference bulletin articles (1889-1903)': 'GCB',
  'the advent review and sabbath herald (1879-1880)': 'ARH',
  'the american sentinel (1887)': 'AS87',
  'the american sentinel (1894)': 'AS94',
  'the gospel in the book of galatians': 'GIG',
  'the signs of the times (1884-1885)': 'ST84',
  'the signs of the times (1890-1891)': 'ST90',
  'the signs of the times (1891-1895)': 'ST91',
  'the southern sentinel and herald of liberty articles (1895-1897)': 'SSHL',
};

Future<String?> _pioneerSyntheticReferenceDesignator(
  Database db,
  String libraryItemId,
) async {
  final rows = await db.query(
    'library_items',
    columns: const <String>['title', 'source_type'],
    where: 'id = ?',
    whereArgs: <Object?>[libraryItemId],
    limit: 1,
  );
  if (rows.isEmpty ||
      rows.single['source_type']?.toString().trim().toLowerCase() !=
          'pioneer_epub_import') {
    return null;
  }
  final title = rows.single['title']?.toString().trim().toLowerCase() ?? '';
  return _pioneerSyntheticReferenceDesignators[title];
}

/// Synthesizes citations for the approved Pioneer page-marker cohort only.
///
/// A marker is metadata on the first following readable block, so it is
/// applied before that block receives its code. A body block always retains
/// the page at which it began; a later marker therefore resets the counter
/// only for following body blocks.
class _SyntheticPageMarkerReferenceTracker {
  _SyntheticPageMarkerReferenceTracker(this.designator);

  final String designator;
  int? _page;
  int _paragraphOnPage = 0;

  _ParsedCanonicalBlock referenceCodeFor(_ParsedCanonicalBlock block) {
    final marker = block.formatted.metadata['source_page_marker']?.toString();
    final markerPage = int.tryParse(marker?.trim() ?? '');
    if (markerPage != null && markerPage > 0) {
      _page = markerPage;
      _paragraphOnPage = 0;
    }
    if (block.refcode?.trim().isNotEmpty == true ||
        !_isCitableBodyBlock(block) ||
        _page == null) {
      return block;
    }
    _paragraphOnPage++;
    return block.withSyntheticReferenceCode(
      '$designator $_page.$_paragraphOnPage',
    );
  }
}

bool _isCitableBodyBlock(_ParsedCanonicalBlock block) => switch (block.type) {
  LibraryDocumentBlockType.paragraph ||
  LibraryDocumentBlockType.listItem ||
  LibraryDocumentBlockType.quotation ||
  LibraryDocumentBlockType.poem => block.text.trim().isNotEmpty,
  _ => false,
};

List<_ParsedCanonicalBlock> _parseHtmlBlocks(
  String html, {
  EpubTextStyles textStyles = const EpubTextStyles.empty(),
  _EpubRefCodeTracker? refCodeTracker,
  _SourcePageTracker? sourcePageTracker,
  List<EpubAnchorTarget> numericHeadingTargets = const [],
  bool linkCitations = true,
}) {
  if (RegExp(
    r'''class\s*=\s*["'][^"']*\bclip-text\b''',
    caseSensitive: false,
  ).hasMatch(html)) {
    final captured = _parseCapturedEgwBlocks(html);
    if (captured.isNotEmpty) return captured;
  }
  return _parseSemanticHtmlBlocks(
    html,
    textStyles: textStyles,
    refCodeTracker: refCodeTracker,
    sourcePageTracker: sourcePageTracker,
    numericHeadingTargets: numericHeadingTargets,
    linkCitations: linkCitations,
  );
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

/// Older Pioneer exports use a leaf DIV wherever other EPUBs use P.
/// Normalize only those leaf containers in the parsing copy. A surrounding
/// layout DIV must never consume its child paragraphs or duplicate their text.
/// Source bytes, attributes and inline descendants remain unchanged.
String _normalizeLeafDivBlocks(String html) {
  final stack = <({RegExpMatch open, bool hasBlockChild})>[];
  final replacements = <({int start, int end, String value})>[];
  final tags = RegExp(
    r'<(/?)(div|h[1-6]|p|blockquote|pre|li|ul|ol|table|section|article|figure|img|hr)\b[^>]*>',
    caseSensitive: false,
  );
  for (final tag in tags.allMatches(html)) {
    final name = tag.group(2)!.toLowerCase();
    final closing = tag.group(1) == '/';
    if (!closing) {
      if (stack.isNotEmpty) {
        final parent = stack.removeLast();
        stack.add((open: parent.open, hasBlockChild: true));
      }
      if (name == 'div' && !tag.group(0)!.endsWith('/>')) {
        stack.add((open: tag, hasBlockChild: false));
      }
    } else if (name == 'div' && stack.isNotEmpty) {
      final frame = stack.removeLast();
      if (frame.hasBlockChild) continue;
      final opening = frame.open.group(0)!;
      replacements.add((
        start: frame.open.start,
        end: frame.open.end,
        value: '<p data-source-tag="div"${opening.substring(4)}',
      ));
      replacements.add((start: tag.start, end: tag.end, value: '</p>'));
    }
  }
  // Offsets are source offsets; replacing from the end keeps them valid.
  replacements.sort((a, b) => b.start.compareTo(a.start));
  for (final replacement in replacements) {
    html = html.replaceRange(
      replacement.start,
      replacement.end,
      replacement.value,
    );
  }
  return html;
}

int _imageRotationDegrees(String attributes) {
  final raw = _attribute(attributes, 'data-image-rotation');
  if (raw == null) return 0;
  final degrees = int.tryParse(raw.trim());
  if (degrees == null || !const [0, 90, 180, 270].contains(degrees)) {
    throw StateError(
      'Unsupported image orientation "$raw". Expected clockwise degrees '
      '0, 90, 180 or 270; the prior reading generation is retained.',
    );
  }
  return degrees;
}

List<_ParsedCanonicalBlock> _parseSemanticHtmlBlocks(
  String html, {
  EpubTextStyles textStyles = const EpubTextStyles.empty(),
  _EpubRefCodeTracker? refCodeTracker,
  _SourcePageTracker? sourcePageTracker,
  List<EpubAnchorTarget> numericHeadingTargets = const [],
  bool linkCitations = true,
}) {
  // A split section can contain only the document head and a page boundary.
  // Head/style/script text is not book prose, even when it contains HTML-like
  // strings. Remove it before looking for readable blocks or fallback text.
  html = html
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(
        RegExp(
          r'<(head|style|script|title)\b[^>]*>.*?</\1\s*>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      );
  html = _normalizeLeafDivBlocks(html);
  final pattern = RegExp(
    r'<(table|h[1-6]|p|blockquote|pre|li|img|hr)\b([^>]*)>(?:(.*?)</\1\s*>)?',
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
  var hasReadableHeading = false;
  for (final match in pattern.allMatches(html)) {
    var tag = match.group(1)!.toLowerCase();
    var attrs = match.group(2) ?? '';
    var inner = match.group(3) ?? '';
    String? wrapperAttrs;
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
    // Image-only paragraphs are layout wrappers, not empty prose. Preserve
    // the real image through the same extraction path as a standalone IMG.
    // Keep wrapper attributes for citation/alignment and both source anchors.
    if (tag == 'p') {
      final image = RegExp(
        r'^(?:\s|&(?:nbsp|#160|#xA0);)*<img\b([^>]*)>(?:\s|&(?:nbsp|#160|#xA0);)*$',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(inner);
      if (image != null) {
        wrapperAttrs = attrs;
        attrs = '${image.group(1)!} $attrs';
        tag = 'img';
        inner = '';
      }
    }
    if (tag != 'img' &&
        RegExp(r'<img\b', caseSensitive: false).hasMatch(inner)) {
      throw StateError(
        'Nested image layout is not supported without losing content. '
        'The source and any previous reading generation are retained for review.',
      );
    }
    // Keep `inner` unstripped for the pagebreak refcode tracker below (it
    // needs to see pagebreak markers), but derive prose text/nodes from a
    // copy with any refcode marker span removed.
    final proseInner = _stripRefCodeSpans(inner);
    final tableRows = tag == 'table'
        ? _tableRows(proseInner, textStyles)
        : null;
    final text = tag == 'img'
        ? (_attribute(attrs, 'alt') ?? '')
        : tableRows != null
        ? tableRows
              .map((row) => row.map((cell) => cell['text']).join('\t'))
              .join('\n')
        : _plain(proseInner);
    // A numeric heading can be an authored section, such as a year. Require
    // the source Contents to name this exact file/fragment and numeric label;
    // never infer a year from its value or a book's title. Explicit pagebreak
    // semantics take precedence over that evidence.
    final isStandaloneNumber = RegExp(r'^\d{1,4}$').hasMatch(text);
    final explicitPageBreak =
        _attribute(attrs, 'epub:type') == 'pagebreak' ||
        _attribute(attrs, 'role') == 'doc-pagebreak';
    final authoredNumber =
        !explicitPageBreak &&
        numericHeadingTargets.any((target) {
          if (target.title.trim() != text) return false;
          if (target.anchor.isEmpty) return !hasReadableHeading;
          if (target.anchor == pendingAnchor ||
              target.anchor == _attribute(attrs, 'id')) {
            return true;
          }
          return RegExp(r'<(?:span|a)\b[^>]*>', caseSensitive: false)
              .allMatches(inner)
              .any(
                (marker) =>
                    _attribute(marker.group(0)!, 'id') == target.anchor ||
                    _attribute(marker.group(0)!, 'name') == target.anchor,
              );
        });
    final isBarePageNumber =
        tag.startsWith('h') && isStandaloneNumber && !authoredNumber;
    // These elements are print-layout anchors, not reader content. Keeping
    // them as paragraphs made books such as Acts of the Apostles render
    // hundreds of consecutive page numbers, one per line. A real numbered
    // heading remains intact when it has punctuation or descriptive text.
    if (isBarePageNumber) {
      // The old parser discarded these page boundaries outright.
      sourcePageTracker?.recordPage(text);
      continue;
    }
    if (tag.startsWith('h')) hasReadableHeading = true;
    // A reviewed source can explicitly mark an unpaginated gap. Do not carry
    // the preceding page number into that material or guess a replacement.
    if (_attribute(attrs, 'data-source-page-reset') == 'true') {
      sourcePageTracker?.reset();
    }
    final pageMetadata =
        sourcePageTracker?.metadataFor(inner) ?? const <String, Object?>{};
    final className = _attribute(attrs, 'class');
    final isChapterOutline = RegExp(
      r'(?:^|\s)chapter[-_]summary(?:\s|$)',
      caseSensitive: false,
    ).hasMatch(className ?? '');
    final headingClass = RegExp(
      r'(?:^|\s)heading[-_]([1-6])(?:\s|$)',
      caseSensitive: false,
    ).firstMatch(className ?? '');
    final isPartHeading = RegExp(
      r'(?:^|\s)header-main(?:\s|$)',
      caseSensitive: false,
    ).hasMatch(className ?? '');
    final isClassHeading =
        tag == 'p' && (headingClass != null || isPartHeading);
    final type = switch (tag) {
      'blockquote' => LibraryDocumentBlockType.quotation,
      'pre' => LibraryDocumentBlockType.poem,
      'li' => LibraryDocumentBlockType.listItem,
      'img' => LibraryDocumentBlockType.image,
      'hr' => LibraryDocumentBlockType.horizontalRule,
      _ when tag.startsWith('h') || isClassHeading =>
        LibraryDocumentBlockType.heading,
      _ => LibraryDocumentBlockType.paragraph,
    };
    if (text.isEmpty &&
        type != LibraryDocumentBlockType.image &&
        type != LibraryDocumentBlockType.horizontalRule) {
      continue;
    }
    final alignment =
        textStyles.resolveAlignment(tag, attrs) ??
        _alignment(attrs, className) ??
        (wrapperAttrs == null
            ? null
            : textStyles.resolveAlignment('p', wrapperAttrs) ??
                  _alignment(wrapperAttrs, _attribute(wrapperAttrs, 'class')));
    final imageRotation = type == LibraryDocumentBlockType.image
        ? _imageRotationDegrees(attrs)
        : 0;
    final nodes = type == LibraryDocumentBlockType.image
        ? <Map<String, Object?>>[
            <String, Object?>{
              'type': 'image',
              'source': _attribute(attrs, 'src') ?? '',
              'alt': text,
              if (imageRotation != 0) 'rotation_degrees': imageRotation,
            },
          ]
        : tableRows != null
        ? <Map<String, Object?>>[
            for (var r = 0; r < tableRows.length; r++) ...[
              if (r > 0) {'type': 'line_break'},
              for (var c = 0; c < tableRows[r].length; c++) ...[
                if (c > 0) {'type': 'text', 'text': '\t'},
                ...(tableRows[r][c]['nodes'] as List<Map<String, Object?>>),
              ],
            ],
          ]
        : _inlineNodes(
            proseInner,
            linkCitations: linkCitations,
            className: className,
            textStyles: textStyles,
            blockStyle: textStyles.resolve(
              _attribute(attrs, 'data-source-tag') ?? tag,
              attrs,
            ),
          );
    final explicitChapter =
        type == LibraryDocumentBlockType.heading &&
        RegExp(
          r'^chapter\s+(?:\d+|[ivxlcdm]+)\b',
          caseSensitive: false,
        ).hasMatch(text.trim());
    final headingRole = explicitChapter
        ? 'chapter'
        : isClassHeading
        ? (isPartHeading
              ? 'part'
              : headingClass?.group(1) == '1'
              ? 'chapter'
              : 'section')
        : switch (tag) {
            'h1' => 'book_title',
            'h2' => 'chapter',
            'h3' => 'section',
            'h4' || 'h5' || 'h6' => 'minor',
            _ => null,
          };
    if (headingRole == 'chapter') refCodeTracker?.beginBody();
    final embeddedCode = _attribute(attrs, 'data-refcode');
    final derivedCode =
        embeddedCode == null && type == LibraryDocumentBlockType.paragraph
        ? refCodeTracker?.referenceCodeFor(inner)
        : null;
    final anchor =
        pendingAnchor ??
        (wrapperAttrs == null ? null : _attribute(wrapperAttrs, 'id')) ??
        _attribute(attrs, 'id') ??
        _attribute(
          RegExp(
                r'<(?:span|a)\b[^>]*>',
                caseSensitive: false,
              ).firstMatch(inner)?.group(0) ??
              '',
          'id',
        );
    // A paragraph can contain several independently linked page/footnote
    // anchors. Keep them even when their marker text is omitted from prose.
    // Preserve the existing primary anchor and block identity.
    final anchorAliases =
        {
              if (wrapperAttrs != null) _attribute(wrapperAttrs, 'id'),
              _attribute(attrs, 'id'),
              for (final marker in RegExp(
                r'<[a-z][a-z0-9:_-]*\b[^>]*>',
                caseSensitive: false,
              ).allMatches(inner)) ...[
                _attribute(marker.group(0)!, 'id'),
                if (RegExp(
                  r'^<a\b',
                  caseSensitive: false,
                ).hasMatch(marker.group(0)!))
                  _attribute(marker.group(0)!, 'name'),
              ],
            }
            .whereType<String>()
            .where((value) => value.isNotEmpty && value != anchor)
            .toList();
    result.add(
      _ParsedCanonicalBlock(
        type: type,
        text: text,
        formatted: LibraryFormattedContent(
          nodes: nodes,
          alignment: alignment,
          metadata: (<String, Object?>{
            'source_tag': _attribute(attrs, 'data-source-tag') ?? tag,
            if (tableRows != null) 'table_rows': tableRows,
            if (textStyles.resolveFontScale(tag, attrs) case final scale?)
              'relative_font_scale': scale,
            if (textStyles.resolveFontScale(tag, attrs) != null)
              'font_scale_basis': 'body',
            'source_class': className,
            if (tag == 'p' &&
                alignment == 'center' &&
                textStyles.hasCompactVerticalMargins(tag, attrs))
              'compact_centered_paragraph': true,
            if (wrapperAttrs != null) 'source_wrapper_tag': 'p',
            if (wrapperAttrs != null &&
                _attribute(wrapperAttrs, 'class') != null)
              'source_wrapper_class': _attribute(wrapperAttrs, 'class'),
            if (anchorAliases.isNotEmpty)
              'source_anchor_aliases': anchorAliases,
            if (_attribute(attrs, 'data-index-entry-group') != null)
              'source_index_entry_group': _attribute(
                attrs,
                'data-index-entry-group',
              ),
            if (_attribute(attrs, 'data-index-letter') != null)
              'source_index_letter': _attribute(attrs, 'data-index-letter'),
            if (_attribute(attrs, 'data-text-witness') != null)
              'text_witness': _attribute(attrs, 'data-text-witness'),
            if (isChapterOutline) 'content_role': 'chapter_outline',
            if (_attribute(attrs, 'data-reference-context') != null)
              'reference_context': _attribute(attrs, 'data-reference-context'),
            if (_attribute(attrs, 'data-reference-witness') != null)
              'reference_witness': _attribute(attrs, 'data-reference-witness'),
            if (_attribute(attrs, 'data-reference-origin') != null)
              'reference_origin': _attribute(attrs, 'data-reference-origin'),
            if (derivedCode != null)
              'reference_origin': 'synthetic_epub_pagebreak',
            ...pageMetadata,
            'classification_reason': tag.startsWith('h')
                ? 'explicit semantic heading element'
                : 'semantic HTML block',
            'heading_role': headingRole,
          }..removeWhere((_, value) => value == null)),
        ),
        anchor: anchor,
        refcode: embeddedCode ?? derivedCode,
      ),
    );
    pendingAnchor = null;
  }
  if (result.isEmpty) {
    // Recognized blocks were intentionally omitted (for example a lone
    // printed page number). Do not resurrect them as fallback prose. Keep
    // genuine unwrapped body text that remains outside those elements.
    final text = _plain(html.replaceAll(pattern, ''));
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
  return _extractStandalonePageMarkers(result);
}

/// Removes a print-layout page number only when its source shape makes it a
/// standalone interruption in otherwise readable flow.  List items are never
/// candidates: a lone number in an `<li>` is ordinary list content.  Likewise
/// a verse-class paragraph remains content even if it contains only a number.
///
/// The marker is retained on the following readable block as
/// `formatted_content.metadata.source_page_marker`, which represents the page
/// boundary immediately before that block.
List<_ParsedCanonicalBlock> _extractStandalonePageMarkers(
  List<_ParsedCanonicalBlock> blocks,
) {
  if (blocks.length < 3) return blocks;
  final extracted = <_ParsedCanonicalBlock>[];
  for (var index = 0; index < blocks.length; index++) {
    final block = blocks[index];
    final marker = _standalonePageMarker(block);
    if (marker == null ||
        index == 0 ||
        index == blocks.length - 1 ||
        !_isPageMarkerPredecessor(blocks[index - 1]) ||
        !_isReadingFlowBlock(blocks[index + 1])) {
      extracted.add(block);
      continue;
    }
    // The next iteration writes the marker to the following readable block.
    final next = blocks[index + 1].withPageMarker(marker);
    blocks[index + 1] = next;
  }
  return extracted;
}

// A print page can begin immediately after a chapter/section heading. The
// dedicated standalone-number shape remains required, so admitting headings
// here preserves that real page boundary without treating ordinary numbered
// prose as a marker.
bool _isPageMarkerPredecessor(_ParsedCanonicalBlock block) =>
    _isReadingFlowBlock(block) ||
    block.type == LibraryDocumentBlockType.heading;

String? _standalonePageMarker(_ParsedCanonicalBlock block) {
  if (block.type != LibraryDocumentBlockType.paragraph) return null;
  final tag = block.formatted.metadata['source_tag']?.toString().toLowerCase();
  if (tag != 'p') return null;
  final className =
      block.formatted.metadata['source_class']?.toString().toLowerCase() ?? '';
  if (RegExp(r'\b(?:verse|scripture|bible)\b').hasMatch(className)) return null;
  final text = block.text.trim();
  // Plain digits, optional surrounding brackets, or a conventional `p. 57`
  // token are the print-page forms encountered in EPUB exports. Keep this
  // deliberately narrow so numbered prose is not reclassified as metadata.
  final match = RegExp(
    r'^(?:\[\s*)?(?:p(?:age)?\.?\s*)?(\d{1,4})(?:\s*\])?$',
  ).firstMatch(text);
  return match?.group(1);
}

bool _isReadingFlowBlock(_ParsedCanonicalBlock block) => switch (block.type) {
  LibraryDocumentBlockType.paragraph ||
  LibraryDocumentBlockType.listItem ||
  LibraryDocumentBlockType.quotation ||
  LibraryDocumentBlockType.poem => block.text.trim().isNotEmpty,
  _ => false,
};

/// Records only source page boundaries. Paragraph numbers are not invented.
/// Nonsemantic colored markers require a profile tied to the exact source hash.
class _SourcePageTracker {
  _SourcePageTracker({this.spanClass});
  final String? spanClass;
  int? _page;
  void reset() => _page = null;
  void recordPage(String value) {
    final page = int.tryParse(value);
    if (page != null && page > 0) _page = page;
  }

  Map<String, Object?> metadataFor(String html) {
    var start = _page;
    for (final marker in RegExp(
      r'<span\b([^>]*)>(.*?)</span\s*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html)) {
      final attrs = marker.group(1) ?? '';
      final classes = (_attribute(attrs, 'class') ?? '').split(RegExp(r'\s+'));
      final semantic =
          _attribute(attrs, 'epub:type') == 'pagebreak' ||
          _attribute(attrs, 'role') == 'doc-pagebreak';
      final profiled = spanClass != null && classes.contains(spanClass);
      if (!semantic && !profiled) continue;
      final raw = semantic
          ? (_attribute(attrs, 'title') ??
                _attribute(attrs, 'aria-label') ??
                _plain(marker.group(2)!))
          : _plain(marker.group(2)!);
      final match = RegExp(r'^\[?(\d{1,4})\]?$').firstMatch(raw.trim());
      if (match == null) continue;
      recordPage(match.group(1)!);
      if (_plain(html.substring(0, marker.start)).isEmpty) start = _page;
    }
    return {
      if (start != null) 'source_page_start': start,
      if (_page != null) 'source_page_end': _page,
      if (start != null || _page != null)
        'page_reference_origin': 'source_printed_page',
    };
  }
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
/// Recovery requires the number to match the next expected chapter within
/// a source-identified part. Explicit Daniel/Revelation part openers reset
/// the sequence; an isolated number 1 in body prose never does so.
/// Within each part, strict monotonic sequence — the same technique already used for the
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
  final Set<String> _seenParts = {};

  // These are structural labels present verbatim in this combined work's
  // source. Require a paragraph-start label, never a title/filename identity
  // guess or an arbitrary chapter-number decrease in prose.
  static final _partOpening = RegExp(
    r'^Response of History to (?:the Prophecy of Daniel|the Revelation)\b',
    caseSensitive: false,
  );

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
      // A printed contents list is evidence, not the chapter body. Its
      // repeated number/title runs must not advance the recovery sequence.
      if (RegExp(
        r'^(?:table of contents|contents)\b',
        caseSensitive: false,
      ).hasMatch(block.text.trim())) {
        result.add(block);
        continue;
      }
      final part = _partOpening.firstMatch(block.text);
      if (part != null && _seenParts.add(part.group(0)!.toLowerCase())) {
        _expectedChapter = 1;
        changed = true;
        final className = block.formatted.nodes.first['class'] as String?;
        result.add(
          _ocrRecoveredHeading(
            part.group(0)!,
            className: className,
            role: 'part',
          ),
        );
        final remaining = block.text.substring(part.end).trim();
        if (remaining.isNotEmpty) {
          result.addAll(
            _splitForHeadings(
              _ocrPlainParagraph(remaining, className: className),
            ),
          );
        }
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
    final nextCore = i + 1 < tokens.length
        ? tokens[i + 1]
              .group(0)!
              .replaceAll(RegExp(r'^[^A-Za-z]+|[^A-Za-z]+$'), '')
        : '';
    final singleLetterInTitle =
        (core == 'A' || core == 'I') &&
        nextCore.length >= 2 &&
        nextCore == nextCore.toUpperCase();
    final isUpperWord =
        (core.length >= 2 || singleLetterInTitle) &&
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

_ParsedCanonicalBlock _ocrRecoveredHeading(
  String text, {
  String? className,
  String role = 'chapter',
}) => _ParsedCanonicalBlock(
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
    metadata: <String, Object?>{
      'source_tag': 'p',
      'heading_role': role,
      'classification_reason': role == 'part'
          ? 'explicit source part opener'
          : 'recovered from unmarked OCR chapter-number title run',
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

/// Initial identity is SHA-256 over version, work, normalized locator,
/// optional source anchor, semantic type, and zero-based source ordinal.
/// Content is deliberately excluded and is tracked by content_hash instead.
/// Updates reconcile these candidate IDs with proven prior block identities.
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

List<List<Map<String, Object?>>> _tableRows(
  String html,
  EpubTextStyles styles,
) {
  if (RegExp(r'<table\b', caseSensitive: false).hasMatch(html)) {
    throw StateError('Nested tables require review; source retained.');
  }
  final rows = <List<Map<String, Object?>>>[];
  for (final row in RegExp(
    r'<tr\b[^>]*>(.*?)</tr\s*>',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(html)) {
    final cells = <Map<String, Object?>>[];
    for (final cell in RegExp(
      r'<(td|th)\b([^>]*)>(.*?)</\1\s*>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(row.group(1)!)) {
      final attrs = cell.group(2)!;
      final rowspan = int.tryParse(_attribute(attrs, 'rowspan') ?? '1');
      if (rowspan != 1) {
        throw StateError(
          'Row-spanning table requires review; source retained.',
        );
      }
      final colspan = int.tryParse(_attribute(attrs, 'colspan') ?? '1');
      if (colspan == null || colspan < 1 || colspan > 24) {
        throw StateError('Unsupported table column span; source retained.');
      }
      final content = cell
          .group(3)!
          .replaceAll(
            RegExp(r'</(?:p|div)>\s*(?=<(?:p|div)\b)', caseSensitive: false),
            '<br/>',
          );
      cells.add({
        'text': _plain(content),
        'colspan': colspan,
        'header': cell.group(1)!.toLowerCase() == 'th',
        'alignment':
            styles.resolveAlignment(cell.group(1)!.toLowerCase(), attrs) ??
            _alignment(attrs, _attribute(attrs, 'class')),
        'nodes': _inlineNodes(
          content,
          textStyles: styles,
          blockStyle: styles.resolve(cell.group(1)!.toLowerCase(), attrs),
        ),
      });
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty)
    throw StateError('Empty or malformed table requires review.');
  // Captions are not cells: reject rather than silently dropping their text.
  if (RegExp(r'<caption\b', caseSensitive: false).hasMatch(html)) {
    throw StateError('Table caption requires review; source retained.');
  }
  return rows;
}

List<Map<String, Object?>> _inlineNodes(
  String html, {
  String? className,
  EpubTextStyles textStyles = const EpubTextStyles.empty(),
  Map<String, bool> blockStyle = const {},
  bool linkCitations = true,
}) {
  final nodes = <Map<String, Object?>>[];
  final tokens = RegExp(r'(<[^>]+>|[^<]+)', dotAll: true).allMatches(html);
  final frames =
      <({String tag, Map<String, bool> style, String? link, double scale})>[];
  for (final token in tokens) {
    final value = token.group(0)!;
    if (value.startsWith('<')) {
      final lower = value.toLowerCase();
      if (RegExp(r'^<br\b').hasMatch(lower)) {
        nodes.add(<String, Object?>{'type': 'line_break'});
        continue;
      }
      final closing = RegExp(r'^</([a-z0-9]+)').firstMatch(lower)?.group(1);
      if (closing != null) {
        final index = frames.lastIndexWhere((frame) => frame.tag == closing);
        if (index >= 0) frames.removeRange(index, frames.length);
        continue;
      }
      final tag = RegExp(r'^<([a-z0-9]+)').firstMatch(lower)?.group(1);
      if (tag == null ||
          value.endsWith('/>') ||
          const {'img', 'hr', 'wbr', 'input', 'meta', 'link'}.contains(tag)) {
        continue;
      }
      // Track unstyled elements too: </span> must not close an outer <em>.
      frames.add((
        tag: tag,
        scale:
            ((frames.isEmpty ? 1.0 : frames.last.scale) *
                    (textStyles.resolveFontScale(tag, value) ?? 1.0))
                .clamp(0.7, 2.0)
                .toDouble(),
        style: textStyles.resolve(
          tag,
          value,
          inherited: frames.isEmpty ? blockStyle : frames.last.style,
        ),
        link: tag == 'a'
            ? _attribute(value, 'href')
            : (_attribute(value, 'class') ?? '')
                  .split(RegExp(r'\s+'))
                  .contains('cis-inline-bible')
            ? 'studybible-citation:${Uri.encodeComponent(_inlineElementText(html, token.end, tag))}'
            : null,
      ));
      continue;
    }
    final styles = (frames.isEmpty ? blockStyle : frames.last.style).entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();
    final links = frames.map((frame) => frame.link).whereType<String>();
    final linkHref = links.isEmpty ? null : links.last;
    // Unlike _plain(), inline text must retain source whitespace at token
    // boundaries. A styled span commonly divides ordinary prose between the
    // word and its following space; trimming each token would fuse the words
    // when the reader concatenates these nodes.
    final text = _inlineText(value);
    if (text.isEmpty) continue;
    nodes.add(<String, Object?>{
      'type': 'text',
      'text': text,
      if (frames.isNotEmpty && frames.last.scale != 1.0)
        'relative_font_scale': frames.last.scale,
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
  final normalized = _normalizeInlineNodeWhitespace(nodes);
  return linkCitations ? linkLibraryCitations(normalized) : normalized;
}

String _inlineText(String html) =>
    decodeXmlHtmlEntities(html).replaceAll(RegExp(r'\s+'), ' ');

String _inlineElementText(String html, int start, String tag) {
  var depth = 1;
  for (final match in RegExp(
    '</?$tag\\b[^>]*>',
    caseSensitive: false,
  ).allMatches(html, start)) {
    final token = match.group(0)!;
    if (token.startsWith('</')) {
      depth--;
      if (depth == 0) return _plain(html.substring(start, match.start)).trim();
    } else if (!token.endsWith('/>')) {
      depth++;
    }
  }
  return ''; // Malformed marked citation remains unresolved, never guessed.
}

List<Map<String, Object?>> _normalizeInlineNodeWhitespace(
  List<Map<String, Object?>> nodes,
) {
  Map<String, Object?>? previousText;
  var afterLineBreak = true;
  final normalized = <Map<String, Object?>>[];

  for (final node in nodes) {
    if (node['type'] == 'line_break') {
      if (previousText != null) {
        previousText['text'] = previousText['text']!.toString().trimRight();
      }
      normalized.add(node);
      previousText = null;
      afterLineBreak = true;
      continue;
    }
    if (node['type'] != 'text') {
      normalized.add(node);
      continue;
    }

    var text = node['text']!.toString();
    if (afterLineBreak) text = text.trimLeft();
    if (previousText != null && text.startsWith(' ')) {
      if (previousText['text']!.toString().endsWith(' ')) {
        text = text.trimLeft();
      }
    }
    // Whitespace before closing punctuation is never a visible prose
    // boundary, even if formatting/indentation introduced it in the source.
    if (RegExp(r'^\s*[,.;:!?)\]\}]').hasMatch(text)) {
      previousText?['text'] = previousText['text']!.toString().trimRight();
      text = text.trimLeft();
    }
    if (text.isEmpty) continue;

    final normalizedNode = Map<String, Object?>.from(node)..['text'] = text;
    normalized.add(normalizedNode);
    previousText = normalizedNode;
    afterLineBreak = false;
  }

  for (var index = normalized.length - 1; index >= 0; index--) {
    final node = normalized[index];
    if (node['type'] == 'line_break') break;
    if (node['type'] == 'text') {
      node['text'] = node['text']!.toString().trimRight();
      if (node['text']!.toString().isEmpty) normalized.removeAt(index);
      break;
    }
  }
  return normalized
      .where(
        (node) => node['type'] != 'text' || node['text']!.toString().isNotEmpty,
      )
      .toList();
}
