part of 'library_screen.dart';

final RegExp _libraryDigitPattern = RegExp(r'\d');

List<LibraryCatalogNavigationItem> _filterNavigation(
  List<LibraryCatalogNavigationItem> items,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return items;
  return items.where((item) {
    final haystack = [
      item.label,
      item.href ?? '',
      item.anchorId ?? '',
      item.navType ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(normalized);
  }).toList();
}

String _stamp(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

int _compareNaturalSortKeys(
  List<({String text, int? number})> left,
  List<({String text, int? number})> right,
) {
  final length = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final leftToken = left[i];
    final rightToken = right[i];

    if (leftToken.number != null && rightToken.number != null) {
      final compare = leftToken.number!.compareTo(rightToken.number!);
      if (compare != 0) return compare;
      continue;
    }

    final compare = leftToken.text.compareTo(rightToken.text);
    if (compare != 0) return compare;
  }

  return left.length.compareTo(right.length);
}

List<({String text, int? number})> _naturalSortKey(String value) {
  if (value.isEmpty) return const [];
  final tokens = <({String text, int? number})>[];
  final buffer = StringBuffer();
  var currentIsDigit = _libraryDigitPattern.hasMatch(value[0]);

  void flush() {
    if (buffer.isEmpty) return;
    final token = buffer.toString().toLowerCase();
    tokens.add((text: token, number: int.tryParse(token)));
    buffer.clear();
  }

  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final isDigit = _libraryDigitPattern.hasMatch(char);
    if (isDigit != currentIsDigit) {
      flush();
      currentIsDigit = isDigit;
    }
    buffer.write(char);
  }
  flush();
  return tokens;
}

String _sortableTitle(String displayTitle) {
  final trimmed = displayTitle.trim();
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('the ') && trimmed.length > 4) {
    return trimmed.substring(4);
  }
  if (lower.startsWith('an ') && trimmed.length > 3) {
    return trimmed.substring(3);
  }
  if (lower.startsWith('a ') && trimmed.length > 2) {
    return trimmed.substring(2);
  }
  return trimmed;
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

String _normalizeLibraryText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _isLibraryMetadataHelpLabel(String value) {
  final normalized = _normalizeLibraryText(value);
  if (normalized.isEmpty) return false;

  return libraryIsMetadataSectionLabel(value);
}

bool _isLibraryChapterOneLabel(String value) {
  final normalized = _normalizeLibraryText(value);
  if (normalized.isEmpty) return false;

  const prefixes = <String>[
    'chapter 1',
    'chapter i',
    'chapter one',
    '1 ',
    '1.',
    '1)',
    'i ',
    'i.',
    'i)',
  ];
  for (final prefix in prefixes) {
    if (normalized == prefix.trim() || normalized.startsWith(prefix)) {
      return true;
    }
  }

  return false;
}

Color _librarySurfaceLowColor(ThemeData theme) {
  return theme.colorScheme.surfaceContainerLow;
}

Color _librarySurfaceHighColor(ThemeData theme) {
  return theme.colorScheme.surfaceContainerHigh;
}

Color _librarySurfaceHighestColor(ThemeData theme) {
  return theme.colorScheme.surfaceContainerHighest;
}

Color _libraryOutlineColor(ThemeData theme) {
  return theme.colorScheme.outlineVariant;
}

Color _librarySelectedColor(ThemeData theme) {
  return theme.colorScheme.primary.withValues(alpha: 0.14);
}

Color _libraryFallbackCoverColor(ThemeData theme) {
  return Color.alphaBlend(
    theme.colorScheme.primary.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.16 : 0.12,
    ),
    _librarySurfaceHighColor(theme),
  );
}

ButtonStyle _libraryTonalButtonStyle(BuildContext context) {
  final theme = Theme.of(context);
  return FilledButton.styleFrom(
    foregroundColor: theme.colorScheme.onSurface,
    backgroundColor: _librarySurfaceHighColor(theme),
    disabledForegroundColor: theme.colorScheme.onSurface.withValues(
      alpha: 0.45,
    ),
    disabledBackgroundColor: _librarySurfaceHighColor(
      theme,
    ).withValues(alpha: 0.45),
    side: BorderSide(color: _libraryOutlineColor(theme)),
  );
}
