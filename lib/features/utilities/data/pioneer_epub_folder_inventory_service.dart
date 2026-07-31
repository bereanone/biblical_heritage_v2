import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/elibrary_database.dart';
import '../../library/data/library_document_canonicalizer.dart';
import '../../library/data/library_document_repository.dart';
import '../../library/data/library_item_identity.dart';
import '../../library/data/library_book_display_title.dart';
import 'elibrary_folder_policy.dart';
import 'epub_download_validator.dart';

String _normalizeIdentityText(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

class _LegacyPioneerUpgradeWork {
  const _LegacyPioneerUpgradeWork({
    required this.displayTitle,
    required this.titleAliases,
    required this.fileStemAliases,
    required this.authorAliases,
  });

  final String displayTitle;
  final Set<String> titleAliases;
  final Set<String> fileStemAliases;
  final Set<String> authorAliases;
}

const List<_LegacyPioneerUpgradeWork>
_legacyPioneerUpgradeWorks = <_LegacyPioneerUpgradeWork>[
  _LegacyPioneerUpgradeWork(
    displayTitle: 'The Cross and Its Shadow',
    titleAliases: <String>{'the cross and its shadow', 'cross and its shadow'},
    fileStemAliases: <String>{'the cross and its shadow'},
    authorAliases: <String>{
      'stephen nelson haskell',
      'stephen n haskell',
      's n haskell',
    },
  ),
  _LegacyPioneerUpgradeWork(
    displayTitle: 'The Story of the Seer of Patmos',
    titleAliases: <String>{
      'the story of the seer of patmos',
      'story of the seer of patmos',
      'the seer of patmos',
      'seer of patmos',
    },
    fileStemAliases: <String>{'the story of the seer of patmos'},
    authorAliases: <String>{
      'stephen nelson haskell',
      'stephen n haskell',
      's n haskell',
    },
  ),
  _LegacyPioneerUpgradeWork(
    displayTitle: 'The Consecrated Way to Christian Perfection',
    titleAliases: <String>{
      'the consecrated way to christian perfection',
      'consecrated way to christian perfection',
      'the consecrated way',
      'consecrated way',
    },
    fileStemAliases: <String>{'the consecrated way to christian perfection'},
    authorAliases: <String>{
      'alonzo trevier jones',
      'alonzo t jones',
      'a t jones',
    },
  ),
  _LegacyPioneerUpgradeWork(
    displayTitle: 'Sanctification',
    titleAliases: <String>{'sanctification'},
    fileStemAliases: <String>{'aplib d t bordeau sanctification epub d826c638'},
    authorAliases: <String>{'daniel t bordeau', 'd t bordeau'},
  ),
];

/// One `.epub` file discovered in a user-selected raw Pioneer EPUB folder,
/// described purely from deterministic local metadata — no network access,
/// no Ollama, no content fabrication. Never read for anything but this
/// inventory pass; the source file itself is opened read-only.
class PioneerEpubInventoryEntry {
  const PioneerEpubInventoryEntry({
    required this.sourceRelativePath,
    required this.absolutePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.sha256,
    required this.isStructurallyValid,
    this.rejectionReason,
    this.title,
    this.author,
    this.language,
    this.identifier,
    required this.hasCover,
    required this.hasNavigation,
    required this.spineItemCount,
    required this.readableContentCount,
    required this.libraryItemId,
    required this.reusesLegacyLibraryItemIdentity,
    required this.duplicateGroupKey,
    required this.alreadyImported,
    required this.isUnchanged,
  });

  /// Path relative to the selected Pioneer source folder — never an
  /// absolute, device-specific path outside that folder.
  final String sourceRelativePath;
  final String absolutePath;
  final String fileName;
  final int fileSizeBytes;
  final String sha256;

  final bool isStructurallyValid;
  final String? rejectionReason;

  final String? title;
  final String? author;
  final String? language;
  final String? identifier;
  final bool hasCover;
  final bool hasNavigation;
  final int spineItemCount;
  final int readableContentCount;

  /// The deterministic `library_items.id` this file would receive if
  /// imported, computed the same way whether or not it has been imported
  /// yet — so inventory and import always agree on identity.
  final String libraryItemId;

  /// True when this EPUB is an upgraded source for a library item that was
  /// already installed under an older capture/package identity. Import must
  /// update that row in place so every user-owned reference remains attached.
  final bool reusesLegacyLibraryItemIdentity;

  /// Loose grouping key (normalized title+author, or filename stem when
  /// neither is known) used only to surface "probable duplicate or
  /// alternate-edition candidates" in the inventory report. Never used to
  /// silently merge distinct library items.
  final String duplicateGroupKey;

  /// True when a `library_items` row for [libraryItemId] already exists.
  final bool alreadyImported;

  /// True when already imported AND the current source fingerprint matches
  /// what was imported last time — safe to skip without rebuilding.
  final bool isUnchanged;

  bool get missingCover => !hasCover;
}

class PioneerEpubFolderInventory {
  const PioneerEpubFolderInventory({
    required this.folderPath,
    required this.scannedAt,
    required this.entries,
    required this.skippedNonEpubCount,
  });

  final String folderPath;
  final DateTime scannedAt;
  final List<PioneerEpubInventoryEntry> entries;

  /// Non-`.epub` files (zip/json/hidden/system files, etc.) seen while
  /// scanning and deliberately ignored.
  final int skippedNonEpubCount;

  int get totalFound => entries.length;
  int get validCount => entries.where((e) => e.isStructurallyValid).length;
  int get invalidCount => entries.where((e) => !e.isStructurallyValid).length;
  int get unchangedCount => entries.where((e) => e.isUnchanged).length;
  int get missingCoverCount =>
      entries.where((e) => e.isStructurallyValid && e.missingCover).length;

  /// Valid entries that are either not yet imported, or imported from a
  /// source that has since changed.
  List<PioneerEpubInventoryEntry> get needsImport => entries
      .where((e) => e.isStructurallyValid && !e.isUnchanged)
      .toList(growable: false);

  int get needsImportCount => needsImport.length;

  List<PioneerEpubInventoryEntry> get invalid =>
      entries.where((e) => !e.isStructurallyValid).toList(growable: false);

  /// Groups of two or more entries that share a duplicate-group key —
  /// reported for the user's awareness, never auto-merged.
  Map<String, List<PioneerEpubInventoryEntry>> get probableDuplicateGroups {
    final groups = <String, List<PioneerEpubInventoryEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(entry.duplicateGroupKey, () => []).add(entry);
    }
    groups.removeWhere((_, list) => list.length < 2);
    return groups;
  }

  int get estimatedNewSourceBytes =>
      needsImport.fold(0, (sum, e) => sum + e.fileSizeBytes);
}

