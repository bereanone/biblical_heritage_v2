import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const String kPioneerSourceCatalogAssetPath =
    'assets/elibrary_sources/pioneer_sources.json';

enum PioneerSourceAvailability {
  available,
  sourceNeeded,
  imported,
  unavailable,
  unknown;

  static PioneerSourceAvailability fromStoredValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'verified':
      case 'verified_source':
      case 'available':
      case 'available_source':
        return PioneerSourceAvailability.available;
      case 'imported':
        return PioneerSourceAvailability.imported;
      case 'unavailable':
      case 'blocked':
        return PioneerSourceAvailability.unavailable;
      case 'source_needed':
      case 'needed':
      case 'unknown':
      default:
        return PioneerSourceAvailability.sourceNeeded;
    }
  }

  String get friendlyLabel => switch (this) {
    PioneerSourceAvailability.available => 'Available',
    PioneerSourceAvailability.sourceNeeded => 'Capture needed',
    PioneerSourceAvailability.imported => 'Imported',
    PioneerSourceAvailability.unavailable => 'Unavailable',
    PioneerSourceAvailability.unknown => 'Status unknown',
  };

  bool get isImportable => this == PioneerSourceAvailability.available;
}

enum PioneerSourceImportMethodPreference {
  textReadCapture,
  validatedEpub,
  userSuppliedCleanedSource,
  sourceNeeded;

  String get label => switch (this) {
    PioneerSourceImportMethodPreference.textReadCapture => 'Text/read capture',
    PioneerSourceImportMethodPreference.validatedEpub => 'Capture needed',
    PioneerSourceImportMethodPreference.userSuppliedCleanedSource =>
      'Text/browser capture',
    PioneerSourceImportMethodPreference.sourceNeeded => 'Source needed',
  };
}

enum PioneerEpubValidationStatus {
  validated,
  needsReview,
  unavailable;

  String get label => switch (this) {
    PioneerEpubValidationStatus.validated => 'Capture needed',
    PioneerEpubValidationStatus.needsReview => 'Capture needed',
    PioneerEpubValidationStatus.unavailable => 'Source needed',
  };
}

enum PioneerTextCaptureStatus {
  textSource,
  captureNeeded,
  sourceNeeded;

  String get label => switch (this) {
    PioneerTextCaptureStatus.textSource => 'Text capture available',
    PioneerTextCaptureStatus.captureNeeded => 'Capture needed',
    PioneerTextCaptureStatus.sourceNeeded => 'Source needed',
  };
}

@immutable
class PioneerSourceCandidate {
  const PioneerSourceCandidate({
    required this.provider,
    required this.sourceType,
    required this.priority,
    required this.qualityTier,
    required this.availability,
    this.url,
    this.zipEntry,
    this.editionLabel,
    this.editionYear,
    this.requiresVerification = false,
    this.destructiveReplacementAllowed = false,
    this.isRepairSource = false,
    this.userMustConfirmReplacement = true,
    this.notes,
  });

  final String provider;
  final String sourceType;
  final String? url;
  final String? zipEntry;
  final String? editionLabel;
  final int? editionYear;
  final int priority;
  final String qualityTier;
  final PioneerSourceAvailability availability;
  final bool requiresVerification;
  final bool destructiveReplacementAllowed;
  final bool isRepairSource;
  final bool userMustConfirmReplacement;
  final String? notes;

  bool get hasUrl => url?.trim().isNotEmpty == true;

  bool get isDirectFileSource => _isDirectFileUrl(url);

  bool get canOpenInWebView => () {
    final normalized = sourceType.trim().toLowerCase();
    return normalized == 'readerpage' ||
        normalized == 'capturedhtml' ||
        normalized == 'capturedhtmlpage' ||
        normalized == 'captured_html' ||
        normalized == 'pioneer_captured_html';
  }();

  bool get isTextCaptureCandidate {
    final normalized = sourceType.trim().toLowerCase();
    return normalized == 'readerpage' ||
        normalized == 'capturedhtml' ||
        normalized == 'capturedhtmlpage' ||
        normalized == 'captured_html' ||
        normalized == 'pioneer_captured_html' ||
        normalized == 'clipboard' ||
        normalized == 'savedfile' ||
        normalized == 'html';
  }

  bool get isLegacyFileCandidate {
    final normalized = sourceType.trim().toLowerCase();
    return normalized == 'epub' ||
        normalized == 'directepub' ||
        normalized == 'epubzipentry' ||
        normalized == 'pdf' ||
        normalized == 'mobi' ||
        isDirectFileSource;
  }

  bool get supportsAutoImport =>
      availability.isImportable &&
      hasUrl &&
      () {
        final normalized = sourceType.trim().toLowerCase();
        return normalized == 'capturedhtml' ||
            normalized == 'capturedhtmlpage' ||
            normalized == 'captured_html' ||
            normalized == 'pioneer_captured_html' ||
            normalized == 'clipboard' ||
            normalized == 'savedfile' ||
            normalized == 'html';
      }();

  PioneerSourceCandidate copyWith({
    String? provider,
    String? sourceType,
    String? url,
    String? zipEntry,
    String? editionLabel,
    int? editionYear,
    int? priority,
    String? qualityTier,
    PioneerSourceAvailability? availability,
    bool? requiresVerification,
    bool? destructiveReplacementAllowed,
    bool? isRepairSource,
    bool? userMustConfirmReplacement,
    String? notes,
  }) {
    return PioneerSourceCandidate(
      provider: provider ?? this.provider,
      sourceType: sourceType ?? this.sourceType,
      priority: priority ?? this.priority,
      qualityTier: qualityTier ?? this.qualityTier,
      availability: availability ?? this.availability,
      url: url ?? this.url,
      zipEntry: zipEntry ?? this.zipEntry,
      editionLabel: editionLabel ?? this.editionLabel,
      editionYear: editionYear ?? this.editionYear,
      requiresVerification: requiresVerification ?? this.requiresVerification,
      destructiveReplacementAllowed:
          destructiveReplacementAllowed ?? this.destructiveReplacementAllowed,
      isRepairSource: isRepairSource ?? this.isRepairSource,
      userMustConfirmReplacement:
          userMustConfirmReplacement ?? this.userMustConfirmReplacement,
      notes: notes ?? this.notes,
    );
  }

  String get providerLabel {
    switch (provider.trim().toLowerCase()) {
      case 'adventaudio':
      case 'advent audio':
      case 'egwaudio':
      case 'egw audio':
      case 'ellenwhiteaudio':
      case 'aplib':
        return 'Hidden source';
      case 'egwwritings':
        return 'EGW Writings';
      case 'egwexisting':
        return 'Existing install';
      case 'archive':
        return 'Archive.org';
      case 'gutenberg':
        return 'Project Gutenberg';
      case 'local':
        return 'Local';
      case 'clipboard':
        return 'Clipboard';
      case 'savedfile':
        return 'Saved File';
    }
    return provider.trim().isEmpty ? 'Unknown' : provider.trim();
  }

  String get sourceTypeLabel {
    switch (sourceType.trim().toLowerCase()) {
      case 'epub':
      case 'directepub':
      case 'epubzipentry':
      case 'pdf':
      case 'mobi':
        return 'Hidden source';
      case 'readerpage':
        return 'Reader Capture';
      case 'capturedhtml':
      case 'capturedhtmlpage':
        return 'Captured HTML';
      case 'captured_html':
      case 'pioneer_captured_html':
        return 'Pioneer Captured HTML';
      case 'existingdb':
        return 'Installed';
      case 'clipboard':
        return 'Clipboard';
      case 'savedfile':
        return 'Saved File';
      case 'html':
        return 'HTML';
    }
    final normalized = sourceType.trim();
    if (normalized.isEmpty) return 'Unknown';
    final spaced = normalized
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return spaced.toUpperCase();
  }

  String get displayLabel {
    if (provider.trim().toLowerCase() == 'clipboard') {
      return 'Clipboard';
    }
    if (provider.trim().toLowerCase() == 'local' &&
        sourceType.trim().toLowerCase() == 'savedfile') {
      return 'Saved File';
    }
    if (provider.trim().toLowerCase() == 'egwexisting') {
      return 'Existing install';
    }
    if (provider.trim().toLowerCase() == 'egwwritings' &&
        sourceType.trim().toLowerCase() == 'readerpage') {
      return 'EGW Reader Capture';
    }
    if (provider.trim().toLowerCase() == 'egwwritings' &&
        sourceType.trim().toLowerCase() == 'capturedhtml') {
      return 'EGW Captured HTML';
    }
    if (provider.trim().toLowerCase() == 'egwwritings' &&
        sourceType.trim().toLowerCase() == 'captured_html') {
      return 'EGW Captured HTML';
    }
    if (provider.trim().toLowerCase() == 'egwwritings' &&
        sourceType.trim().toLowerCase() == 'pioneer_captured_html') {
      return 'Pioneer Captured HTML';
    }
    return '$providerLabel $sourceTypeLabel'.trim();
  }

  String? get editionDisplayLabel {
    if (editionLabel?.trim().isNotEmpty == true) {
      return editionLabel!.trim();
    }
    if (editionYear != null) {
      return editionYear.toString();
    }
    return null;
  }

  int get qualityRank {
    switch (qualityTier.trim().toLowerCase()) {
      case 'existing':
      case 'installed':
      case 'epub':
      case 'directepub':
      case 'epubzipentry':
        return 4;
      case 'pdf':
        return 2;
      case 'reader':
      case 'capturedhtml':
      case 'capturedtext':
      case 'html':
      case 'captured_html':
      case 'pioneer_captured_html':
        return 1;
      case 'clipboard':
      case 'savedfile':
        return 0;
    }
    return 1;
  }
}

