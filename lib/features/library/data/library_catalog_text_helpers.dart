part of 'library_catalog_service.dart';

DateTime? _parseDate(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed);
}

String? _canonicalPeriodicalTitle(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('review') && lower.contains('herald')) {
    return 'The Review and Herald';
  }
  if (lower.contains('signs') && lower.contains('times')) {
    return 'The Signs of the Times';
  }
  return null;
}

const Map<int, String> _manuscriptReleasesVolumeTitles = <int, String>{
  1: 'Manuscript Releases, vol. 1 [Nos. 19-96]',
  2: 'Manuscript Releases, vol. 2 [Nos. 97-161]',
  3: 'Manuscript Releases, vol. 3 [Nos. 162-209]',
  4: 'Manuscript Releases, vol. 4 [Nos. 210-259]',
  5: 'Manuscript Releases, vol. 5 [Nos. 260-346]',
  6: 'Manuscript Releases, vol. 6 [Nos. 347-418]',
  7: 'Manuscript Releases, vol. 7 [Nos. 419-525]',
  8: 'Manuscript Releases, vol. 8 [Nos. 526-663]',
  9: 'Manuscript Releases, vol. 9 [Nos. 664-770]',
  10: 'Manuscript Releases, vol. 10 [Nos. 771-850]',
  11: 'Manuscript Releases, vol. 11 [Nos. 851-920]',
  12: 'Manuscript Releases, vol. 12 [Nos. 921-999]',
  13: 'Manuscript Releases, vol. 13 [Nos. 1000-1080]',
  14: 'Manuscript Releases, vol. 14 [Nos. 1081-1135]',
  15: 'Manuscript Releases, vol. 15 [Nos. 1136-1185]',
  16: 'Manuscript Releases, vol. 16 [Nos. 1186-1235]',
  17: 'Manuscript Releases, vol. 17 [Nos. 1236-1300]',
  18: 'Manuscript Releases, vol. 18 [Nos. 1301-1359]',
  19: 'Manuscript Releases, vol. 19 [Nos. 1360-1419]',
  20: 'Manuscript Releases, vol. 20 [Nos. 1420-1500]',
  21: 'Manuscript Releases, vol. 21 [Nos. 1501-1598]',
};

String? _manuscriptReleasesVolumeTitleFromCode(String code) {
  final normalizedCode = code.trim().toUpperCase();
  final match = RegExp(r'^(\d{1,2})MR$').firstMatch(normalizedCode);
  if (match == null) return null;

  final volume = int.tryParse(match.group(1) ?? '');
  if (volume == null) return null;

  return _manuscriptReleasesVolumeTitles[volume];
}

String _canonicalOfficialDownloadTitle({
  required String code,
  required String title,
}) {
  final canonicalTitle = _manuscriptReleasesVolumeTitleFromCode(code);
  if (canonicalTitle != null) {
    final normalizedTitle = _normalizedLibraryText(title);
    if (normalizedTitle.contains('manuscript releases')) {
      return title;
    }
    return canonicalTitle;
  }

  return title;
}

String? _canonicalManuscriptReleasesDisplayTitle({
  required String title,
  String? fileName,
  String? relativePath,
}) {
  final candidates = <String?>[title, fileName, relativePath];
  for (final candidate in candidates) {
    final normalized = _manuscriptReleasesVolumeCodeFromValue(candidate);
    if (normalized == null || normalized.isEmpty) continue;
    final canonicalTitle = _manuscriptReleasesVolumeTitleFromCode(normalized);
    if (canonicalTitle != null) {
      return canonicalTitle;
    }
  }

  return null;
}

String? _manuscriptReleasesVolumeCodeFromValue(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final basename = p.basenameWithoutExtension(trimmed.replaceAll('\\', '/'));
  final candidate = basename.replaceFirst(
    RegExp(r'^(?:[a-z]{2}|[A-Z]{2})[_-]'),
    '',
  );
  final compact = candidate.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
  if (compact.isEmpty) return null;
  return compact.toUpperCase();
}

bool _looksLikeFilename(String value) {
  final base = value.trim();
  if (base.isEmpty) {
    return true;
  }

  return base.contains('_') ||
      base.contains('-') ||
      RegExp(r'^\d{4}[_-]').hasMatch(base) ||
      (RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(base) && !base.contains(' '));
}

/// Returns true when [value] is a language-prefixed EGW code such as
/// "en GW" or "en 1TT" — the pattern produced when the EPUB filename stem
/// is used as the display title instead of the real EPUB dc:title.
bool _isLanguagePrefixedCodeTitle(String value) {
  return RegExp(r'^[a-z]{2}[\s_][A-Za-z0-9]+$').hasMatch(value.trim());
}

String _humanizeFileName(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) {
    return value.trim();
  }

  return cleaned
      .split(' ')
      .map((part) {
        if (part.length <= 2) {
          return part.toUpperCase();
        }
        if (RegExp(r'^\d+$').hasMatch(part)) {
          return part;
        }
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      })
      .join(' ');
}

String _normalizedLibraryText(String? value) {
  return (value?.trim() ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizedLibrarySearchText(String value) {
  return value
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('„', '"')
      .replaceAll('‟', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _cleanLibrarySearchText(String value) {
  return value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('„', '"')
      .replaceAll('‟', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .trim();
}

String compactLibrarySearchText(String? value) {
  return (value?.trim() ?? '').toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '',
  );
}

String _librarySearchInitials(String? value) {
  final words = _cleanLibrarySearchText(
    value ?? '',
  ).split(' ').where((part) => part.isNotEmpty).toList(growable: false);
  if (words.isEmpty) return '';

  final initials = StringBuffer();
  for (final word in words) {
    final first = word[0];
    if (RegExp(r'[a-z0-9]').hasMatch(first.toLowerCase())) {
      initials.write(first);
    }
  }
  return initials.toString().toLowerCase();
}

String libraryCatalogSearchTextForItem(LibraryCatalogItem item) {
  final normalizedRelativePath = item.relativePath.replaceAll('\\', '/');
  final candidates = <String?>[
    item.displayTitle,
    item.title,
    libraryUserFacingBookAbbreviation(
      title: item.displayTitle,
      fileName: item.fileName,
      relativePath: item.relativePath,
    ),
    item.displayAuthor,
    item.author,
    item.collectionName,
    item.fileName,
    p.basenameWithoutExtension(item.fileName),
    _stripLanguagePrefix(p.basenameWithoutExtension(item.fileName)),
    normalizedRelativePath,
    p.basenameWithoutExtension(normalizedRelativePath),
    _stripLanguagePrefix(p.basenameWithoutExtension(normalizedRelativePath)),
    item.id,
    item.sourceSite,
    item.sourceUrl,
    item.sourceType,
    item.fileHash,
    item.libraryRole,
    item.folderType,
    _librarySearchInitials(item.displayTitle),
    _librarySearchInitials(item.title),
  ];

  final buffer = StringBuffer();
  for (final candidate in candidates) {
    final normalized = compactLibrarySearchText(candidate);
    if (normalized.isEmpty) continue;
    buffer.write(normalized);
    buffer.write(' ');
  }
  return buffer.toString().trim();
}

String _stripLanguagePrefix(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  final stripped = trimmed.replaceFirst(
    RegExp(r'^[a-z]{2}[_-]', caseSensitive: false),
    '',
  );
  return stripped.isEmpty ? trimmed : stripped;
}
