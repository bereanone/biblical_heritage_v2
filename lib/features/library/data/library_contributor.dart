import 'package:flutter/foundation.dart';

@immutable
class LibraryContributor {
  const LibraryContributor({
    required this.id,
    required this.displayName,
    this.fullName,
    this.sortName,
    this.normalizedName,
  });

  final String id;
  final String displayName;
  final String? fullName;
  final String? sortName;
  final String? normalizedName;

  factory LibraryContributor.fromRow(Map<String, Object?> row) {
    return LibraryContributor(
      id: row['id']?.toString() ?? '',
      displayName: row['display_name']?.toString() ?? '',
      fullName: row['full_name']?.toString(),
      sortName: row['sort_name']?.toString(),
      normalizedName: row['normalized_name']?.toString(),
    );
  }

  Map<String, Object?> toRow(String now) => {
    'id': id,
    'display_name': displayName,
    'full_name': fullName,
    'sort_name': sortName,
    'normalized_name': normalizedName ?? _normalizeContributorName(displayName),
    'created_at': now,
    'updated_at': now,
  };
}

@immutable
class LibraryItemContributor {
  const LibraryItemContributor({
    required this.libraryItemId,
    required this.contributor,
    required this.role,
    required this.sortOrder,
    required this.isPrimary,
  });

  final String libraryItemId;
  final LibraryContributor contributor;
  final String role;
  final int sortOrder;
  final bool isPrimary;

  Map<String, Object?> toRow(String now) => {
    'library_item_id': libraryItemId,
    'contributor_id': contributor.id,
    'role': role,
    'sort_order': sortOrder,
    'is_primary': isPrimary ? 1 : 0,
    'created_at': now,
  };
}

/// Parsed from metadata.json in capture folders, or hardcoded for known works.
@immutable
class ImportContributorSpec {
  const ImportContributorSpec({
    required this.name,
    this.fullName,
    this.role = 'author',
    this.sortOrder = 0,
    this.isPrimary = false,
  });

  final String name;
  final String? fullName;
  final String role;
  final int sortOrder;
  final bool isPrimary;

  factory ImportContributorSpec.fromJson(Map<String, Object?> json) {
    return ImportContributorSpec(
      name: json['name']?.toString() ?? '',
      fullName: json['full_name']?.toString(),
      role: json['role']?.toString() ?? 'author',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isPrimary: json['primary'] == true,
    );
  }

  String get stableId => _normalizeContributorName(name);

  LibraryContributor toContributor() => LibraryContributor(
    id: stableId,
    displayName: name,
    fullName: fullName,
    sortName: _sortableContributorName(name),
    normalizedName: stableId,
  );
}

/// Returns contributor display names joined with "; ".
/// e.g. "A. T. Jones; E. J. Waggoner"
String displayAuthorsFromContributors(List<LibraryItemContributor> contributors) {
  if (contributors.isEmpty) return '';
  final sorted = [...contributors]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return sorted.map((c) => c.contributor.displayName).join('; ');
}

/// Returns last names joined with " & ".
/// e.g. "Jones & Waggoner"
String shortAuthorsFromContributors(List<LibraryItemContributor> contributors) {
  if (contributors.isEmpty) return '';
  if (contributors.length == 1) {
    return contributors.first.contributor.displayName;
  }
  final sorted = [...contributors]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final lastNames = sorted.map((c) => _extractLastName(c.contributor.displayName)).toList();
  return lastNames.join(' & ');
}

/// Parses "A. T. Jones; E. J. Waggoner" into last-name tokens.
String shortAuthorsFromDisplayString(String authorField) {
  final names = authorField.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (names.isEmpty) return authorField;
  if (names.length == 1) return names.first;
  final lastNames = names.map(_extractLastName).toList();
  return lastNames.join(' & ');
}

String _extractLastName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.last;
}

String _normalizeContributorName(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String _sortableContributorName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length <= 1) return name.toLowerCase();
  // "A. T. Jones" → "jones a t"
  return '${parts.last.toLowerCase()} ${parts.take(parts.length - 1).join(' ').toLowerCase()}';
}