@immutable
class PioneerSourceWork {
  const PioneerSourceWork({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.sourceFamily,
    required this.title,
    required this.abbreviation,
    this.editionLabel,
    this.editionYear,
    required this.group,
    required this.subgroup,
    required this.availability,
    required this.verified,
    required this.catalogImportable,
    required this.sourceType,
    required this.sourceUrl,
    this.collectionUrl,
    this.captureUrl,
    this.readerUrl,
    this.directFileUrl,
    this.directFileType,
    this.thumbnailUrl,
    this.coverUrl,
    this.cachedThumbnailPath,
    this.cachedCoverPath,
    required this.sourceLabel,
    required this.notes,
    this.sourceCandidates = const <PioneerSourceCandidate>[],
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? sourceFamily;
  final String title;
  final String abbreviation;
  final String? editionLabel;
  final int? editionYear;
  final String group;
  final String subgroup;
  final PioneerSourceAvailability availability;
  final bool verified;
  final bool catalogImportable;
  final String? sourceType;
  final String? sourceUrl;
  final String? collectionUrl;
  final String? captureUrl;
  final String? readerUrl;
  final String? directFileUrl;
  final String? directFileType;
  final String? thumbnailUrl;
  final String? coverUrl;
  final String? cachedThumbnailPath;
  final String? cachedCoverPath;
  final String? sourceLabel;
  final String? notes;
  final List<PioneerSourceCandidate> sourceCandidates;

  PioneerSourceWork copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? sourceFamily,
    String? title,
    String? abbreviation,
    String? editionLabel,
    int? editionYear,
    String? group,
    String? subgroup,
    PioneerSourceAvailability? availability,
    bool? verified,
    bool? catalogImportable,
    String? sourceType,
    String? sourceUrl,
    String? collectionUrl,
    String? captureUrl,
    String? readerUrl,
    String? directFileUrl,
    String? directFileType,
    String? thumbnailUrl,
    String? coverUrl,
    String? cachedThumbnailPath,
    String? cachedCoverPath,
    String? sourceLabel,
    String? notes,
    List<PioneerSourceCandidate>? sourceCandidates,
  }) {
    return PioneerSourceWork(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      sourceFamily: sourceFamily ?? this.sourceFamily,
      title: title ?? this.title,
      abbreviation: abbreviation ?? this.abbreviation,
      editionLabel: editionLabel ?? this.editionLabel,
      editionYear: editionYear ?? this.editionYear,
      group: group ?? this.group,
      subgroup: subgroup ?? this.subgroup,
      availability: availability ?? this.availability,
      verified: verified ?? this.verified,
      catalogImportable: catalogImportable ?? this.catalogImportable,
      sourceType: sourceType ?? this.sourceType,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      collectionUrl: collectionUrl ?? this.collectionUrl,
      captureUrl: captureUrl ?? this.captureUrl,
      readerUrl: readerUrl ?? this.readerUrl,
      directFileUrl: directFileUrl ?? this.directFileUrl,
      directFileType: directFileType ?? this.directFileType,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      cachedThumbnailPath: cachedThumbnailPath ?? this.cachedThumbnailPath,
      cachedCoverPath: cachedCoverPath ?? this.cachedCoverPath,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      notes: notes ?? this.notes,
      sourceCandidates: sourceCandidates ?? this.sourceCandidates,
    );
  }

  factory PioneerSourceWork.fromJson({
    required String authorId,
    required String authorName,
    String? sourceFamily,
    required Map<String, Object?> json,
  }) {
    final title = _requiredString(json, const ['title', 'name']);
    final parsedEdition = _parseEditionFromTitle(title);
    final explicitEditionLabel = _optionalString(json, const [
      'edition_label',
      'editionLabel',
    ]);
    final explicitEditionYear = _optionalInt(json, const [
      'edition_year',
      'editionYear',
    ]);
    final editionSeed = _stableId(
      explicitEditionLabel ??
          explicitEditionYear?.toString() ??
          parsedEdition?.label ??
          '',
    );
    final workId = _stableId(
      _optionalString(json, const ['work_id', 'id']) ??
          (editionSeed.isEmpty ? title : '$title $editionSeed'),
    );
    final availability = PioneerSourceAvailability.fromStoredValue(
      _optionalString(json, const ['availability_status', 'availability']),
    );
    final verified = _optionalBool(json, const ['verified']) ?? false;
    final sourceType = _optionalString(json, const [
      'source_type',
      'sourceType',
    ])?.trim().trim();
    final editionLabel = explicitEditionLabel ?? parsedEdition?.label;
    final editionYear = explicitEditionYear ?? parsedEdition?.year;
    final sourceUrl = _optionalString(json, const ['source_url', 'sourceUrl']);
    final captureUrl = _optionalString(json, const [
      'capture_url',
      'captureUrl',
    ]);
    final readerUrl = _optionalString(json, const ['reader_url', 'readerUrl']);
    final collectionUrl = _optionalString(json, const [
      'collection_url',
      'collectionUrl',
    ]);
    final directFileUrl = _optionalString(json, const [
      'direct_file_url',
      'directFileUrl',
    ]);
    final directFileType = _optionalString(json, const [
      'direct_file_type',
      'directFileType',
    ]);
    final thumbnailUrl = _optionalString(json, const [
      'thumbnail_url',
      'thumbnailUrl',
      'cover_thumbnail_url',
      'coverThumbnailUrl',
    ]);
    final coverUrl = _optionalString(json, const [
      'cover_url',
      'coverUrl',
      'image_url',
      'imageUrl',
    ]);
    final cachedThumbnailPath = _optionalString(json, const [
      'cached_thumbnail_path',
      'cachedThumbnailPath',
      'thumbnail_path',
      'thumbnailPath',
    ]);
    final cachedCoverPath = _optionalString(json, const [
      'cached_cover_path',
      'cachedCoverPath',
      'cover_path',
      'coverPath',
    ]);
    final sourceLabel = _optionalString(json, const [
      'source_label',
      'sourceLabel',
    ]);
    final sourceCandidates = _parseSourceCandidates(
      json,
      availability: availability,
      sourceFamily: sourceFamily,
      sourceLabel: sourceLabel,
      legacySourceType: sourceType,
      legacySourceUrl: sourceUrl,
      collectionUrl: collectionUrl,
      captureUrl: captureUrl,
      readerUrl: readerUrl,
      directFileUrl: directFileUrl,
      directFileType: directFileType,
      verified: verified,
    );
    final catalogImportable =
        _optionalBool(json, const ['importable']) ?? availability.isImportable;
    final normalizedSourceUrl = sourceUrl?.trim();
    final normalizedCaptureUrl = captureUrl?.trim();
    final normalizedReaderUrl = readerUrl?.trim();
    final normalizedCollectionUrl = collectionUrl?.trim();
    final normalizedDirectFileUrl = directFileUrl?.trim();
    final normalizedDirectFileType = directFileType?.trim();
    final normalizedThumbnailUrl = thumbnailUrl?.trim();
    final normalizedCoverUrl = coverUrl?.trim();
    final normalizedCachedThumbnailPath = cachedThumbnailPath?.trim();
    final normalizedCachedCoverPath = cachedCoverPath?.trim();
    final normalizedSourceLabel = sourceLabel?.trim();
    return PioneerSourceWork(
      id: workId,
      authorId: _stableId(authorId),
      authorName: authorName,
      sourceFamily:
          _optionalString(json, const ['source_family', 'sourceFamily']) ??
          sourceFamily,
      title: title,
      abbreviation: _optionalString(json, const ['abbreviation', 'abbr']) ?? '',
      editionLabel: editionLabel,
      editionYear: editionYear,
      group: _optionalString(json, const ['group']) ?? '',
      subgroup: _optionalString(json, const ['subgroup']) ?? '',
      availability: availability,
      verified: verified,
      catalogImportable: catalogImportable,
      sourceType: sourceType?.isNotEmpty == true
          ? _normalizeSourceType(sourceType)
          : null,
      sourceUrl: normalizedSourceUrl?.isNotEmpty == true
          ? normalizedSourceUrl
          : null,
      collectionUrl: normalizedCollectionUrl?.isNotEmpty == true
          ? normalizedCollectionUrl
          : null,
      captureUrl: normalizedCaptureUrl?.isNotEmpty == true
          ? normalizedCaptureUrl
          : null,
      readerUrl: normalizedReaderUrl?.isNotEmpty == true
          ? normalizedReaderUrl
          : null,
      directFileUrl: normalizedDirectFileUrl?.isNotEmpty == true
          ? normalizedDirectFileUrl
          : null,
      directFileType: normalizedDirectFileType?.isNotEmpty == true
          ? normalizedDirectFileType
          : null,
      thumbnailUrl: normalizedThumbnailUrl?.isNotEmpty == true
          ? normalizedThumbnailUrl
          : null,
      coverUrl: normalizedCoverUrl?.isNotEmpty == true
          ? normalizedCoverUrl
          : null,
      cachedThumbnailPath: normalizedCachedThumbnailPath?.isNotEmpty == true
          ? normalizedCachedThumbnailPath
          : null,
      cachedCoverPath: normalizedCachedCoverPath?.isNotEmpty == true
          ? normalizedCachedCoverPath
          : null,
      sourceLabel: normalizedSourceLabel?.isNotEmpty == true
          ? normalizedSourceLabel
          : null,
      notes: _optionalString(json, const ['notes']),
      sourceCandidates: List<PioneerSourceCandidate>.unmodifiable(
        sourceCandidates,
      ),
    );
  }

  String get friendlyAvailabilityLabel => availability.friendlyLabel;

