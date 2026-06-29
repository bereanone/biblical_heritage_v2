import '../../../core/database/elibrary_database.dart';
import 'pioneer_source_catalog.dart';

enum PioneerInstalledQualityState {
  verified,
  needsReview,
  partial,
  badImport,
  empty,
  frontMatterOnly,
  navigationBroken,
  notInstalled;

  String get label => switch (this) {
    PioneerInstalledQualityState.verified => 'Installed — verified',
    PioneerInstalledQualityState.needsReview => 'Legacy import needs review',
    PioneerInstalledQualityState.partial => 'Partially imported',
    PioneerInstalledQualityState.badImport => 'Legacy import needs review',
    PioneerInstalledQualityState.empty => 'Legacy import needs review',
    PioneerInstalledQualityState.frontMatterOnly =>
      'Legacy import needs review',
    PioneerInstalledQualityState.navigationBroken =>
      'Legacy import needs review',
    PioneerInstalledQualityState.notInstalled => 'Available',
  };

  int get qualityRank => switch (this) {
    PioneerInstalledQualityState.verified => 4,
    PioneerInstalledQualityState.needsReview => 3,
    PioneerInstalledQualityState.partial => 2,
    PioneerInstalledQualityState.badImport => 0,
    PioneerInstalledQualityState.empty => 0,
    PioneerInstalledQualityState.frontMatterOnly => 0,
    PioneerInstalledQualityState.navigationBroken => 0,
    PioneerInstalledQualityState.notInstalled => 0,
  };
}

class PioneerWorkInstallStatus {
  const PioneerWorkInstallStatus({
    required this.workId,
    required this.hasLibraryRow,
    required this.qualityState,
    required this.installedSourceSummary,
    required this.installedSourceType,
    required this.installedSourceSite,
    required this.installedSourceUrl,
    required this.textBlockCount,
    required this.navigationRowCount,
    required this.navigationRowsWithTextCount,
    required this.refRowCount,
  });

  final String workId;
  final bool hasLibraryRow;
  final PioneerInstalledQualityState qualityState;
  final String? installedSourceSummary;
  final String? installedSourceType;
  final String? installedSourceSite;
  final String? installedSourceUrl;
  final int textBlockCount;
  final int navigationRowCount;
  final int navigationRowsWithTextCount;
  final int refRowCount;

  bool get isInstalled => hasLibraryRow;

  bool get isVerifiedInstalled =>
      hasLibraryRow && qualityState == PioneerInstalledQualityState.verified;

  String get statusLabel {
    if (hasLibraryRow &&
        qualityState == PioneerInstalledQualityState.verified &&
        _isTextCaptureSource(installedSourceType, installedSourceSite)) {
      return 'Installed — text';
    }
    return qualityState.label;
  }

  String? replacementWarningFor(PioneerSourceWork work) {
    if (!isVerifiedInstalled) {
      return null;
    }
    final candidate = work.preferredImportCandidate;
    if (candidate == null) {
      return null;
    }
    if (candidate.qualityRank >= qualityState.qualityRank) {
      return null;
    }
    if (qualityState.qualityRank >= 4) {
      return 'An existing higher-quality import is already installed. This source will not replace it unless you explicitly choose Repair/Reimport.';
    }
    return 'An existing installed copy is already present. This source will not replace it unless you explicitly choose Repair/Reimport.';
  }
}

class PioneerInstallStatusService {
  PioneerInstallStatusService({ELibraryDatabase? database})
    : _database = database ?? ELibraryDatabase.instance;

  static final PioneerInstallStatusService instance =
      PioneerInstallStatusService();

  final ELibraryDatabase _database;

