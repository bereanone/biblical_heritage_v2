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
  return (value?.trim() ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _librarySearchInitials(String? value) {
  final words = _cleanLibrarySearchText(value ?? '')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
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