  String? get normalizedEditionLabel {
    final label = editionLabel?.trim();
    if (label?.isNotEmpty == true) return label;
    final parsed = _parseEditionFromTitle(title);
    return parsed?.label;
  }

  int? get normalizedEditionYear {
    if (editionYear != null) return editionYear;
    final parsed = _parseEditionFromTitle(title);
    return parsed?.year;
  }

  String get normalizedAuthorKey => _stableId(authorName);

  String get normalizedTitleKey => _stableId(_titleIdentityBase(title));

  String get normalizedAbbreviationKey => _stableId(abbreviation);

  String get workIdentityKey =>
      '$normalizedAuthorKey|$normalizedTitleKey|$normalizedAbbreviationKey';

  String get editionIdentityKey {
    final year = normalizedEditionYear;
    if (year != null) {
      return 'year:$year';
    }
    final label = normalizedEditionLabel;
    if (label == null) return '';
    return 'label:${_stableId(label)}';
  }

  String? get editionDisplayLabel {
    final label = normalizedEditionLabel;
    if (label != null) return label;
    final year = normalizedEditionYear;
    return year?.toString();
  }

  bool canMergeWith(PioneerSourceWork other) {
    if (normalizedAuthorKey != other.normalizedAuthorKey) return false;
    if (normalizedTitleKey != other.normalizedTitleKey) return false;
    final leftEdition = editionIdentityKey;
    final rightEdition = other.editionIdentityKey;
    if (leftEdition.isNotEmpty &&
        rightEdition.isNotEmpty &&
        leftEdition != rightEdition) {
      return false;
    }
    if (leftEdition.isEmpty && rightEdition.isEmpty) {
      final directAndZipMatch =
          (_hasDirectEpubCandidate && other._hasZipEntryCandidate) ||
          (_hasZipEntryCandidate && other._hasDirectEpubCandidate);
      if (directAndZipMatch) {
        return true;
      }
      return _hasCompatibleSourceCandidateOverlap(other);
    }
    if (leftEdition.isEmpty || rightEdition.isEmpty) {
      return true;
    }
    return true;
  }

  PioneerSourceWork mergeWith(PioneerSourceWork other) {
    if (!canMergeWith(other)) {
      throw StateError('Cannot merge distinct Pioneer works.');
    }

    final mergedCandidates = _mergeSourceCandidates([
      ...sourceCandidates,
      ...other.sourceCandidates,
    ]);
    final preferredSourceCandidate = _preferredSourceCandidateFromCandidates(
      mergedCandidates,
    );
    final preferredImportCandidate = _preferredImportCandidateFromCandidates(
      mergedCandidates,
    );
    final resolvedSourceCandidate =
        preferredImportCandidate ?? preferredSourceCandidate;
    final mergedNotes = _mergeTextFields([notes, other.notes]);
    final mergedSourceLabel = _mergeTextFields([
      resolvedSourceCandidate?.providerLabel,
      sourceLabel,
      other.sourceLabel,
    ]);
    final mergedSourceType = resolvedSourceCandidate?.sourceType ?? sourceType;
    final mergedSourceUrl = _mergeFirstNonEmpty([
      resolvedSourceCandidate?.url,
      sourceUrl,
      other.sourceUrl,
    ]);
    final mergedCollectionUrl = _mergeFirstNonEmpty([
      collectionUrl,
      other.collectionUrl,
    ]);
    final mergedCaptureUrl = _mergeFirstNonEmpty([
      captureUrl,
      other.captureUrl,
    ]);
    final mergedReaderUrl = _mergeFirstNonEmpty([readerUrl, other.readerUrl]);
    final mergedDirectFileUrl = _mergeFirstNonEmpty([
      directFileUrl,
      other.directFileUrl,
    ]);
    final mergedDirectFileType = _mergeFirstNonEmpty([
      directFileType,
      other.directFileType,
    ]);
    final mergedThumbnailUrl = _mergeFirstNonEmpty([
      thumbnailUrl,
      other.thumbnailUrl,
    ]);
    final mergedCoverUrl = _mergeFirstNonEmpty([coverUrl, other.coverUrl]);
    final mergedCachedThumbnailPath = _mergeFirstNonEmpty([
      cachedThumbnailPath,
      other.cachedThumbnailPath,
    ]);
    final mergedCachedCoverPath = _mergeFirstNonEmpty([
      cachedCoverPath,
      other.cachedCoverPath,
    ]);
    final mergedEditionLabel =
        normalizedEditionLabel ?? other.normalizedEditionLabel;
    final mergedEditionYear =
        normalizedEditionYear ?? other.normalizedEditionYear;
    final mergedAvailability = _mergeAvailability(
      availability,
      other.availability,
      mergedCandidates,
    );
    final mergedVerified = verified || other.verified;
    final mergedCatalogImportable =
        catalogImportable || other.catalogImportable;
    final mergedGroup = group.trim().isNotEmpty ? group : other.group;
    final mergedSubgroup = subgroup.trim().isNotEmpty
        ? subgroup
        : other.subgroup;
    final mergedSourceFamily = sourceFamily?.trim().isNotEmpty == true
        ? sourceFamily
        : other.sourceFamily;

    return PioneerSourceWork(
      id: id,
      authorId: authorId,
      authorName: authorName,
      sourceFamily: mergedSourceFamily,
      title: title,
      abbreviation: abbreviation.trim().isNotEmpty
          ? abbreviation
          : other.abbreviation,
      editionLabel: mergedEditionLabel,
      editionYear: mergedEditionYear,
      group: mergedGroup,
      subgroup: mergedSubgroup,
      availability: mergedAvailability,
      verified: mergedVerified,
      catalogImportable: mergedCatalogImportable,
      sourceType: mergedSourceType,
      sourceUrl: mergedSourceUrl,
      collectionUrl: mergedCollectionUrl,
      captureUrl: mergedCaptureUrl,
      readerUrl: mergedReaderUrl,
      directFileUrl: mergedDirectFileUrl,
      directFileType: mergedDirectFileType,
      thumbnailUrl: mergedThumbnailUrl,
      coverUrl: mergedCoverUrl,
      cachedThumbnailPath: mergedCachedThumbnailPath,
      cachedCoverPath: mergedCachedCoverPath,
      sourceLabel: mergedSourceLabel,
      notes: mergedNotes,
      sourceCandidates: List<PioneerSourceCandidate>.unmodifiable(
        mergedCandidates,
      ),
    );
  }

  String get friendlySourceStatusLabel {
    return compactImportStatusLabel;
  }

  String get sourceSiteLabel {
    final preferred = preferredSourceCandidate;
    if (preferred != null) {
      return preferred.providerLabel;
    }
    final explicit = sourceLabel?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    if (sourceFamily?.trim().isNotEmpty == true) {
      return sourceFamily!.trim();
    }
    final host = _friendlySourceHost(sourceUrl);
    return host ?? 'Unknown source';
  }

  bool get hasVerifiedSource =>
      verified &&
      (sourceUrl?.trim().isNotEmpty == true ||
          effectiveSourceCandidates.any((candidate) => candidate.hasUrl));

  bool get hasSupportedImportSource =>
      textReadAvailable || textCaptureAvailable;

  String? get coverImagePath {
    final localThumbnail = cachedThumbnailPath?.trim();
    if (localThumbnail?.isNotEmpty == true) return localThumbnail;
    final localCover = cachedCoverPath?.trim();
    if (localCover?.isNotEmpty == true) return localCover;
    return null;
  }

  String get fallbackCoverLabel {
    final abbr = abbreviation.trim();
    if (abbr.isNotEmpty) return abbr.toUpperCase();
    final words = title
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .take(3)
        .map((word) => word.trim()[0].toUpperCase())
        .join();
    return words.isEmpty ? 'P' : words;
  }

  bool get epubAvailable => effectiveSourceCandidates.any(
    (candidate) =>
        candidate.availability.isImportable &&
        _isEpubSourceCandidate(candidate.sourceType),
  );

  bool get textCaptureAvailable =>
      preferredCaptureCandidate != null || launchUrl != null;

  bool get hasTextCaptureFallback => textCaptureAvailable;

  bool get hasDeferredPdfSource => effectiveSourceCandidates.any(
    (candidate) => candidate.sourceType.trim().toLowerCase() == 'pdf',
  );

  bool get textReadAvailable {
    final normalizedSourceType = _normalizeSourceType(sourceType);
    if (normalizedSourceType == 'capturedhtml' ||
        normalizedSourceType == 'capturedhtmlpage' ||
        normalizedSourceType == 'webviewcapturedhtml' ||
        normalizedSourceType == 'captured_html' ||
        normalizedSourceType == 'pioneer_captured_html' ||
        normalizedSourceType == 'clipboard' ||
        normalizedSourceType == 'savedfile') {
      return true;
    }
    return effectiveSourceCandidates.any((candidate) {
      final candidateType = candidate.sourceType.trim().toLowerCase();
      return candidateType == 'capturedhtml' ||
          candidateType == 'capturedhtmlpage' ||
          candidateType == 'captured_html' ||
          candidateType == 'pioneer_captured_html' ||
          candidateType == 'clipboard' ||
          candidateType == 'savedfile';
    });
  }

  String? get textReadUrl {
    if (!textReadAvailable) return null;
    final sourceCandidate = sourceUrl?.trim();
    if (sourceCandidate?.isNotEmpty == true) {
      return sourceCandidate;
    }
    final preferredCapture = preferredCaptureCandidate;
    if (preferredCapture?.hasUrl == true) {
      return preferredCapture!.url!.trim();
    }
    return launchUrl?.trim();
  }