  Future<Map<String, PioneerWorkInstallStatus>> inspectCatalog(
    PioneerSourceCatalog catalog,
  ) async {
    final workIds = <String>{};
    for (final work in catalog.works) {
      workIds.add(work.stableLibraryItemId);
      workIds.add(work.copiedRangeLibraryItemId);
      workIds.add(work.libraryItemIdForSourceKey('text_capture'));
    }
    if (workIds.isEmpty) {
      return const <String, PioneerWorkInstallStatus>{};
    }

    final db = await _database.database;
    final orderedWorkIds = workIds.toList(growable: false);
    final placeholders = List<String>.filled(
      orderedWorkIds.length,
      '?',
    ).join(', ');
    final rows = await db.rawQuery('''
      SELECT
        id,
        title,
        author,
        collection_name,
        source_type,
        source_site,
        source_url,
        file_format,
        mime_type,
        index_status,
        (
          SELECT COUNT(*)
          FROM library_text_blocks
          WHERE library_item_id = library_items.id
        ) AS text_block_count,
        (
          SELECT COUNT(*)
          FROM library_navigation_items
          WHERE library_item_id = library_items.id
            AND deleted_at IS NULL
        ) AS navigation_row_count,
        (
          SELECT COUNT(*)
          FROM library_navigation_items nav
          WHERE nav.library_item_id = library_items.id
            AND nav.deleted_at IS NULL
            AND EXISTS (
              SELECT 1
              FROM library_text_blocks text_block
              WHERE text_block.library_item_id = library_items.id
                AND text_block.epub_href = nav.href
            )
        ) AS navigation_rows_with_text_count,
        (
          SELECT COUNT(*)
          FROM elibrary_ref_index
          WHERE library_item_id = library_items.id
        ) AS ref_row_count,
        (
          SELECT COUNT(*)
          FROM library_navigation_items
          WHERE library_item_id = library_items.id
            AND deleted_at IS NULL
            AND is_body_start = 1
        ) AS body_start_count,
        (
          SELECT COUNT(*)
          FROM library_navigation_items nav
          WHERE nav.library_item_id = library_items.id
            AND nav.deleted_at IS NULL
            AND lower(coalesce(nav.nav_type, '')) = 'toc'
            AND lower(coalesce(nav.content_kind, '')) IN ('chapter', 'section')
            AND coalesce(nav.body_order, 1) > 1
        ) AS toc_target_mismatch_count,
        (
          SELECT COUNT(*)
          FROM library_text_blocks
          WHERE library_item_id = library_items.id
            AND (
              lower(plain_text) LIKE '%adventist pioneer library%' OR
              lower(plain_text) LIKE '%www.aplib.org%' OR
              lower(plain_text) LIKE '%isbn:%' OR
              lower(plain_text) LIKE '%published in the usa%' OR
              lower(plain_text) LIKE '%originally published in%' OR
              lower(plain_text) LIKE '%support the ministry%' OR
              lower(plain_text) LIKE '%donate%' OR
              lower(plain_text) LIKE '%donation%'
            )
        ) AS wrapper_text_count,
        (
          SELECT COUNT(*)
          FROM library_text_blocks
          WHERE library_item_id = library_items.id
            AND lower(plain_text) GLOB '*[0-9] margin*'
        ) AS margin_artifact_count,
        (
          SELECT COUNT(*)
          FROM library_items AS candidate
          WHERE candidate.deleted_at IS NULL
            AND (
              lower(candidate.collection_name) LIKE '%pioneer%' OR
              lower(candidate.source_site) IN (
                'adventaudio.org',
                'ellenwhiteaudio.org'
              ) OR
              lower(candidate.source_url) LIKE '%adventaudio.org%' OR
              lower(candidate.source_url) LIKE '%ellenwhiteaudio.org%'
            )
            AND lower(trim(candidate.title)) = lower(trim(library_items.title))
            AND lower(trim(coalesce(candidate.author, ''))) = lower(
              trim(coalesce(library_items.author, ''))
            )
            AND coalesce(candidate.source_url, '') = coalesce(
              library_items.source_url,
              ''
            )
        ) AS duplicate_item_count,
        (
          SELECT GROUP_CONCAT(plain_text, ' || ')
          FROM (
            SELECT plain_text
            FROM library_text_blocks
            WHERE library_item_id = library_items.id
            ORDER BY spine_index, paragraph_index
            LIMIT 3
          )
        ) AS first_snippets
      FROM library_items
      WHERE deleted_at IS NULL AND id IN ($placeholders)
      ''', orderedWorkIds);

    final rowById = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      rowById[id] = row;
    }

