part of 'library_screen.dart';

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

String _fallbackSpineLabel(String title) {
  final words = title
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .split(' ')
      .where((part) => part.isNotEmpty)
      .take(4)
      .toList();
  if (words.isEmpty) return 'Book';
  return words.join('\n');
}

String _stamp(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

int _naturalCompare(String a, String b) {
  final left = _naturalSortTokens(a);
  final right = _naturalSortTokens(b);
  final length = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final leftToken = left[i];
    final rightToken = right[i];
    final leftIsNumber = int.tryParse(leftToken) != null;
    final rightIsNumber = int.tryParse(rightToken) != null;

    if (leftIsNumber && rightIsNumber) {
      final compare = int.parse(leftToken).compareTo(int.parse(rightToken));
      if (compare != 0) return compare;
      continue;
    }

    final compare = leftToken.toLowerCase().compareTo(rightToken.toLowerCase());
    if (compare != 0) return compare;
  }

  return left.length.compareTo(right.length);
}

List<String> _naturalSortTokens(String value) {
  if (value.isEmpty) return const [];
  final tokens = <String>[];
  final buffer = StringBuffer();
  var currentIsDigit = RegExp(r'\d').hasMatch(value[0]);

  void flush() {
    if (buffer.isEmpty) return;
    tokens.add(buffer.toString());
    buffer.clear();
  }

  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final isDigit = RegExp(r'\d').hasMatch(char);
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
  if (lower.startsWith('the ') && trimmed.length > 4) return trimmed.substring(4);
  if (lower.startsWith('an ') && trimmed.length > 3) return trimmed.substring(3);
  if (lower.startsWith('a ') && trimmed.length > 2) return trimmed.substring(2);
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

  const exactMatches = <String>{
    'cover',
    'title page',
    'titlepage',
    'table of contents',
    'contents',
    'toc',
    'nav',
    'foreword',
    'preface',
    'about this book',
    'about book',
    'aboutbook',
    'about the author',
    'information about this book',
    'overview',
    'further links',
    'further information',
    'end user license agreement',
    'copyright',
    'publisher note',
    'publisher',
    'editor note',
    'editorial note',
    'editorial',
    'publication information',
    'source credits',
    'dedication',
    'acknowledgments',
    'acknowledgements',
    'index',
    'bibliography',
    'ellen g white',
    'ellen white',
  };
  if (exactMatches.contains(normalized)) return true;

  const prefixes = <String>[
    'cover ',
    'title page',
    'titlepage',
    'table of contents',
    'contents',
    'toc',
    'nav',
    'foreword',
    'preface',
    'about this book',
    'about book',
    'aboutbook',
    'about the author',
    'information about this book',
    'overview',
    'further links',
    'further information',
    'end user license agreement',
    'copyright',
    'publisher note',
    'publisher',
    'editor note',
    'editorial note',
    'editorial',
    'publication information',
    'source credits',
    'dedication',
    'acknowledgments',
    'acknowledgements',
    'index',
    'bibliography',
    'ellen g white',
    'ellen white',
  ];
  for (final prefix in prefixes) {
    if (normalized.startsWith(prefix)) return true;
  }

  return false;
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