  String? get textReadWorkId {
    if (!textReadAvailable) return null;
    return stableLibraryItemId;
  }

  PioneerTextCaptureStatus get textCaptureStatus {
    if (textReadAvailable) {
      return PioneerTextCaptureStatus.textSource;
    }
    if (textCaptureAvailable) {
      return PioneerTextCaptureStatus.captureNeeded;
    }
    return PioneerTextCaptureStatus.sourceNeeded;
  }

  PioneerEpubValidationStatus get epubValidationStatus {
    if (!epubAvailable) {
      return PioneerEpubValidationStatus.unavailable;
    }
    return PioneerEpubValidationStatus.needsReview;
  }

  bool get hasValidatedEpubSource =>
      epubValidationStatus == PioneerEpubValidationStatus.validated;

  bool get hasUsableSourcePath => textReadAvailable;

  String? get epubRejectedReason {
    if (epubValidationStatus == PioneerEpubValidationStatus.needsReview) {
      return null;
    }
    return null;
  }

  PioneerSourceImportMethodPreference get preferredImportMethod {
    if (textReadAvailable) {
      return PioneerSourceImportMethodPreference.textReadCapture;
    }
    if (sourceNeededReason != null) {
      return PioneerSourceImportMethodPreference.sourceNeeded;
    }
    return PioneerSourceImportMethodPreference.userSuppliedCleanedSource;
  }

  PioneerSourceImportMethodPreference get fallbackImportMethod {
    if (textCaptureAvailable) {
      return PioneerSourceImportMethodPreference.userSuppliedCleanedSource;
    }
    return PioneerSourceImportMethodPreference.sourceNeeded;
  }

  String? get sourceNeededReason {
    if (hasUsableSourcePath) {
      return null;
    }
    if (textCaptureAvailable) {
      return 'Capture is needed before this source can be imported.';
    }
    return 'No usable source path is seeded yet.';
  }

  bool get isImportable =>
      hasVerifiedSource &&
      availability.isImportable &&
      catalogImportable &&
      textReadAvailable;

  String get sourceTypeLabel {
    final preferred = preferredSourceCandidate;
    if (preferred != null) {
      return preferred.displayLabel;
    }
    final normalized = sourceType?.trim() ?? '';
    if (normalized.isEmpty) return 'Unknown';
    switch (normalized) {
      case 'egwreadpage':
        return 'EGW READER CAPTURE';
      case 'webviewcapturedhtml':
      case 'webviewcapturedhtmlpage':
        return 'EGW CAPTURED HTML';
      case 'directepub':
      case 'epub':
      case 'epubzipentry':
      case 'pdf':
        return 'CAPTURE NEEDED';
    }
    final spaced = normalized
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return spaced.toUpperCase();
  }

  String get preferredImportMethodLabel {
    return preferredImportMethod.label;
  }

  String get fallbackImportMethodLabel => fallbackImportMethod.label;

  String get compactImportStatusLabel {
    switch (textCaptureStatus) {
      case PioneerTextCaptureStatus.textSource:
      case PioneerTextCaptureStatus.captureNeeded:
        return textCaptureStatus.label;
      case PioneerTextCaptureStatus.sourceNeeded:
        return availability.friendlyLabel;
    }
  }

  String? get launchUrl {
    final webViewCandidate = preferredCaptureCandidate;
    if (webViewCandidate?.hasUrl == true) {
      return webViewCandidate!.url!.trim();
    }
    final sourceCandidate = sourceUrl?.trim() ?? '';
    if (sourceCandidate.isNotEmpty && !_isDirectFileUrl(sourceCandidate)) {
      final normalizedSourceType = _normalizeSourceType(sourceType);
      if (normalizedSourceType == 'egwreadpage' ||
          normalizedSourceType == 'capturedhtml' ||
          normalizedSourceType == 'capturedhtmlpage' ||
          normalizedSourceType == 'captured_html' ||
          normalizedSourceType == 'pioneer_captured_html' ||
          normalizedSourceType == 'html') {
        return sourceCandidate;
      }
    }
    return null;
  }

  bool get hasDirectFileSource =>
      _isDirectFileUrl(sourceUrl) ||
      _isDirectFileUrl(directFileUrl) ||
      _isDirectFileUrl(captureUrl) ||
      _isDirectFileUrl(readerUrl) ||
      effectiveSourceCandidates.any(
        (candidate) => candidate.isDirectFileSource,
      );

  PioneerSourceCandidate? get preferredSourceCandidate {
    return _preferredSourceCandidateFromCandidates(effectiveSourceCandidates);
  }

  PioneerSourceCandidate? get preferredImportCandidate {
    return _preferredImportCandidateFromCandidates(effectiveSourceCandidates);
  }

  PioneerSourceCandidate? get preferredCaptureCandidate {
    final sorted = effectiveSourceCandidates
        .where((candidate) => candidate.canOpenInWebView && candidate.hasUrl)
        .toList();
    if (sorted.isEmpty) return null;
    sorted.sort(_compareCandidates);
    return sorted.first;
  }

  List<PioneerSourceCandidate> get alternateSourceCandidates {
    final candidates = effectiveSourceCandidates;
    if (candidates.isEmpty) return const <PioneerSourceCandidate>[];
    final sorted = [...candidates]..sort(_compareCandidates);
    final preferred = preferredSourceCandidate;
    return List<PioneerSourceCandidate>.unmodifiable(
      sorted.where((candidate) => !identical(candidate, preferred)),
    );
  }

  List<PioneerSourceCandidate> get effectiveSourceCandidates {
    if (sourceCandidates.isNotEmpty) {
      return sourceCandidates;
    }
    return _legacySourceCandidatesForWork(this);
  }

  String get stableLibraryItemId =>
      'library_item_research_pioneer_${authorId}_$id';

  String libraryItemIdForSourceKey(String sourceKey) {
    final normalizedSourceKey = _stableId(sourceKey);
    if (normalizedSourceKey.isEmpty) {
      return stableLibraryItemId;
    }
    return '${stableLibraryItemId}_$normalizedSourceKey';
  }

  String get copiedRangeLibraryItemId =>
      libraryItemIdForSourceKey('egw_copied_range');

  bool _hasCompatibleSourceCandidateOverlap(PioneerSourceWork other) {
    final leftCandidates = effectiveSourceCandidates;
    final rightCandidates = other.effectiveSourceCandidates;
    if (leftCandidates.isEmpty || rightCandidates.isEmpty) return false;
    for (final left in leftCandidates) {
      for (final right in rightCandidates) {
        if (_candidatesAreCompatible(left, right)) {
          return true;
        }
      }
    }
    return false;
  }

  bool get _hasDirectEpubCandidate => effectiveSourceCandidates.any(
    (candidate) => candidate.sourceType.trim().toLowerCase() == 'directepub',
  );

  bool get _hasZipEntryCandidate => effectiveSourceCandidates.any(
    (candidate) => candidate.sourceType.trim().toLowerCase() == 'epubzipentry',
  );
}

@immutable
class PioneerSourceAuthor {
  const PioneerSourceAuthor({
    required this.id,
    required this.name,
    required this.sourceFamily,
    required this.works,
    required this.sortKey,
  });

  final String id;
  final String name;
  final String? sourceFamily;
  final List<PioneerSourceWork> works;
  final String sortKey;

  factory PioneerSourceAuthor.fromJson(Map<String, Object?> json) {
    final name = _requiredString(json, const ['author_name', 'name']);
    final sourceFamily = _optionalString(json, const [
      'source_family',
      'sourceFamily',
    ]);
    final id = _stableId(
      _optionalString(json, const ['author_id', 'id']) ?? name,
    );
    final worksJson = json['works'];
    final works = <PioneerSourceWork>[];
    if (worksJson is List) {
      for (final rawWork in worksJson) {
        if (rawWork is! Map) continue;
        final typedWork = rawWork.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        works.add(
          PioneerSourceWork.fromJson(
            authorId: id,
            authorName: name,
            sourceFamily: sourceFamily,
            json: typedWork,
          ),
        );
      }
    }

    final normalizedSortKey =
        _optionalString(json, const ['sort_key', 'sortKey']) ??
        name.toLowerCase();

    return PioneerSourceAuthor(
      id: id,
      name: name,
      sourceFamily: sourceFamily,
      works: List<PioneerSourceWork>.unmodifiable(
        works..sort(_compareWorksForDisplay),
      ),
      sortKey: normalizedSortKey,
    );
  }
}

@immutable
class PioneerEpubCollectionDiagnostics {
  const PioneerEpubCollectionDiagnostics({
    required this.totalArchiveEntryCount,
    required this.epubEntryCount,
    required this.authorCount,
    required this.unknownAuthorCount,
    required this.duplicateEntriesSkipped,
    required this.authorEntryCounts,
  });

  final int totalArchiveEntryCount;
  final int epubEntryCount;
  final int authorCount;
  final int unknownAuthorCount;
  final int duplicateEntriesSkipped;
  final Map<String, int> authorEntryCounts;

  List<MapEntry<String, int>> topAuthorCounts({int limit = 20}) {
    final sorted = authorEntryCounts.entries.toList()
      ..sort((left, right) {
        final compareCount = right.value.compareTo(left.value);
        if (compareCount != 0) return compareCount;
        return left.key.compareTo(right.key);
      });
    return List<MapEntry<String, int>>.unmodifiable(sorted.take(limit));
  }

  String get summaryText {
    return 'ZIP entries: $totalArchiveEntryCount • EPUB entries: '
        '$epubEntryCount • Authors: $authorCount • Needs review: '
        '$unknownAuthorCount • Duplicates skipped: $duplicateEntriesSkipped';
  }
}