    final statuses = <String, PioneerWorkInstallStatus>{};
    for (final work in catalog.works) {
      final row =
          rowById[work.copiedRangeLibraryItemId] ??
          rowById[work.libraryItemIdForSourceKey('text_capture')] ??
          rowById[work.stableLibraryItemId];
      statuses[work.id] = row == null
          ? PioneerWorkInstallStatus(
              workId: work.id,
              hasLibraryRow: false,
              qualityState: PioneerInstalledQualityState.notInstalled,
              installedSourceSummary: null,
              installedSourceType: null,
              installedSourceSite: null,
              installedSourceUrl: null,
              textBlockCount: 0,
              navigationRowCount: 0,
              navigationRowsWithTextCount: 0,
              refRowCount: 0,
            )
          : PioneerWorkInstallStatus(
              workId: work.id,
              hasLibraryRow: true,
              qualityState: _installedQualityState(row: row),
              installedSourceSummary: _installedSourceSummary(row),
              installedSourceType: row['source_type']?.toString(),
              installedSourceSite: row['source_site']?.toString(),
              installedSourceUrl: row['source_url']?.toString(),
              textBlockCount: _countValue(row, 'text_block_count'),
              navigationRowCount: _countValue(row, 'navigation_row_count'),
              navigationRowsWithTextCount: _countValue(
                row,
                'navigation_rows_with_text_count',
              ),
              refRowCount: _countValue(row, 'ref_row_count'),
            );
    }

    return statuses;
  }
}

String _installedSourceSummary(Map<String, Object?> row) {
  final parts = <String>[];
  final sourceSite = row['source_site']?.toString().trim();
  final sourceType = row['source_type']?.toString().trim();
  final fileFormat = row['file_format']?.toString().trim();
  if (sourceSite != null && sourceSite.isNotEmpty) {
    parts.add(sourceSite);
  }
  if (sourceType != null && sourceType.isNotEmpty) {
    parts.add(sourceType);
  }
  if (fileFormat != null && fileFormat.isNotEmpty) {
    parts.add(fileFormat.toUpperCase());
  }
  if (parts.isEmpty) {
    return 'Installed copy';
  }
  return parts.join(' • ');
}

PioneerInstalledQualityState _installedQualityState({
  required Map<String, Object?> row,
}) {
  final textBlockCount = _countValue(row, 'text_block_count');
  final indexStatus =
      row['index_status']?.toString().trim().toLowerCase() ?? '';
  if (indexStatus.contains('partial')) {
    return PioneerInstalledQualityState.partial;
  }
  if (textBlockCount == 0) {
    return PioneerInstalledQualityState.empty;
  }

  final navCount = _countValue(row, 'navigation_row_count');
  final navRowsWithTextCount = _countValue(
    row,
    'navigation_rows_with_text_count',
  );
  if (navCount == 0 || navRowsWithTextCount == 0) {
    return PioneerInstalledQualityState.navigationBroken;
  }

  final tocTargetMismatchCount = _countValue(row, 'toc_target_mismatch_count');
  final marginArtifactCount = _countValue(row, 'margin_artifact_count');
  if (tocTargetMismatchCount > 0 || marginArtifactCount > 0) {
    return PioneerInstalledQualityState.navigationBroken;
  }

  final duplicateCount = _countValue(row, 'duplicate_item_count');
  if (duplicateCount > 1) {
    return PioneerInstalledQualityState.needsReview;
  }

  final wrapperCount = _countValue(row, 'wrapper_text_count');
  final bodyStartCount = _countValue(row, 'body_start_count');
  final firstSnippets = row['first_snippets']?.toString() ?? '';
  if (wrapperCount > 0 &&
      bodyStartCount <= 0 &&
      _looksLikeFrontMatter(firstSnippets)) {
    return PioneerInstalledQualityState.frontMatterOnly;
  }

  return PioneerInstalledQualityState.verified;
}

bool _looksLikeFrontMatter(String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return true;
  }
  final lowered = normalized.toLowerCase();
  if (lowered.contains('adventist pioneer library')) return true;
  if (lowered.contains('www.aplib.org')) return true;
  if (lowered.contains('isbn:')) return true;
  if (lowered.contains('published in the usa')) return true;
  if (lowered.contains('originally published in')) return true;
  if (lowered.contains('the original table of contents contained')) {
    return true;
  }
  if (lowered.contains('support the ministry') ||
      lowered.contains('donate') ||
      lowered.contains('donation')) {
    return true;
  }
  return false;
}

bool _isTextCaptureSource(String? sourceType, String? sourceSite) {
  final normalizedType = sourceType?.trim().toLowerCase() ?? '';
  final normalizedSite = sourceSite?.trim().toLowerCase() ?? '';
  return normalizedType.contains('copied_range') ||
      normalizedType.contains('text_capture') ||
      normalizedType.contains('captured') ||
      normalizedType.contains('browser') ||
      normalizedType.contains('egw_copied') ||
      normalizedSite.contains('egw writings copied') ||
      normalizedSite.contains('browser capture');
}

int _countValue(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