/// Surveys a user-selected raw Pioneer EPUB folder without importing
/// anything. Read-only: every source file is only opened for reading, never
/// renamed, moved, modified, or deleted, and nothing is written to the
/// canonical database during this pass.
class PioneerEpubFolderInventoryService {
  PioneerEpubFolderInventoryService._();

  static final PioneerEpubFolderInventoryService instance =
      PioneerEpubFolderInventoryService._();

  Future<PioneerEpubFolderInventory> survey(
    Directory folder, {
    void Function(int current, int total, String fileName)? onProgress,
  }) async {
    final scannedAt = DateTime.now().toUtc();
    final entries = <PioneerEpubInventoryEntry>[];
    var skippedNonEpub = 0;

    final files = <File>[];
    await for (final entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final baseName = p.basename(entity.path);
      if (baseName.startsWith('.')) {
        skippedNonEpub += 1;
        continue;
      }
      if (p.extension(entity.path).toLowerCase() != '.epub') {
        skippedNonEpub += 1;
        continue;
      }
      files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    final db = await ELibraryDatabase.instance.database;
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      onProgress?.call(index + 1, files.length, p.basename(file.path));
      entries.add(await _inspect(file: file, folderPath: folder.path, db: db));
    }

    return PioneerEpubFolderInventory(
      folderPath: folder.path,
      scannedAt: scannedAt,
      entries: entries,
      skippedNonEpubCount: skippedNonEpub,
    );
  }