@immutable
class PioneerSourceCatalog {
  const PioneerSourceCatalog({
    required this.authors,
    required this.authorsById,
    required this.worksById,
    this.diagnostics,
  });

  static const String assetPath = kPioneerSourceCatalogAssetPath;

  final List<PioneerSourceAuthor> authors;
  final Map<String, PioneerSourceAuthor> authorsById;
  final Map<String, PioneerSourceWork> worksById;
  final PioneerEpubCollectionDiagnostics? diagnostics;

  int get authorCount => authors.length;
  int get workCount => worksById.length;

  PioneerSourceAuthor? authorById(String id) {
    return authorsById[_stableId(id)];
  }

  PioneerSourceWork? workById(String id) {
    return worksById[_stableId(id)];
  }

  Iterable<PioneerSourceWork> get works sync* {
    for (final author in authors) {
      yield* author.works;
    }
  }

  Iterable<PioneerSourceWork> get importableWorks sync* {
    for (final work in works) {
      if (work.isImportable) yield work;
    }
  }

  Iterable<PioneerSourceWork> get sourceNeededWorks sync* {
    for (final work in works) {
      if (!work.isImportable) yield work;
    }
  }

  factory PioneerSourceCatalog.fromJson(Map<String, Object?> json) {
    final authorsJson = json['authors'];
    final authors = <PioneerSourceAuthor>[];
    if (authorsJson is List) {
      for (final rawAuthor in authorsJson) {
        if (rawAuthor is! Map) continue;
        final typedAuthor = rawAuthor.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        authors.add(PioneerSourceAuthor.fromJson(typedAuthor));
      }
    }

    return PioneerSourceCatalog._fromAuthors(authors);
  }

  static Future<PioneerSourceCatalog> load({AssetBundle? bundle}) async {
    final assetBundle = bundle ?? rootBundle;
    final jsonText = await assetBundle.loadString(assetPath);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, Object?>) {
      throw StateError('Invalid Pioneer source catalog.');
    }
    return PioneerSourceCatalog.fromJson(decoded);
  }

  static PioneerSourceCatalog merge(Iterable<PioneerSourceCatalog> catalogs) {
    final catalogList = catalogs.toList(growable: false);
    final mergedAuthors = <String, _MergedAuthorGroup>{};
    for (final catalog in catalogList) {
      for (final author in catalog.authors) {
        final authorKey = _stableId(author.name);
        final group = mergedAuthors.putIfAbsent(
          authorKey,
          () => _MergedAuthorGroup(
            authorId: author.id,
            authorName: author.name,
            sourceFamily: author.sourceFamily,
            sortKey: author.sortKey,
          ),
        );
        group.mergeAuthor(author);
      }
    }

    final authors =
        mergedAuthors.values
            .map((group) => group.toAuthor())
            .toList(growable: false)
          ..sort((left, right) {
            final compareSortKey = left.sortKey.compareTo(right.sortKey);
            if (compareSortKey != 0) return compareSortKey;
            return left.name.compareTo(right.name);
          });

    final authorsById = <String, PioneerSourceAuthor>{};
    final worksById = <String, PioneerSourceWork>{};
    for (final author in authors) {
      authorsById[author.id] = author;
      for (final work in author.works) {
        worksById[work.id] = work;
      }
    }

    return PioneerSourceCatalog(
      authors: List<PioneerSourceAuthor>.unmodifiable(authors),
      authorsById: Map<String, PioneerSourceAuthor>.unmodifiable(authorsById),
      worksById: Map<String, PioneerSourceWork>.unmodifiable(worksById),
      diagnostics: catalogList.isNotEmpty
          ? catalogList.first.diagnostics
          : null,
    );
  }

  PioneerSourceCatalog validateZipEntries(Iterable<String> zipEntries) {
    final normalizedZipEntries = <String>{
      for (final entry in zipEntries)
        if (entry.trim().isNotEmpty) p.normalize(entry.trim()).toLowerCase(),
    };

    final validatedAuthors = authors
        .map(
          (author) => PioneerSourceAuthor(
            id: author.id,
            name: author.name,
            sourceFamily: author.sourceFamily,
            works: List<PioneerSourceWork>.unmodifiable(
              author.works
                  .map((work) {
                    final validatedCandidates = work.sourceCandidates
                        .map((candidate) {
                          if (candidate.sourceType.trim().toLowerCase() !=
                              'epubzipentry') {
                            return candidate;
                          }
                          final zipEntry = candidate.zipEntry?.trim();
                          if (zipEntry?.isNotEmpty != true) {
                            return candidate.copyWith(
                              availability:
                                  PioneerSourceAvailability.sourceNeeded,
                              notes: _mergeTextFields([
                                candidate.notes,
                                'ZIP entry is missing from the archive.',
                              ]),
                            );
                          }
                          final normalizedZipEntry = p
                              .normalize(zipEntry!)
                              .toLowerCase();
                          if (normalizedZipEntries.contains(
                            normalizedZipEntry,
                          )) {
                            return candidate;
                          }
                          return candidate.copyWith(
                            availability:
                                PioneerSourceAvailability.sourceNeeded,
                            notes: _mergeTextFields([
                              candidate.notes,
                              'ZIP entry is missing from the archive.',
                            ]),
                          );
                        })
                        .toList(growable: false);
                    final immutableValidatedCandidates =
                        List<PioneerSourceCandidate>.unmodifiable(
                          validatedCandidates,
                        );

                    final hasImportableCandidate = immutableValidatedCandidates
                        .any((candidate) => candidate.supportsAutoImport);
                    if (hasImportableCandidate) {
                      return work.copyWith(
                        sourceCandidates: immutableValidatedCandidates,
                      );
                    }

                    return work.copyWith(
                      availability: PioneerSourceAvailability.sourceNeeded,
                      catalogImportable: false,
                      sourceCandidates: immutableValidatedCandidates,
                    );
                  })
                  .toList(growable: false),
            ),
            sortKey: author.sortKey,
          ),
        )
        .toList(growable: false);

    final authorsById = <String, PioneerSourceAuthor>{};
    final worksById = <String, PioneerSourceWork>{};
    for (final author in validatedAuthors) {
      authorsById[author.id] = author;
      for (final work in author.works) {
        worksById[work.id] = work;
      }
    }

    return PioneerSourceCatalog(
      authors: List<PioneerSourceAuthor>.unmodifiable(validatedAuthors),
      authorsById: Map<String, PioneerSourceAuthor>.unmodifiable(authorsById),
      worksById: Map<String, PioneerSourceWork>.unmodifiable(worksById),
      diagnostics: diagnostics,
    );
  }

  factory PioneerSourceCatalog._fromAuthors(List<PioneerSourceAuthor> authors) {
    final sortedAuthors = List<PioneerSourceAuthor>.from(authors)
      ..sort((left, right) {
        final compareSortKey = left.sortKey.compareTo(right.sortKey);
        if (compareSortKey != 0) return compareSortKey;
        return left.name.compareTo(right.name);
      });

    final authorsById = <String, PioneerSourceAuthor>{};
    final worksById = <String, PioneerSourceWork>{};
    for (final author in sortedAuthors) {
      authorsById[author.id] = author;
      for (final work in author.works) {
        worksById[work.id] = work;
      }
    }

    return PioneerSourceCatalog(
      authors: List<PioneerSourceAuthor>.unmodifiable(sortedAuthors),
      authorsById: Map<String, PioneerSourceAuthor>.unmodifiable(authorsById),
      worksById: Map<String, PioneerSourceWork>.unmodifiable(worksById),
    );
  }
}

@immutable
class PioneerSourceSelection {
  const PioneerSourceSelection._(this.selectedWorkIds);

  factory PioneerSourceSelection.empty() {
    return const PioneerSourceSelection._(<String>{});
  }

  factory PioneerSourceSelection.fromWorkIds(Iterable<String> workIds) {
    final normalized = <String>{};
    for (final workId in workIds) {
      final id = _stableId(workId);
      if (id.isNotEmpty) {
        normalized.add(id);
      }
    }
    return PioneerSourceSelection._(Set<String>.unmodifiable(normalized));
  }

  final Set<String> selectedWorkIds;

  int get selectedCount => selectedWorkIds.length;

  bool isSelected(String workId) {
    return selectedWorkIds.contains(_stableId(workId));
  }

  PioneerSourceSelection toggle(String workId) {
    final normalized = _stableId(workId);
    final next = Set<String>.from(selectedWorkIds);
    if (!next.add(normalized)) {
      next.remove(normalized);
    }
    return PioneerSourceSelection._(Set<String>.unmodifiable(next));
  }

  List<PioneerSourceWork> selectedWorks(PioneerSourceCatalog catalog) {
    return catalog.works
        .where((work) => selectedWorkIds.contains(work.id))
        .toList(growable: false);
  }

  List<PioneerSourceWork> importableSelectedWorks(
    PioneerSourceCatalog catalog,
  ) {
    return selectedWorks(
      catalog,
    ).where((work) => work.isImportable).toList(growable: false);
  }

  List<PioneerSourceWork> blockedSelectedWorks(PioneerSourceCatalog catalog) {
    return selectedWorks(
      catalog,
    ).where((work) => !work.isImportable).toList(growable: false);
  }

  bool canImport(PioneerSourceCatalog catalog) {
    return importableSelectedWorks(catalog).isNotEmpty;
  }

  String? importBlockMessage(PioneerSourceCatalog catalog) {
    final selected = selectedWorks(catalog);
    if (selected.isEmpty) {
      return 'Select one or more works to import.';
    }
    final blockedCount = blockedSelectedWorks(catalog).length;
    final importableCount = importableSelectedWorks(catalog).length;
    if (importableCount > 0) {
      if (blockedCount == 0) return null;
      return '$blockedCount selected work${blockedCount == 1 ? '' : 's'} need a verified source first.';
    }
    return 'No selected Pioneer work has a verified source yet.';
  }
}

