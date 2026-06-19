import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
    PioneerSourceAvailability.sourceNeeded => 'Source needed',
    PioneerSourceAvailability.imported => 'Imported',
    PioneerSourceAvailability.unavailable => 'Unavailable',
    PioneerSourceAvailability.unknown => 'Status unknown',
  };

  bool get isImportable => this == PioneerSourceAvailability.available;
}

@immutable
class PioneerSourceWork {
  const PioneerSourceWork({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.abbreviation,
    required this.group,
    required this.subgroup,
    required this.availability,
    required this.verified,
    required this.catalogImportable,
    required this.sourceType,
    required this.sourceUrl,
    required this.sourceLabel,
    required this.notes,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String title;
  final String abbreviation;
  final String group;
  final String subgroup;
  final PioneerSourceAvailability availability;
  final bool verified;
  final bool catalogImportable;
  final String? sourceType;
  final String? sourceUrl;
  final String? sourceLabel;
  final String? notes;

  factory PioneerSourceWork.fromJson({
    required String authorId,
    required String authorName,
    required Map<String, Object?> json,
  }) {
    final title = _requiredString(json, const ['title', 'name']);
    final workId = _stableId(
      _optionalString(json, const ['work_id', 'id']) ?? title,
    );
    final availability = PioneerSourceAvailability.fromStoredValue(
      _optionalString(json, const ['availability_status', 'availability']),
    );
    final verified = _optionalBool(json, const ['verified']) ?? false;
    final sourceType = _optionalString(json, const ['source_type', 'sourceType'])
        ?.trim()
        .toLowerCase();
    final sourceUrl = _optionalString(json, const ['source_url', 'sourceUrl']);
    final sourceLabel = _optionalString(json, const [
      'source_label',
      'sourceLabel',
    ]);
    final catalogImportable =
        _optionalBool(json, const ['importable']) ?? availability.isImportable;
    final normalizedSourceUrl = sourceUrl?.trim();
    final normalizedSourceLabel = sourceLabel?.trim();
    return PioneerSourceWork(
      id: workId,
      authorId: _stableId(authorId),
      authorName: authorName,
      title: title,
      abbreviation: _optionalString(json, const ['abbreviation', 'abbr']) ?? '',
      group: _optionalString(json, const ['group']) ?? '',
      subgroup: _optionalString(json, const ['subgroup']) ?? '',
      availability: availability,
      verified: verified,
      catalogImportable: catalogImportable,
      sourceType: sourceType?.isNotEmpty == true ? sourceType : null,
      sourceUrl: normalizedSourceUrl?.isNotEmpty == true
          ? normalizedSourceUrl
          : null,
      sourceLabel: normalizedSourceLabel?.isNotEmpty == true
          ? normalizedSourceLabel
          : null,
      notes: _optionalString(json, const ['notes']),
    );
  }

  String get friendlyAvailabilityLabel => availability.friendlyLabel;

  String get friendlySourceStatusLabel {
    if (sourceUrl == null || sourceUrl!.trim().isEmpty) {
      if (availability.isImportable) {
        return 'Verified source missing URL';
      }
      return 'No verified source';
    }
    if (!verified) {
      return 'Source URL present but not verified';
    }
    final typeLabel = sourceType?.trim().isNotEmpty == true
        ? sourceType!.trim().toUpperCase()
        : 'source';
    return sourceLabel?.trim().isNotEmpty == true
        ? sourceLabel!.trim()
        : 'Verified $typeLabel source available';
  }

  bool get hasVerifiedSource =>
      verified && sourceUrl != null && sourceUrl!.trim().isNotEmpty;

  bool get hasSupportedImportSource =>
      sourceType == 'epub' || sourceType == 'html';

  bool get isImportable =>
      hasVerifiedSource &&
      hasSupportedImportSource &&
      availability.isImportable &&
      catalogImportable;

  String get sourceTypeLabel {
    final normalized = sourceType?.trim() ?? '';
    if (normalized.isEmpty) return 'Unknown';
    return normalized.toUpperCase();
  }

  String get stableLibraryItemId =>
      'library_item_research_pioneer_${authorId}_$id';
}

@immutable
class PioneerSourceAuthor {
  const PioneerSourceAuthor({
    required this.id,
    required this.name,
    required this.works,
    required this.sortKey,
  });

  final String id;
  final String name;
  final List<PioneerSourceWork> works;
  final String sortKey;

  factory PioneerSourceAuthor.fromJson(Map<String, Object?> json) {
    final name = _requiredString(json, const ['author_name', 'name']);
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
      works: List<PioneerSourceWork>.unmodifiable(
        works..sort((a, b) => a.title.compareTo(b.title)),
      ),
      sortKey: normalizedSortKey,
    );
  }
}

@immutable
class PioneerSourceCatalog {
  const PioneerSourceCatalog({
    required this.authors,
    required this.authorsById,
    required this.worksById,
  });

  static const String assetPath = kPioneerSourceCatalogAssetPath;

  final List<PioneerSourceAuthor> authors;
  final Map<String, PioneerSourceAuthor> authorsById;
  final Map<String, PioneerSourceWork> worksById;

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

    authors.sort((a, b) {
      final compareSortKey = a.sortKey.compareTo(b.sortKey);
      if (compareSortKey != 0) return compareSortKey;
      return a.name.compareTo(b.name);
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
    );
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
}

@immutable
class PioneerSourceSelection {
  const PioneerSourceSelection._(this.selectedWorkIds);

  factory PioneerSourceSelection.empty() {
    return const PioneerSourceSelection._(<String>{});
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