  Future<PioneerEpubInventoryEntry> _inspect({
    required File file,
    required String folderPath,
    required Database db,
  }) async {
    final sourceRelativePath = p
        .relative(file.path, from: folderPath)
        .replaceAll('\\', '/');
    final bytes = await file.readAsBytes();
    final fingerprint = sha256.convert(bytes).toString();
    final fileSize = bytes.length;

    final structural = EpubDownloadValidator.validate(bytes);
    final meta = structural.isValid
        ? _extractDisplayMetadata(bytes)
        : const _PioneerEpubDisplayMetadata();

    final identityKey = _stableIdentityKey(
      identifier: meta.identifier,
      sourceRelativePath: sourceRelativePath,
    );
    final pioneerLibraryItemId = canonicalLibraryItemId(
      folderType: 'pioneer_epub_import',
      relativePath: identityKey,
    );
    final legacyLibraryItemId = await _legacyLibraryItemIdFor(
      db: db,
      title: meta.title,
      author: meta.author,
      sourceRelativePath: sourceRelativePath,
    );
    final libraryItemId = legacyLibraryItemId ?? pioneerLibraryItemId;

    final existing = await db.query(
      'library_items',
      columns: const <String>['pioneer_source_fingerprint', 'index_status'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    final alreadyImported = existing.isNotEmpty;
    final priorFingerprint = alreadyImported
        ? existing.first['pioneer_source_fingerprint']?.toString().trim()
        : null;
    // "Unchanged" requires more than a matching fingerprint: a prior attempt
    // that copied the file but then failed canonicalization must stay
    // eligible for retry, not be silently treated as already-ready.
    final canonicalGenerationReady =
        alreadyImported &&
        await LibraryDocumentRepository(db).isCurrentComplete(
          libraryItemId,
          canonicalizerVersion: LibraryDocumentCanonicalizer.version,
        );
    final isUnchanged =
        alreadyImported &&
        structural.isValid &&
        priorFingerprint != null &&
        priorFingerprint == fingerprint &&
        canonicalGenerationReady;

    final duplicateGroupKey = _duplicateGroupKey(
      title: meta.title,
      author: meta.author,
      fileName: p.basename(file.path),
    );

    return PioneerEpubInventoryEntry(
      sourceRelativePath: sourceRelativePath,
      absolutePath: file.path,
      fileName: p.basename(file.path),
      fileSizeBytes: fileSize,
      sha256: fingerprint,
      isStructurallyValid: structural.isValid,
      rejectionReason: structural.isValid
          ? null
          : _rejectionSummary(structural),
      title: meta.title,
      author: meta.author,
      language: meta.language,
      identifier: meta.identifier,
      hasCover: meta.hasCover,
      hasNavigation: meta.hasNavigation,
      spineItemCount: structural.spineItemCount,
      readableContentCount: structural.readableContentCount,
      libraryItemId: libraryItemId,
      reusesLegacyLibraryItemIdentity: legacyLibraryItemId != null,
      duplicateGroupKey: duplicateGroupKey,
      alreadyImported: alreadyImported,
      isUnchanged: isUnchanged,
    );
  }

  Future<String?> _legacyLibraryItemIdFor({
    required Database db,
    required String? title,
    required String? author,
    required String sourceRelativePath,
  }) async {
    final work = _legacyUpgradeWorkFor(
      title: title,
      author: author,
      sourceRelativePath: sourceRelativePath,
    );
    if (work == null) return null;

    // Deliberately exclude rows produced by this importer. This lookup is
    // solely a bridge from a pre-existing capture/package identity to the new
    // EPUB source identity.
    final rows = await db.query(
      'library_items',
      columns: const <String>['id', 'title', 'author', 'source_type'],
      where: 'deleted_at IS NULL',
    );
    final matches = rows
        .where((row) {
          if (row['source_type']?.toString() == 'pioneer_epub_import')
            return false;
          final candidateTitle = _normalizeIdentityText(
            row['title']?.toString() ?? '',
          );
          if (!work.titleAliases.contains(candidateTitle)) return false;
          final candidateAuthor = _normalizeIdentityText(
            row['author']?.toString() ?? '',
          );
          return candidateAuthor.isEmpty ||
              work.authorAliases.isEmpty ||
              work.authorAliases.contains(candidateAuthor);
        })
        .toList(growable: false);

    if (matches.length > 1) {
      throw StateError(
        'More than one existing library item matches "${work.displayTitle}". '
        'Import stopped rather than creating or upgrading an ambiguous item.',
      );
    }
    return matches.isEmpty ? null : matches.single['id']!.toString();
  }

  _LegacyPioneerUpgradeWork? _legacyUpgradeWorkFor({
    required String? title,
    required String? author,
    required String sourceRelativePath,
  }) {
    final normalizedTitle = _normalizeIdentityText(title ?? '');
    final normalizedAuthor = _normalizeIdentityText(author ?? '');
    final normalizedStem = _normalizeIdentityText(
      p.basenameWithoutExtension(sourceRelativePath),
    );
    for (final work in _legacyPioneerUpgradeWorks) {
      final titleMatches =
          work.titleAliases.contains(normalizedTitle) ||
          work.fileStemAliases.contains(normalizedStem);
      if (!titleMatches) continue;
      if (normalizedAuthor.isEmpty ||
          work.authorAliases.isEmpty ||
          work.authorAliases.contains(normalizedAuthor)) {
        return work;
      }
    }
    return null;
  }

  String _rejectionSummary(EpubDownloadValidationResult structural) {
    final reasonName = structural.rejectionReason?.name ?? 'invalid';
    final detail = structural.detail?.trim();
    return detail == null || detail.isEmpty
        ? reasonName
        : '$reasonName: $detail';
  }

  /// Row identity is deliberately per-file, never per normalized
  /// title/author: two genuinely different files that happen to share a
  /// near-identical title (a typo fix, a re-scan, an alternate edition)
  /// must never collapse onto the same `library_items.id` — that would
  /// silently discard one file's canonical content the next time the other
  /// is (re)imported. A reliable, non-placeholder EPUB identifier survives
  /// the file being renamed/moved within the source folder; otherwise the
  /// file's path relative to the selected folder is the stable key, so
  /// re-scanning an unchanged location always resolves to the same row
  /// (resumable) while two distinct files always get distinct rows.
  /// Normalized title/author is used only for [_duplicateGroupKey] below,
  /// which merely *reports* probable duplicates — it never merges them.
  String _stableIdentityKey({
    required String? identifier,
    required String sourceRelativePath,
  }) {
    final cleanIdentifier = identifier?.trim() ?? '';
    if (cleanIdentifier.isNotEmpty &&
        !_looksLikePlaceholderIdentifier(cleanIdentifier)) {
      return 'id_$cleanIdentifier';
    }
    return 'path_$sourceRelativePath';
  }

  bool _looksLikePlaceholderIdentifier(String identifier) {
    final lower = identifier.toLowerCase();
    if (lower == 'urn:uuid:00000000-0000-0000-0000-000000000000') return true;
    if (lower
        .replaceAll(RegExp(r'[^a-f0-9]'), '')
        .replaceAll('0', '')
        .isEmpty) {
      return true;
    }
    return false;
  }

  String _duplicateGroupKey({
    required String? title,
    required String? author,
    required String fileName,
  }) {
    final cleanTitle = (title ?? '').trim().toLowerCase();
    final cleanAuthor = (author ?? '').trim().toLowerCase();
    if (cleanTitle.isNotEmpty) {
      final normalizedTitle = cleanTitle
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      final normalizedAuthor = cleanAuthor
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      return '$normalizedTitle|$normalizedAuthor';
    }
    return ELibraryFolderPolicy.editionKeyForFileName(fileName);
  }

  _PioneerEpubDisplayMetadata _extractDisplayMetadata(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final containerEntry = _findEntry(archive, 'META-INF/container.xml');
      if (containerEntry == null) return const _PioneerEpubDisplayMetadata();
      final containerXml = _decodeText(containerEntry);
      final rootfilePath = RegExp(
        r'''<rootfile\b[^>]*\bfull-path\s*=\s*(["'])([^"']+)\1''',
        caseSensitive: false,
      ).firstMatch(containerXml)?.group(2)?.trim();
      if (rootfilePath == null || rootfilePath.isEmpty) {
        return const _PioneerEpubDisplayMetadata();
      }
      final opfEntry = _findEntry(archive, rootfilePath);
      if (opfEntry == null) return const _PioneerEpubDisplayMetadata();
      final opfXml = _decodeText(opfEntry);

      final title = normalizeBookDisplayTitle(
        _stripTags(
          RegExp(
                r'<dc:title[^>]*>(.*?)</dc:title>',
                caseSensitive: false,
                dotAll: true,
              ).firstMatch(opfXml)?.group(1) ??
              '',
        ).trim(),
      );
      final author = normalizeBookDisplayAuthor(
        _stripTags(
          RegExp(
                r'<dc:creator[^>]*>(.*?)</dc:creator>',
                caseSensitive: false,
                dotAll: true,
              ).firstMatch(opfXml)?.group(1) ??
              '',
        ).trim(),
        fallbackLabel: '',
      );
      final language = _stripTags(
        RegExp(
              r'<dc:language[^>]*>(.*?)</dc:language>',
              caseSensitive: false,
              dotAll: true,
            ).firstMatch(opfXml)?.group(1) ??
            '',
      ).trim();
      final identifier = _stripTags(
        RegExp(
              r'<dc:identifier[^>]*>(.*?)</dc:identifier>',
              caseSensitive: false,
              dotAll: true,
            ).firstMatch(opfXml)?.group(1) ??
            '',
      ).trim();

      final manifestBody =
          RegExp(
            r'<manifest\b[^>]*>(.*?)</manifest>',
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(opfXml)?.group(1) ??
          '';
      final hasCover =
          RegExp(
            r'''properties\s*=\s*["'][^"']*\bcover-image\b''',
            caseSensitive: false,
          ).hasMatch(manifestBody) ||
          RegExp(
            r'''<meta\b[^>]*name\s*=\s*["']cover["']''',
            caseSensitive: false,
          ).hasMatch(opfXml);
      final hasNavigation =
          RegExp(
            r'''properties\s*=\s*["'][^"']*\bnav\b''',
            caseSensitive: false,
          ).hasMatch(manifestBody) ||
          RegExp(
            r'''media-type\s*=\s*["']application/x-dtbncx\+xml["']''',
            caseSensitive: false,
          ).hasMatch(manifestBody);

      return _PioneerEpubDisplayMetadata(
        title: title.isEmpty ? null : title,
        author: author.isEmpty ? null : author,
        language: language.isEmpty ? null : language,
        identifier: identifier.isEmpty ? null : identifier,
        hasCover: hasCover,
        hasNavigation: hasNavigation,
      );
    } catch (_) {
      return const _PioneerEpubDisplayMetadata();
    }
  }

  ArchiveFile? _findEntry(Archive archive, String path) {
    final normalized = _normalizePath(path);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (_normalizePath(file.name) == normalized) return file;
    }
    return null;
  }

  String _normalizePath(String path) =>
      path.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');

  String _decodeText(ArchiveFile entry) =>
      utf8.decode(entry.content as List<int>, allowMalformed: true);

  String _stripTags(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _PioneerEpubDisplayMetadata {
  const _PioneerEpubDisplayMetadata({
    this.title,
    this.author,
    this.language,
    this.identifier,
    this.hasCover = false,
    this.hasNavigation = false,
  });

  final String? title;
  final String? author;
  final String? language;
  final String? identifier;
  final bool hasCover;
  final bool hasNavigation;
}
