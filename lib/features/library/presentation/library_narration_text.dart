/// Speech-only transformations. Reader paragraphs and reference labels stay intact.
class LibrarySpeechSpan {
  const LibrarySpeechSpan(this.start, this.end, this.spoken);
  final int start;
  final int end;
  final String spoken;
}

String _numberWords(int n) {
  const small = [
    '',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  const tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];
  if (n < 20) return small[n];
  if (n < 100) {
    return '${tens[n ~/ 10]}${n % 10 == 0 ? '' : '-${small[n % 10]}'}';
  }
  return 'one hundred${n == 100 ? '' : ' ${_numberWords(n - 100)}'}';
}

final _booksPattern =
    (_bookAliases.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
        .map((s) => RegExp.escape(s).replaceAll(' ', r'\s+'))
        .join('|');
final _citationStart = RegExp(
  '(?<!\\w)($_booksPattern)\\s*(\\d+)\\s*:\\s*',
  caseSensitive: false,
);
final _parenthesizedCitationStart = RegExp(
  '(?<!\\w)($_booksPattern)\\s+\\(\\s*(\\d+)\\s*:\\s*',
  caseSensitive: false,
);
final _singleChapterBooks = {'Obadiah', 'Philemon', '2 John', '3 John', 'Jude'};
final _singleChapterPattern = _bookAliases.entries
    .where((entry) => _singleChapterBooks.contains(entry.value))
    .map((entry) => RegExp.escape(entry.key).replaceAll(' ', r'\s+'))
    .join('|');
final _singleChapterCitation = RegExp(
  '(?<!\\w)($_singleChapterPattern)\\s+(?=\\d)',
  caseSensitive: false,
);
final _citationFollow = RegExp(
  '(?:\\s*;\\s*|\\s*,?\\s+and\\s+)(?:($_booksPattern)\\s+)?(\\d+)\\s*:\\s*',
  caseSensitive: false,
);
final _range = RegExp(r'(\d+)(?:\s*[-–—]\s*(\d+))?');
final _listSeparator = RegExp(
  r'\s*(?:,\s*(?:and\s+)?|and\s+)',
  caseSensitive: false,
);
final _pageMarker = RegExp(r'\[\s*\d+\s*\]');
// Require a decimal paragraph number, so prose and Bible chapter references survive.
final _referenceCode = RegExp(
  r'(?<![\w])(?:SC|WOR)\s*\d+\.\d+[a-z]?(?![\w])',
  caseSensitive: false,
);

({List<List<int>> values, int end})? _verses(String text, int start) {
  var pos = start;
  final values = <List<int>>[];
  while (true) {
    final m = _range.matchAsPrefix(text, pos);
    if (m == null) return null;
    final nums = [int.parse(m[1]!), if (m[2] != null) int.parse(m[2]!)];
    if (nums.any((n) => n < 1 || n > 199) ||
        (nums.length == 2 && nums[1] < nums[0])) {
      return null;
    }
    values.add(nums);
    pos = m.end;
    final comma = _listSeparator.matchAsPrefix(text, pos);
    if (comma == null) break;
    final next = comma.end;
    if (_citationStart.matchAsPrefix(text, next) != null ||
        RegExp(r'\d+\s*:\s*\d').matchAsPrefix(text, next) != null ||
        _range.matchAsPrefix(text, next) == null) {
      break;
    }
    pos = next;
  }
  if (pos < text.length &&
      RegExp(r'[\w]|:\s*\d|-|[–—](?=\s*(?:$|\d))').matchAsPrefix(text, pos) != null) {
    return null;
  }
  return (values: values, end: pos);
}

String _phrase(String? raw, int chapter, List<List<int>> values) {
  var book = raw == null
      ? ''
      : _bookAliases[raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')]!;
  if (book == 'Chapter') book = '';
  book = book.replaceFirstMapped(
    RegExp(r'^([123]) '),
    (m) => '${['First', 'Second', 'Third'][int.parse(m[1]!) - 1]} ',
  );
  final kind = values.length > 1 || values.first.length > 1
      ? 'verses'
      : 'verse';
  final verses = values
      .map((v) => v.map(_numberWords).join(' through '))
      .join(' and ');
  return '${book.isEmpty ? '' : '$book '}chapter ${_numberWords(chapter)} $kind $verses';
}

List<LibrarySpeechSpan> librarySpeechSpans(String text) {
  final spans = <LibrarySpeechSpan>[];
  var consumed = 0;
  for (final m in _citationStart.allMatches(text)) {
    if (m.start < consumed) continue;
    var chapter = int.parse(m[2]!);
    var parsed = _verses(text, m.end);
    if (parsed == null || chapter < 1 || chapter > 199) continue;
    var end = parsed.end;
    var spoken = _phrase(m[1], chapter, parsed.values);
    while (true) {
      final next = _citationFollow.matchAsPrefix(text, end);
      if (next == null) break;
      chapter = int.parse(next[2]!);
      parsed = _verses(text, next.end);
      if (parsed == null || chapter < 1 || chapter > 199) break;
      end = parsed.end;
      spoken += ' and ${_phrase(next[1], chapter, parsed.values)}';
    }
    spans.add(LibrarySpeechSpan(m.start, end, spoken));
    consumed = end;
  }
  // Printed parentheses separate the book name from its chapter, as in
  // Habakkuk (2:4). Keep the original source offsets and consume the closing
  // parenthesis only after validating the entire reference.
  for (final m in _parenthesizedCitationStart.allMatches(text)) {
    final chapter = int.parse(m[2]!);
    final parsed = _verses(text, m.end);
    if (parsed == null || chapter < 1 || chapter > 199) continue;
    final closing = RegExp(r'\s*\)').matchAsPrefix(text, parsed.end);
    if (closing == null || spans.any((s) => m.start < s.end && closing.end > s.start)) continue;
    spans.add(LibrarySpeechSpan(m.start, closing.end, _phrase(m[1], chapter, parsed.values)));
  }
  // Single-chapter books often print verse numbers without a colon.
  for (final m in _singleChapterCitation.allMatches(text)) {
    final parsed = _verses(text, m.end);
    if (parsed == null ||
        spans.any((s) => m.start < s.end && parsed.end > s.start)) {
      continue;
    }
    spans.add(
      LibrarySpeechSpan(m.start, parsed.end, _phrase(m[1], 1, parsed.values)),
    );
  }
  // A terminal colon can introduce a quotation after a verse list. It is
  // only a new chapter when another number actually follows that colon.
  for (final m in RegExp(r'\bverses?\s*,?\s*(?=\d)',
      caseSensitive: false).allMatches(text)) {
    final parsed = _verses(text, m.end);
    if (parsed == null || spans.any((s) => m.start < s.end && parsed.end > s.start)) continue;
    final values = parsed.values;
    final kind = values.length > 1 || values.first.length > 1 ? 'verses' : 'verse';
    final words = values.map((v) => v.map(_numberWords).join(' through ')).join(' and ');
    spans.add(LibrarySpeechSpan(m.start, parsed.end, '$kind $words'));
  }
  for (final m in RegExp(r'\bchapter\s+(\d+)(?![\d]|\s*:)',
      caseSensitive: false).allMatches(text)) {
    final n = int.parse(m[1]!);
    if (n < 1 || n > 199 || spans.any((s) => m.start < s.end && m.end > s.start)) continue;
    spans.add(LibrarySpeechSpan(m.start, m.end, 'chapter ${_numberWords(n)}'));
  }
  for (final pattern in [_pageMarker, _referenceCode]) {
    for (final m in pattern.allMatches(text)) {
      if (!spans.any((s) => m.start < s.end && m.end > s.start)) {
        spans.add(LibrarySpeechSpan(m.start, m.end, ''));
      }
    }
  }
  for (final span in _dateSpeechSpans(text)) {
    if (!spans.any((s) => span.start < s.end && span.end > s.start)) {
      spans.add(span);
    }
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  return spans;
}

const _months = <String, String>{
  'jan': 'January', 'january': 'January',
  'feb': 'February', 'february': 'February',
  'mar': 'March', 'march': 'March',
  'apr': 'April', 'april': 'April', 'may': 'May',
  'jun': 'June', 'june': 'June', 'jul': 'July', 'july': 'July',
  'aug': 'August', 'august': 'August',
  'sep': 'September', 'sept': 'September', 'september': 'September',
  'oct': 'October', 'october': 'October',
  'nov': 'November', 'november': 'November',
  'dec': 'December', 'december': 'December',
};
const _dayOrdinals = [
  '', 'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh',
  'eighth', 'ninth', 'tenth', 'eleventh', 'twelfth', 'thirteenth',
  'fourteenth', 'fifteenth', 'sixteenth', 'seventeenth', 'eighteenth',
  'nineteenth', 'twentieth', 'twenty-first', 'twenty-second',
  'twenty-third', 'twenty-fourth', 'twenty-fifth', 'twenty-sixth',
  'twenty-seventh', 'twenty-eighth', 'twenty-ninth', 'thirtieth',
  'thirty-first',
];
final _monthPattern = (_months.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length)))
    .join('|');
final _monthDay = RegExp(
  '(?<![\\w])($_monthPattern)\\.?\\s*(\\d{1,2})(?:st|nd|rd|th)?'
  '(?![\\w])(?:(?:,\\s*|\\s+)((?:1[6-9]|20)\\d{2})(?![\\w]))?',
  caseSensitive: false,
);

String _yearWords(int year) {
  final century = year ~/ 100;
  final rest = year % 100;
  if (century == 20 && rest < 10) {
    return 'two thousand${rest == 0 ? '' : ' ${_numberWords(rest)}'}';
  }
  return '${_numberWords(century)} ${rest == 0 ? 'hundred' : rest < 10 ? 'oh ${_numberWords(rest)}' : _numberWords(rest)}';
}

Iterable<LibrarySpeechSpan> _dateSpeechSpans(String text) sync* {
  for (final m in _monthDay.allMatches(text)) {
    final month = _months[m[1]!.toLowerCase()]!;
    final day = int.parse(m[2]!);
    final monthNumber = const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ].indexOf(month) + 1;
    final year = m[3] == null ? null : int.parse(m[3]!);
    // Yearless dates in printed lists (July 18, July 25, August 1, 1899)
    // retain the year exactly where printed. Invalid dates are left intact.
    final maxDay = DateTime.utc(year ?? 2000, monthNumber + 1, 0).day;
    if (day < 1 || day > maxDay) continue;
    yield LibrarySpeechSpan(m.start, m.end,
      '$month ${_dayOrdinals[day]}${year == null ? '' : ', ${_yearWords(year)}'}');
  }
}