String? _optionalString(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

bool? _optionalBool(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) continue;
    if (text == 'true' || text == '1' || text == 'yes' || text == 'y') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no' || text == 'n') {
      return false;
    }
  }
  return null;
}

String _requiredString(Map<String, Object?> json, List<String> keys) {
  final value = _optionalString(json, keys);
  if (value == null) {
    throw StateError('Missing required Pioneer source catalog field.');
  }
  return value;
}

String _stableId(String value) {
  final normalized = value.toLowerCase().trim();
  if (normalized.isEmpty) return '';
  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

String pioneerSourceWorkIdentityKey({
  required String provider,
  required String authorName,
  required String title,
  required String sourceType,
  String? zipEntry,
  String? sourceUrl,
  int? sourceIndex,
}) {
  final normalizedBase = _stableId(
    '${provider}_${authorName}_${title}_$sourceType',
  );
  final identitySource = zipEntry?.trim().isNotEmpty == true
      ? zipEntry!.trim()
      : sourceUrl?.trim().isNotEmpty == true
      ? sourceUrl!.trim()
      : sourceIndex?.toString() ?? '';
  if (identitySource.isEmpty) {
    return normalizedBase;
  }
  return '${normalizedBase}_${_stableHash(identitySource)}';
}

String _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String? _friendlySourceHost(String? sourceUrl) {
  final normalized = sourceUrl?.trim() ?? '';
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  final host = uri?.host.trim().toLowerCase() ?? '';
  if (host.isEmpty) return null;
  final cleaned = host.startsWith('www.') ? host.substring(4) : host;
  switch (cleaned) {
    case 'archive.org':
      return 'Archive.org';
    case 'adventaudio.org':
      return 'AdventAudio';
    case 'gutenberg.org':
      return 'Project Gutenberg';
    case 'egwwritings.org':
      return 'EGW Writings';
  }
  return cleaned;
}

String? _normalizeSourceType(String? sourceType) {
  final normalized = sourceType?.trim() ?? '';
  return normalized.isEmpty ? null : normalized.toLowerCase();
}

List<PioneerSourceCandidate> _parseSourceCandidates(
  Map<String, Object?> json, {
  required PioneerSourceAvailability availability,
  required String? sourceFamily,
  required String? sourceLabel,
  required String? legacySourceType,
  required String? legacySourceUrl,
  required String? collectionUrl,
  required String? captureUrl,
  required String? readerUrl,
  required String? directFileUrl,
  required String? directFileType,
  required bool verified,
}) {
  final parsedCandidates = <PioneerSourceCandidate>[];
  final rawCandidates =
      json['source_candidates'] ?? json['sourceCandidates'] ?? json['sources'];
  if (rawCandidates is List) {
    for (final rawCandidate in rawCandidates) {
      if (rawCandidate is! Map) continue;
      final typedCandidate = rawCandidate.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final provider = _optionalString(typedCandidate, const ['provider']);
      final sourceType = _optionalString(typedCandidate, const [
        'source_type',
        'sourceType',
      ]);
      final url = _optionalString(typedCandidate, const ['url', 'source_url']);
      if (provider == null || sourceType == null) continue;
      parsedCandidates.add(
        PioneerSourceCandidate(
          provider: _normalizeCandidateProvider(provider),
          sourceType: _normalizeCandidateSourceType(sourceType),
          url: url,
          priority:
              _optionalInt(typedCandidate, const ['priority']) ??
              _defaultCandidatePriority(
                provider: provider,
                sourceType: sourceType,
                url: url,
              ),
          qualityTier:
              _optionalString(typedCandidate, const [
                'quality_tier',
                'qualityTier',
              ]) ??
              _defaultCandidateQualityTier(
                provider: provider,
                sourceType: sourceType,
                url: url,
              ),
          availability: PioneerSourceAvailability.fromStoredValue(
            _optionalString(typedCandidate, const ['availability']),
          ),
          editionLabel: _optionalString(typedCandidate, const [
            'edition_label',
            'editionLabel',
          ]),
          editionYear: _optionalInt(typedCandidate, const [
            'edition_year',
            'editionYear',
          ]),
          requiresVerification:
              _optionalBool(typedCandidate, const ['requires_verification']) ??
              false,
          zipEntry: _optionalString(typedCandidate, const [
            'zip_entry',
            'zipEntry',
          ]),
          destructiveReplacementAllowed:
              _optionalBool(typedCandidate, const [
                'destructive_replacement_allowed',
              ]) ??
              false,
          isRepairSource:
              _optionalBool(typedCandidate, const ['is_repair_source']) ??
              false,
          userMustConfirmReplacement:
              _optionalBool(typedCandidate, const [
                'user_must_confirm_replacement',
              ]) ??
              true,
          notes: _optionalString(typedCandidate, const ['notes']),
        ),
      );
    }
  }

  if (parsedCandidates.isNotEmpty) {
    parsedCandidates.sort(_compareCandidates);
    return parsedCandidates;
  }

  final synthesized = <PioneerSourceCandidate>[];
  final legacySourceTypeNormalized = _normalizeSourceType(legacySourceType);
  final legacySourceUrlNormalized = legacySourceUrl?.trim();
  final provider = _inferProviderFromSource(
    sourceFamily: sourceFamily,
    sourceLabel: sourceLabel,
    sourceUrl: legacySourceUrlNormalized,
  );

  if (legacySourceUrlNormalized?.isNotEmpty == true ||
      captureUrl?.trim().isNotEmpty == true ||
      readerUrl?.trim().isNotEmpty == true ||
      directFileUrl?.trim().isNotEmpty == true) {
    synthesized.add(
      PioneerSourceCandidate(
        provider: provider,
        sourceType: _legacyCandidateSourceType(
          legacySourceTypeNormalized,
          legacySourceUrlNormalized,
          directFileType: directFileType,
          captureUrl: captureUrl,
          readerUrl: readerUrl,
          directFileUrl: directFileUrl,
        ),
        url: _legacyCandidateUrl(
          legacySourceUrlNormalized,
          captureUrl: captureUrl,
          readerUrl: readerUrl,
          directFileUrl: directFileUrl,
        ),
        priority: _defaultCandidatePriority(
          provider: provider,
          sourceType: legacySourceTypeNormalized ?? 'html',
          url: legacySourceUrlNormalized,
        ),
        qualityTier: _defaultCandidateQualityTier(
          provider: provider,
          sourceType: legacySourceTypeNormalized ?? 'html',
          url: legacySourceUrlNormalized,
        ),
        availability: availability,
        requiresVerification: !verified,
        destructiveReplacementAllowed: false,
        isRepairSource: false,
        userMustConfirmReplacement: true,
        zipEntry: null,
      ),
    );
  }

  synthesized.sort(_compareCandidates);
  return synthesized;
}

String _normalizeCandidateProvider(String provider) {
  final normalized = provider.trim().toLowerCase();
  switch (normalized) {
    case 'adventaudio':
    case 'advent audio':
      return 'adventaudio';
    case 'egwaudio':
    case 'egw audio':
    case 'ellenwhiteaudio':
    case 'ellen white audio':
      return 'ellenwhiteaudio';
    case 'egw writings':
    case 'egwwritings':
      return 'egwWritings';
    case 'egw existing':
    case 'egwexisting':
      return 'egwExisting';
    case 'saved file':
    case 'savedfile':
      return 'savedFile';
    default:
      return normalized;
  }
}

String _normalizeCandidateSourceType(String sourceType) {
  final normalized = sourceType.trim().toLowerCase();
  switch (normalized) {
    case 'directepub':
    case 'direct_epub':
    case 'direct-epub':
      return 'directEpub';
    case 'epubzipentry':
    case 'epub_zip_entry':
    case 'zipentryepub':
    case 'zip_entry_epub':
      return 'epubZipEntry';
    case 'egwreadpage':
    case 'reader':
    case 'readerpage':
      return 'readerPage';
    case 'captured_html':
    case 'capturedhtmlpage':
    case 'webviewcapturedhtml':
      return 'capturedHtml';
    case 'existingdb':
      return 'existingDb';
    case 'savedfile':
      return 'savedFile';
  }
  return normalized;
}

String _legacyCandidateSourceType(
  String? legacySourceType,
  String? sourceUrl, {
  String? directFileType,
  String? captureUrl,
  String? readerUrl,
  String? directFileUrl,
}) {
  final normalized = legacySourceType?.trim().toLowerCase() ?? '';
  if (normalized.isNotEmpty) {
    if (normalized == 'egwreadpage') return 'readerPage';
    if (normalized == 'webviewcapturedhtml') return 'capturedHtml';
    return normalized;
  }
  if (directFileUrl != null || _isDirectFileUrl(sourceUrl)) {
    final normalizedType = directFileType?.trim().toLowerCase() ?? '';
    if (normalizedType == 'pdf') return 'pdf';
    return 'epub';
  }
  if (captureUrl?.trim().isNotEmpty == true ||
      readerUrl?.trim().isNotEmpty == true) {
    return 'readerPage';
  }
  return 'html';
}

String? _legacyCandidateUrl(
  String? sourceUrl, {
  String? captureUrl,
  String? readerUrl,
  String? directFileUrl,
}) {
  if (readerUrl?.trim().isNotEmpty == true) return readerUrl!.trim();
  if (captureUrl?.trim().isNotEmpty == true) return captureUrl!.trim();
  if (directFileUrl?.trim().isNotEmpty == true) return directFileUrl!.trim();
  if (sourceUrl?.trim().isNotEmpty == true) return sourceUrl!.trim();
  return null;
}

String _inferProviderFromSource({
  required String? sourceFamily,
  required String? sourceLabel,
  required String? sourceUrl,
}) {
  final label = sourceLabel?.trim().toLowerCase() ?? '';
  if (label.contains('egw')) return 'egwWritings';
  if (label.contains('ellenwhiteaudio')) return 'ellenwhiteaudio';
  if (label.contains('adventaudio')) return 'adventaudio';
  if (label.contains('aplib')) return 'aplib';
  if (label.contains('archive')) return 'archive';

  final family = sourceFamily?.trim().toLowerCase() ?? '';
  if (family.contains('adventist pioneer library')) return 'aplib';
  if (family.contains('ellenwhiteaudio')) return 'ellenwhiteaudio';
  if (family.contains('adventaudio')) return 'adventaudio';

  final host = Uri.tryParse(sourceUrl ?? '')?.host.toLowerCase() ?? '';
  if (host.contains('ellenwhiteaudio.org')) return 'ellenwhiteaudio';
  if (host.contains('egwwritings.org')) return 'egwWritings';
  if (host.contains('adventaudio.org')) return 'adventaudio';
  if (host.contains('archive.org')) return 'archive';
  if (host.contains('gutenberg.org')) return 'gutenberg';
  if (host.contains('aplib.org')) {
    return 'aplib';
  }

  return 'local';
}

int _defaultCandidatePriority({
  required String provider,
  required String sourceType,
  required String? url,
}) {
  final normalizedProvider = provider.trim().toLowerCase();
  final normalizedSourceType = sourceType.trim().toLowerCase();
  if (normalizedProvider == 'egwexisting') return 0;
  if ((normalizedProvider == 'ellenwhiteaudio' ||
          normalizedProvider == 'adventaudio') &&
      (normalizedSourceType == 'epub' ||
          normalizedSourceType == 'directepub' ||
          normalizedSourceType == 'epubzipentry')) {
    return 5;
  }
  if (normalizedProvider == 'aplib' &&
      (normalizedSourceType == 'epub' ||
          normalizedSourceType == 'directepub' ||
          normalizedSourceType == 'epubzipentry')) {
    return 10;
  }
  if (normalizedProvider == 'adventaudio' && normalizedSourceType == 'pdf') {
    return 20;
  }
  if (normalizedProvider == 'aplib' && normalizedSourceType == 'pdf') {
    return 25;
  }
  if (normalizedSourceType == 'epub') return 30;
  if (normalizedSourceType == 'epubzipentry') return 30;
  if (normalizedSourceType == 'html') return 40;
  if (normalizedSourceType == 'readerpage') return 50;
  if (normalizedSourceType == 'capturedhtml') return 60;
  if (normalizedSourceType == 'captured_html') return 60;
  if (normalizedSourceType == 'pioneer_captured_html') return 60;
  if (normalizedSourceType == 'pdf') return 70;
  if (normalizedSourceType == 'clipboard') return 80;
  if (normalizedSourceType == 'savedfile') return 90;
  return _isDirectFileUrl(url) ? 75 : 100;
}

String _defaultCandidateQualityTier({
  required String provider,
  required String sourceType,
  required String? url,
}) {
  final normalizedProvider = provider.trim().toLowerCase();
  final normalizedSourceType = sourceType.trim().toLowerCase();
  if (normalizedProvider == 'egwexisting') return 'installed';
  if ((normalizedProvider == 'ellenwhiteaudio' ||
          normalizedProvider == 'adventaudio') &&
      (normalizedSourceType == 'epub' ||
          normalizedSourceType == 'directepub' ||
          normalizedSourceType == 'epubzipentry')) {
    return 'epub';
  }
  if (normalizedProvider == 'aplib' &&
      (normalizedSourceType == 'epub' ||
          normalizedSourceType == 'directepub' ||
          normalizedSourceType == 'epubzipentry')) {
    return 'epub';
  }
  if (normalizedProvider == 'adventaudio' && normalizedSourceType == 'pdf') {
    return 'pdf';
  }
  if (normalizedProvider == 'aplib' && normalizedSourceType == 'pdf') {
    return 'pdf';
  }
  if (normalizedSourceType == 'epub') return 'epub';
  if (normalizedSourceType == 'pdf') return 'pdf';
  if (normalizedSourceType == 'readerpage') return 'reader';
  if (normalizedSourceType == 'capturedhtml') return 'reader';
  if (normalizedSourceType == 'captured_html') return 'reader';
  if (normalizedSourceType == 'pioneer_captured_html') return 'reader';
  if (normalizedSourceType == 'clipboard') return 'clipboard';
  if (normalizedSourceType == 'savedfile') return 'savedfile';
  if (_isDirectFileUrl(url)) return 'epub';
  return 'html';
}

int _compareCandidates(
  PioneerSourceCandidate left,
  PioneerSourceCandidate right,
) {
  final priorityCompare = left.priority.compareTo(right.priority);
  if (priorityCompare != 0) return priorityCompare;
  final qualityCompare = right.qualityRank.compareTo(left.qualityRank);
  if (qualityCompare != 0) return qualityCompare;
  final leftHasUrl = left.hasUrl;
  final rightHasUrl = right.hasUrl;
  if (leftHasUrl && !rightHasUrl) return -1;
  if (!leftHasUrl && rightHasUrl) return 1;
  // Prefer candidates with an explicit ZIP entry path (more specific) over
  // generic candidates pointing to the same ZIP URL without an entry path.
  final leftHasZipEntry = left.zipEntry?.trim().isNotEmpty == true;
  final rightHasZipEntry = right.zipEntry?.trim().isNotEmpty == true;
  if (leftHasZipEntry && !rightHasZipEntry) return -1;
  if (!leftHasZipEntry && rightHasZipEntry) return 1;
  return left.displayLabel.compareTo(right.displayLabel);
}

int _compareWorksForDisplay(PioneerSourceWork left, PioneerSourceWork right) {
  final titleCompare = left.title.compareTo(right.title);
  if (titleCompare != 0) return titleCompare;
  final leftEditionYear = left.normalizedEditionYear ?? 0;
  final rightEditionYear = right.normalizedEditionYear ?? 0;
  final editionYearCompare = leftEditionYear.compareTo(rightEditionYear);
  if (editionYearCompare != 0) return editionYearCompare;
  final leftEditionLabel = left.normalizedEditionLabel ?? '';
  final rightEditionLabel = right.normalizedEditionLabel ?? '';
  final editionLabelCompare = leftEditionLabel.compareTo(rightEditionLabel);
  if (editionLabelCompare != 0) return editionLabelCompare;
  return left.abbreviation.compareTo(right.abbreviation);
}

List<PioneerSourceCandidate> _mergeSourceCandidates(
  List<PioneerSourceCandidate> candidates,
) {
  if (candidates.isEmpty) {
    return const <PioneerSourceCandidate>[];
  }

  final mergedByKey = <String, PioneerSourceCandidate>{};
  final orderedKeys = <String>[];
  for (final candidate in candidates) {
    final key = _candidateMergeKey(candidate);
    final existing = mergedByKey[key];
    if (existing == null) {
      mergedByKey[key] = candidate;
      orderedKeys.add(key);
      continue;
    }
    mergedByKey[key] = _mergeCandidate(existing, candidate);
  }

  final merged = orderedKeys.map((key) => mergedByKey[key]!).toList();
  merged.sort(_compareCandidates);
  return List<PioneerSourceCandidate>.unmodifiable(merged);
}

PioneerSourceCandidate? _preferredSourceCandidateFromCandidates(
  Iterable<PioneerSourceCandidate> candidates,
) {
  final textCapture = candidates
      .where(
        (candidate) =>
            candidate.hasUrl &&
            candidate.isTextCaptureCandidate &&
            !candidate.isLegacyFileCandidate,
      )
      .toList();
  if (textCapture.isNotEmpty) {
    textCapture.sort(_compareCandidates);
    return textCapture.first;
  }

  final sourceNeededCapture = candidates
      .where(
        (candidate) =>
            !candidate.hasUrl &&
            candidate.isTextCaptureCandidate &&
            !candidate.isLegacyFileCandidate,
      )
      .toList();
  if (sourceNeededCapture.isNotEmpty) {
    sourceNeededCapture.sort(_compareCandidates);
    return sourceNeededCapture.first;
  }

  final fallback = candidates
      .where((candidate) => !candidate.isLegacyFileCandidate)
      .toList();
  if (fallback.isNotEmpty) {
    fallback.sort(_compareCandidates);
    return fallback.first;
  }
  return null;
}

PioneerSourceCandidate? _preferredImportCandidateFromCandidates(
  Iterable<PioneerSourceCandidate> candidates,
) {
  final importable = candidates
      .where((candidate) => candidate.supportsAutoImport)
      .toList();
  if (importable.isEmpty) return null;
  importable.sort(_compareCandidates);
  return importable.first;
}

PioneerSourceCandidate _mergeCandidate(
  PioneerSourceCandidate left,
  PioneerSourceCandidate right,
) {
  return PioneerSourceCandidate(
    provider: left.provider.trim().isNotEmpty ? left.provider : right.provider,
    sourceType: left.sourceType.trim().isNotEmpty
        ? left.sourceType
        : right.sourceType,
    url: _mergeFirstNonEmpty([left.url, right.url]),
    zipEntry: _mergeFirstNonEmpty([left.zipEntry, right.zipEntry]),
    editionLabel: _mergeFirstNonEmpty([left.editionLabel, right.editionLabel]),
    editionYear: left.editionYear ?? right.editionYear,
    priority: left.priority < right.priority ? left.priority : right.priority,
    qualityTier:
        (_qualityRankForTier(left.qualityTier) >=
            _qualityRankForTier(right.qualityTier))
        ? left.qualityTier
        : right.qualityTier,
    availability: _mergeCandidateAvailability(
      left.availability,
      right.availability,
    ),
    requiresVerification:
        left.requiresVerification || right.requiresVerification,
    destructiveReplacementAllowed:
        left.destructiveReplacementAllowed ||
        right.destructiveReplacementAllowed,
    isRepairSource: left.isRepairSource || right.isRepairSource,
    userMustConfirmReplacement:
        left.userMustConfirmReplacement || right.userMustConfirmReplacement,
    notes: _mergeTextFields([left.notes, right.notes]),
  );
}

PioneerSourceAvailability _mergeCandidateAvailability(
  PioneerSourceAvailability left,
  PioneerSourceAvailability right,
) {
  final values = [left, right];
  if (values.contains(PioneerSourceAvailability.available)) {
    return PioneerSourceAvailability.available;
  }
  if (values.contains(PioneerSourceAvailability.imported)) {
    return PioneerSourceAvailability.imported;
  }
  if (values.contains(PioneerSourceAvailability.sourceNeeded)) {
    return PioneerSourceAvailability.sourceNeeded;
  }
  if (values.contains(PioneerSourceAvailability.unavailable)) {
    return PioneerSourceAvailability.unavailable;
  }
  return PioneerSourceAvailability.unknown;
}

PioneerSourceAvailability _mergeAvailability(
  PioneerSourceAvailability left,
  PioneerSourceAvailability right,
  List<PioneerSourceCandidate> candidates,
) {
  final candidateAvailability = candidates.isEmpty
      ? PioneerSourceAvailability.unknown
      : candidates
            .map((candidate) => candidate.availability)
            .fold(
              PioneerSourceAvailability.unknown,
              _mergeCandidateAvailability,
            );
  return _mergeCandidateAvailability(
    _mergeCandidateAvailability(left, right),
    candidateAvailability,
  );
}

String? _mergeFirstNonEmpty(List<String?> values) {
  for (final value in values) {
    final normalized = value?.trim();
    if (normalized?.isNotEmpty == true) {
      return normalized;
    }
  }
  return null;
}

String? _mergeTextFields(List<String?> values) {
  final merged = <String>[];
  for (final value in values) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) continue;
    if (!merged.contains(normalized)) {
      merged.add(normalized);
    }
  }
  if (merged.isEmpty) return null;
  return merged.join('\n');
}

