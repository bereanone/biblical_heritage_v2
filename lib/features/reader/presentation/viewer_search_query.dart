import '../../search/search_highlight_helper.dart';

class ViewerSearchQuery {
  const ViewerSearchQuery({required this.whereClause, required this.whereArgs});

  final String whereClause;
  final List<Object?> whereArgs;
}

ViewerSearchQuery buildViewerSearchQuery(
  String query, {
  String section = 'All',
  int? bookNumber,
}) {
  query = _normalizeSearchInput(query);
  query = query.replaceAll('(', ' ( ').replaceAll(')', ' ) ');
  final regex = RegExp(r'"[^"]+"|\S+');
  final tokens = regex.allMatches(query).map((m) => m.group(0)!).toList();

  const normalizedBase = '''
LOWER(
  REPLACE(
    REPLACE(
      REPLACE(
        REPLACE(
          REPLACE(
            REPLACE(
              REPLACE(
                REPLACE(
                  REPLACE(' ' || plain_text || ' ', CHAR(10), ' '),
                  CHAR(13), ' '
                ),
                ',', ' '
              ),
              '.', ' '
            ),
            ';', ' '
          ),
          ':', ' '
        ),
        '?', ' '
      ),
      '!', ' '
    ),
    '"', ' '
  )
)
''';

  String collapseSpaces(String expr) =>
      "REPLACE(REPLACE(REPLACE($expr, '  ', ' '), '  ', ' '), '  ', ' ')";

  final normalizedExpr = collapseSpaces(
    "REPLACE(REPLACE($normalizedBase, '''', ' '), '’', ' ')",
  );

  String normalizeToken(String token) {
    var t = token.toLowerCase().trim();
    t = _normalizeSearchInput(t);
    t = t
        .replaceAll("'", ' ')
        .replaceAll('’', ' ')
        .replaceAll('-', ' ')
        .replaceAll('/', ' ')
        .replaceAll('[', ' ')
        .replaceAll(']', ' ')
        .replaceAll(',', ' ')
        .replaceAll('.', ' ')
        .replaceAll(';', ' ')
        .replaceAll(':', ' ')
        .replaceAll('?', ' ')
        .replaceAll('!', ' ')
        .replaceAll('"', ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  final sqlTokens = <String>[];
  final args = <Object?>[];
  var needsAnd = false;
  var openParens = 0;

  for (final token in tokens) {
    final upper = token.toUpperCase();
    final isLogicalOperator =
        token == upper && const ['AND', 'OR', 'NOT'].contains(upper);

    if (token == '(') {
      if (needsAnd) {
        sqlTokens.add('AND');
      }
      sqlTokens.add('(');
      openParens += 1;
      needsAnd = false;
      continue;
    }

    if (token == ')') {
      if (openParens > 0 && needsAnd) {
        sqlTokens.add(')');
        openParens -= 1;
        needsAnd = true;
      }
      continue;
    }

    if (isLogicalOperator && (token == 'AND' || token == 'OR')) {
      if (needsAnd) {
        sqlTokens.add(token);
        needsAnd = false;
      }
      continue;
    }

    if (isLogicalOperator && token == 'NOT') {
      if (needsAnd) {
        sqlTokens.add('AND');
      }
      sqlTokens.add('NOT');
      needsAnd = false;
      continue;
    }

    if (needsAnd && !isLogicalOperator) {
      sqlTokens.add('AND');
    }

    final cleaned = token.replaceAll('"', '').trim();
    if (cleaned.isEmpty) continue;

    final normalizedToken = normalizeToken(cleaned);
    if (normalizedToken.isEmpty) continue;

    final userPattern = normalizedToken.replaceAll('*', '%').trim();
    final pattern = '% $userPattern %';
    sqlTokens.add('$normalizedExpr LIKE ?');
    args.add(pattern);
    needsAnd = true;
  }

  while (sqlTokens.isNotEmpty &&
      const ['AND', 'OR', 'NOT'].contains(sqlTokens.last)) {
    sqlTokens.removeLast();
  }

  while (openParens > 0 && needsAnd) {
    sqlTokens.add(')');
    openParens -= 1;
  }

  final textClause = sqlTokens.join(' ');
  final constraints = <String>[];
  final constraintArgs = <Object?>[];

  if (bookNumber != null) {
    constraints.add('book_number = ?');
    constraintArgs.add(bookNumber);
  } else {
    final range = viewerSectionBookRange(section);
    if (range != null) {
      constraints.add('book_number BETWEEN ? AND ?');
      constraintArgs.addAll([range.$1, range.$2]);
    }
  }

  if (textClause.isNotEmpty) {
    constraints.add('($textClause)');
  }

  final clause = constraints.join(' AND ');
  return ViewerSearchQuery(
    whereClause: clause,
    whereArgs: <Object?>[...constraintArgs, ...args],
  );
}

List<String> extractViewerSearchHighlightTerms(String query) {
  return extractSearchHighlightTerms(query, booleanSyntax: true);
}

String _normalizeSearchInput(String value) {
  return value
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('„', '"')
      .replaceAll('‟', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'");
}

(int, int)? viewerSectionBookRange(String section) {
  switch (section) {
    case 'Old Testament':
      return (1, 39);
    case 'Pentateuch':
      return (1, 5);
    case 'History':
      return (6, 17);
    case 'Poetry':
      return (18, 22);
    case 'Major Prophets':
      return (23, 27);
    case 'Minor Prophets':
      return (28, 39);
    case 'New Testament':
      return (40, 66);
    case 'Gospels':
      return (40, 43);
    case 'Acts':
      return (44, 44);
    case 'Pauline Epistles':
      return (45, 58);
    case 'General Epistles':
      return (59, 65);
    case 'Revelation':
      return (66, 66);
    default:
      return null;
  }
}