String prepareLibraryNarrationText(String text) {
  final result = StringBuffer();
  var offset = 0;
  for (final span in librarySpeechSpans(text)) {
    result.write(text.substring(offset, span.start));
    result.write(span.spoken);
    offset = span.end;
  }
  result.write(text.substring(offset));
  return result
      .toString()
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' +(?=\r?\n)'), '')
      .replaceAllMapped(RegExp(r' +([,.;:!?])'), (m) => m[1]!)
      .trim();
}

const _bookAliases = <String, String>{
  '1 chr': '1 Chronicles',
  '1 chr.': '1 Chronicles',
  '1 chron': '1 Chronicles',
  '1 chron.': '1 Chronicles',
  '1 kgs': '1 Kings',
  '1 kgs.': '1 Kings',
  '1 sam': '1 Samuel',
  '1 sam.': '1 Samuel',
  '1 thess': '1 Thessalonians',
  '1 thess.': '1 Thessalonians',
  '1 tim': '1 Timothy',
  '1 tim.': '1 Timothy',
  '2 chr': '2 Chronicles',
  '2 chr.': '2 Chronicles',
  '2 chron': '2 Chronicles',
  '2 chron.': '2 Chronicles',
  '2 kgs': '2 Kings',
  '2 kgs.': '2 Kings',
  '2 sam': '2 Samuel',
  '2 sam.': '2 Samuel',
  '2 thess': '2 Thessalonians',
  '2 thess.': '2 Thessalonians',
  '2 tim': '2 Timothy',
  '2 tim.': '2 Timothy',
  'col': 'Colossians',
  'col.': 'Colossians',
  'dan': 'Daniel',
  'dan.': 'Daniel',
  'deut': 'Deuteronomy',
  'deut.': 'Deuteronomy',
  'eccl': 'Ecclesiastes',
  'eccl.': 'Ecclesiastes',
  'esth': 'Esther',
  'esth.': 'Esther',
  'exod': 'Exodus',
  'exod.': 'Exodus',
  'eze': 'Ezekiel',
  'eze.': 'Ezekiel',
  'ezek': 'Ezekiel',
  'ezek.': 'Ezekiel',
  'gal': 'Galatians',
  'gal.': 'Galatians',
  'hab': 'Habakkuk',
  'hab.': 'Habakkuk',
  'hag': 'Haggai',
  'hag.': 'Haggai',
  'heb': 'Hebrews',
  'heb.': 'Hebrews',
  'hos': 'Hosea',
  'hos.': 'Hosea',
  'isa': 'Isaiah',
  'isa.': 'Isaiah',
  'jer': 'Jeremiah',
  'jer.': 'Jeremiah',
  'jn': 'John',
  'jn.': 'John',
  'jno': 'John',
  'jno.': 'John',
  'joel.': 'Joel',
  'joh': 'John',
  'joh.': 'John',
  'jon': 'Jonah',
  'jon.': 'Jonah',
  'josh': 'Joshua',
  'josh.': 'Joshua',
  'judg': 'Judges',
  'judg.': 'Judges',
  'lam': 'Lamentations',
  'lam.': 'Lamentations',
  'lev': 'Leviticus',
  'lev.': 'Leviticus',
  'lk': 'Luke',
  'lk.': 'Luke',
  'mal': 'Malachi',
  'mal.': 'Malachi',
  'mic': 'Micah',
  'mic.': 'Micah',
  'mk': 'Mark',
  'mk.': 'Mark',
  'nah': 'Nahum',
  'nah.': 'Nahum',
  'num': 'Numbers',
  'num.': 'Numbers',
  'obad': 'Obadiah',
  'obad.': 'Obadiah',
  'phil': 'Philippians',
  'phil.': 'Philippians',
  'philem': 'Philemon',
  'philem.': 'Philemon',
  'pr': 'Proverbs',
  'pr.': 'Proverbs',
  'prov': 'Proverbs',
  'prov.': 'Proverbs',
  'psa': 'Psalms',
  'psa.': 'Psalms',
  'song': 'Song of Solomon',
  'zech': 'Zechariah',
  'zech.': 'Zechariah',
  'zeph': 'Zephaniah',
  'zeph.': 'Zephaniah',

  'rom': 'Romans',
  'rom.': 'Romans',
  'genesis': 'Genesis',
  'gen': 'Genesis',
  'gen.': 'Genesis',
  'exodus': 'Exodus',
  'ex': 'Exodus',
  'ex.': 'Exodus',
  'matthew': 'Matthew',
  'matt': 'Matthew',
  'matt.': 'Matthew',
  'revelation': 'Revelation',
  'rev': 'Revelation',
  'rev.': 'Revelation',
  'psalms': 'Psalms',
  'ps': 'Psalms',
  'ps.': 'Psalms',
  '1 corinthians': '1 Corinthians',
  '1 cor': '1 Corinthians',
  '1 cor.': '1 Corinthians',
  '2 corinthians': '2 Corinthians',
  '2 cor': '2 Corinthians',
  '2 cor.': '2 Corinthians',
  '1 peter': '1 Peter',
  '1 pet': '1 Peter',
  '1 pet.': '1 Peter',
  '2 peter': '2 Peter',
  '2 pet': '2 Peter',
  '2 pet.': '2 Peter',
  '1 john': '1 John',
  '1 jn': '1 John',
  '1 jn.': '1 John',
  '2 john': '2 John',
  '2 jn': '2 John',
  '2 jn.': '2 John',
  '3 john': '3 John',
  '3 jn': '3 John',
  '3 jn.': '3 John',
  'james': 'James',
  'jas': 'James',
  'jas.': 'James',
  'jude': 'Jude',
  'jud': 'Jude',
  'jud.': 'Jude',
  'acts': 'Acts',
  'romans': 'Romans',
  '1 chronicles': '1 Chronicles',
  '1 kings': '1 Kings',
  '1 samuel': '1 Samuel',
  '1 thessalonians': '1 Thessalonians',
  '1 timothy': '1 Timothy',
  '2 chronicles': '2 Chronicles',
  '2 kings': '2 Kings',
  '2 samuel': '2 Samuel',
  '2 thessalonians': '2 Thessalonians',
  '2 timothy': '2 Timothy',
  'amos': 'Amos',
  'colossians': 'Colossians',
  'daniel': 'Daniel',
  'deuteronomy': 'Deuteronomy',
  'ecclesiastes': 'Ecclesiastes',
  'ephesians': 'Ephesians',
  'eph': 'Ephesians',
  'eph.': 'Ephesians',
  'esther': 'Esther',
  'ezekiel': 'Ezekiel',
  'ezra': 'Ezra',
  'galatians': 'Galatians',
  'habakkuk': 'Habakkuk',
  'haggai': 'Haggai',
  'hebrews': 'Hebrews',
  'hosea': 'Hosea',
  'isaiah': 'Isaiah',
  'jeremiah': 'Jeremiah',
  'job': 'Job',
  'joel': 'Joel',
  'john': 'John',
  'jonah': 'Jonah',
  'joshua': 'Joshua',
  'judges': 'Judges',
  'lamentations': 'Lamentations',
  'leviticus': 'Leviticus',
  'luke': 'Luke',
  'malachi': 'Malachi',
  'mark': 'Mark',
  'micah': 'Micah',
  'nahum': 'Nahum',
  'nehemiah': 'Nehemiah',
  'numbers': 'Numbers',
  'obadiah': 'Obadiah',
  'philemon': 'Philemon',
  'philippians': 'Philippians',
  'proverbs': 'Proverbs',
  'ruth': 'Ruth',
  'song of solomon': 'Song of Solomon',
  'titus': 'Titus',
  'zechariah': 'Zechariah',
  'zephaniah': 'Zephaniah',
  'psalm': 'Psalms',
  'psalm.': 'Psalms',
  'chapter': 'Chapter',
};