String _candidateMergeKey(PioneerSourceCandidate candidate) {
  final provider = candidate.provider.trim().toLowerCase();
  final sourceType = candidate.sourceType.trim().toLowerCase();
  final url = candidate.url?.trim().toLowerCase() ?? '';
  if (candidate.zipEntry?.trim().isNotEmpty == true) {
    return '$provider|$sourceType|$url';
  }
  return '$provider|$sourceType|$url';
}

bool _candidatesAreCompatible(
  PioneerSourceCandidate left,
  PioneerSourceCandidate right,
) {
  final leftProvider = left.provider.trim().toLowerCase();
  final rightProvider = right.provider.trim().toLowerCase();
  final leftSourceType = left.sourceType.trim().toLowerCase();
  final rightSourceType = right.sourceType.trim().toLowerCase();
  final leftUrl = left.url?.trim().toLowerCase() ?? '';
  final rightUrl = right.url?.trim().toLowerCase() ?? '';
  if (leftProvider != rightProvider) return false;
  if (leftSourceType != rightSourceType) return false;
  if (leftUrl != rightUrl) return false;
  final leftZip = left.zipEntry?.trim().toLowerCase() ?? '';
  final rightZip = right.zipEntry?.trim().toLowerCase() ?? '';
  if (leftZip.isNotEmpty && rightZip.isNotEmpty && leftZip != rightZip) {
    return false;
  }
  return true;
}

int _qualityRankForTier(String qualityTier) {
  switch (qualityTier.trim().toLowerCase()) {
    case 'existing':
    case 'installed':
      return 4;
    case 'epub':
      return 4;
    case 'pdf':
      return 2;
    case 'reader':
    case 'capturedhtml':
    case 'captured_html':
    case 'pioneer_captured_html':
    case 'capturedtext':
    case 'html':
      return 1;
    case 'clipboard':
    case 'savedfile':
      return 0;
  }
  return 1;
}

String _titleIdentityBase(String title) {
  final trimmed = title.trim();
  final parsed = _parseEditionFromTitle(trimmed);
  if (parsed != null) {
    return parsed.baseTitle;
  }
  return trimmed;
}

_TitleEditionInfo? _parseEditionFromTitle(String title) {
  final trimmed = title.trim();
  final match = RegExp(r'^(.*?)(?:\s*\((\d{4})\))$').firstMatch(trimmed);
  if (match == null) {
    return null;
  }
  final baseTitle = match.group(1)?.trim() ?? '';
  if (baseTitle.isEmpty) return null;
  final year = int.tryParse(match.group(2) ?? '');
  if (year == null) return null;
  return _TitleEditionInfo(
    baseTitle: baseTitle,
    label: year.toString(),
    year: year,
  );
}

@immutable
class _TitleEditionInfo {
  const _TitleEditionInfo({
    required this.baseTitle,
    required this.label,
    required this.year,
  });

  final String baseTitle;
  final String label;
  final int year;
}

class _MergedAuthorGroup {
  _MergedAuthorGroup({
    required String authorId,
    required String authorName,
    required String? sourceFamily,
    required String sortKey,
  }) : _authorId = authorId,
       _authorName = authorName,
       _sourceFamily = sourceFamily,
       _sortKey = sortKey;

  final String _authorId;
  final String _authorName;
  String? _sourceFamily;
  String _sortKey;
  final List<_MergedWorkGroup> _workGroups = <_MergedWorkGroup>[];

  void mergeAuthor(PioneerSourceAuthor author) {
    if (_sourceFamily == null && author.sourceFamily != null) {
      _sourceFamily = author.sourceFamily;
    }
    if (_sortKey.trim().isEmpty && author.sortKey.trim().isNotEmpty) {
      _sortKey = author.sortKey;
    }

    for (final work in author.works) {
      _MergedWorkGroup? existingGroup;
      for (final group in _workGroups) {
        if (group.canMergeWith(work)) {
          existingGroup = group;
          break;
        }
      }
      if (existingGroup == null) {
        _workGroups.add(_MergedWorkGroup(work));
        continue;
      }
      existingGroup.merge(work);
    }
  }

  PioneerSourceAuthor toAuthor() {
    final works = _workGroups.map((group) => group.work).toList(growable: false)
      ..sort(_compareWorksForDisplay);
    return PioneerSourceAuthor(
      id: _authorId,
      name: _authorName,
      sourceFamily: _sourceFamily,
      works: List<PioneerSourceWork>.unmodifiable(works),
      sortKey: _sortKey,
    );
  }
}

class _MergedWorkGroup {
  _MergedWorkGroup(this.work);

  PioneerSourceWork work;

  bool canMergeWith(PioneerSourceWork nextWork) => work.canMergeWith(nextWork);

  void merge(PioneerSourceWork nextWork) {
    work = work.mergeWith(nextWork);
  }
}

int? _optionalInt(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is int) return value;
    final text = value.toString().trim();
    if (text.isEmpty) continue;
    final parsed = int.tryParse(text);
    if (parsed != null) return parsed;
  }
  return null;
}

List<PioneerSourceCandidate> _legacySourceCandidatesForWork(
  PioneerSourceWork work,
) {
  final provider = _inferProviderFromSource(
    sourceFamily: work.sourceFamily,
    sourceLabel: work.sourceLabel,
    sourceUrl: work.sourceUrl,
  );
  final sourceType = _legacyCandidateSourceType(
    _normalizeSourceType(work.sourceType),
    work.sourceUrl,
    directFileType: work.directFileType,
    captureUrl: work.captureUrl,
    readerUrl: work.readerUrl,
    directFileUrl: work.directFileUrl,
  );
  final url = _legacyCandidateUrl(
    work.sourceUrl,
    captureUrl: work.captureUrl,
    readerUrl: work.readerUrl,
    directFileUrl: work.directFileUrl,
  );
  if (url == null && work.collectionUrl?.trim().isEmpty != false) {
    return const <PioneerSourceCandidate>[];
  }

  return <PioneerSourceCandidate>[
    PioneerSourceCandidate(
      provider: provider,
      sourceType: sourceType,
      url: url ?? work.collectionUrl?.trim(),
      priority: _defaultCandidatePriority(
        provider: provider,
        sourceType: sourceType,
        url: url ?? work.collectionUrl?.trim(),
      ),
      qualityTier: _defaultCandidateQualityTier(
        provider: provider,
        sourceType: sourceType,
        url: url ?? work.collectionUrl?.trim(),
      ),
      availability: work.availability,
      requiresVerification: !work.verified,
      destructiveReplacementAllowed: false,
      isRepairSource: false,
      userMustConfirmReplacement: true,
      notes: work.notes,
    ),
  ];
}

bool _isDirectFileUrl(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return false;
  return normalized.endsWith('.epub') ||
      normalized.endsWith('.pdf') ||
      normalized.endsWith('.zip') ||
      normalized.endsWith('.mobi') ||
      normalized.endsWith('.docx');
}

bool _isEpubSourceCandidate(String sourceType) {
  switch (sourceType.trim().toLowerCase()) {
    case 'epub':
    case 'directepub':
    case 'epubzipentry':
      return true;
  }
  return false;
}
