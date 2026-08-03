import 'package:flutter/foundation.dart';

import 'commentary_research_models.dart';

const bool _debugCommentaryResearchLogs = false;

class CommentaryResearchFilters {
  static List<CommentaryResearchMatchItem> prepareResearchMatches(
    List<CommentaryResearchMatchItem> rawMatches, {
    required int bookId,
    required int chapter,
    required int verse,
  }) {
    if (_debugCommentaryResearchLogs) {
      debugPrint('[CommentaryResearch] research raw=${rawMatches.length}');
    }
    final exactCount = rawMatches
        .where(
          (match) =>
              match.bookId == bookId &&
              match.chapter == chapter &&
              match.verseStart == verse &&
              match.verseEnd == verse,
        )
        .length;
    final rangeCount = rawMatches
        .where(
          (match) =>
              match.bookId == bookId &&
              match.chapter == chapter &&
              verse > 0 &&
              match.verseStart <= verse &&
              match.verseEnd >= verse &&
              !(match.verseStart == verse && match.verseEnd == verse),
        )
        .length;
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] research exact=$exactCount range=$rangeCount '
        'subjectExpansion=0',
      );
    }

    final sourceEligible = rawMatches
        .where(isResearchEligibleSource)
        .toList(growable: false);
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] research sourceEligible=${sourceEligible.length}',
      );
    }

    final frontMatterFiltered = sourceEligible
        .where((match) => !isFrontMatterOrEditorialHit(match))
        .toList(growable: false);
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] research frontMatterFiltered=${frontMatterFiltered.length}',
      );
    }

    final bodyFiltered = frontMatterFiltered
        .where((match) => isUsableResearchParagraph(match.anchor ?? ''))
        .toList(growable: false);
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] research bodyFiltered=${bodyFiltered.length}',
      );
      debugPrint(
        '[CommentaryResearch] research truncatedExcluded=${frontMatterFiltered.length - bodyFiltered.length}',
      );
    }

    final precisionFiltered = bodyFiltered
        .where(
          (match) => isResearchPrecisionUseful(
            match,
            bookId: bookId,
            chapter: chapter,
            verse: verse,
          ),
        )
        .toList(growable: false);
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] research precisionFiltered=${precisionFiltered.length}',
      );
      debugPrint(
        '[CommentaryResearch] research lowRelevanceExcluded=${bodyFiltered.length - precisionFiltered.length}',
      );
    }

    final grouped = <String, CommentaryResearchMatchItem>{};
    for (final match in precisionFiltered) {
      final key = researchParagraphKey(match);
      final current = grouped[key];
      if (current == null ||
          compareResearchPriority(
                match,
                current,
                bookId: bookId,
                chapter: chapter,
                verse: verse,
              ) <
              0) {
        grouped[key] = match;
      }
    }

    final deduped = grouped.values.toList(growable: false)
      ..sort(
        (a, b) => compareResearchPriority(
          a,
          b,
          bookId: bookId,
          chapter: chapter,
          verse: verse,
        ),
      );
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] research duplicatesRemoved=${precisionFiltered.length - deduped.length}',
      );
      debugPrint(
        '[CommentaryResearch] research deduped=${deduped.length} '
        'titles=${deduped.take(3).map((m) => m.itemTitle).join(' | ')}',
      );
    }
    return deduped;
  }

  static List<CommentaryResearchMatchItem> dedupeMatches(
    List<CommentaryResearchMatchItem> matches,
  ) {
    final grouped = <String, CommentaryResearchMatchItem>{};
    for (final match in matches) {
      final text = commentaryDisplayText(match);
      if (text.isEmpty) continue;
      final key = [
        _logicalBookIdentity(match),
        match.bookId.toString(),
        match.chapter.toString(),
        match.verseStart.toString(),
        match.verseEnd.toString(),
        _canonicalCommentaryText(text),
      ].join('::');
      final current = grouped[key];
      if (current == null || _compareCommentaryQuality(match, current) > 0) {
        grouped[key] = match;
      }
    }
    final deduped = grouped.values.toList(growable: false)
      ..sort(compareCommentaryPriority);
    return deduped;
  }

  static List<CommentaryResearchMatchItem> filterCommentaryMatches(
    List<CommentaryResearchMatchItem> matches,
    int selectedChapter,
  ) {
    final filtered = <CommentaryResearchMatchItem>[];
    var rejectedChapter = 0;
    var rejectedTruncated = 0;
    var rejectedEmpty = 0;
    for (final match in matches) {
      final text = commentaryDisplayText(match);
      if (text.isEmpty) {
        rejectedEmpty += 1;
        continue;
      }
      if (!isUsableCommentaryParagraph(text)) {
        rejectedTruncated += 1;
        continue;
      }
      if (isFrontMatterOrEditorialHit(match)) {
        rejectedTruncated += 1;
        continue;
      }
      if (match.chapter != selectedChapter) {
        rejectedChapter += 1;
        continue;
      }
      final anchor = normalizeForSearch(text);
      final chapterMatch = RegExp(r'\bchapter\s+(\d+)\b').firstMatch(anchor);
      final anchorChapter = int.tryParse(chapterMatch?.group(1) ?? '');
      if (chapterMatch != null &&
          chapterMatch.start < 120 &&
          anchorChapter != null &&
          anchorChapter != selectedChapter) {
        rejectedChapter += 1;
        continue;
      }
      filtered.add(match);
    }
    filtered.sort(compareCommentaryPriority);
    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] commentary chapterRejected=$rejectedChapter '
        'truncatedRejected=$rejectedTruncated '
        'emptyRejected=$rejectedEmpty '
        'final=${filtered.length}',
      );
    }
    return filtered;
  }

  static bool isResearchEligibleSource(CommentaryResearchMatchItem match) {
    final path = normalizeForSearch(match.relativePath);
    if (path.contains('/research/') ||
        path.contains('/research library/') ||
        path.startsWith('research/') ||
        path.startsWith('research library/') ||
        path.contains('/epubs/research/')) {
      return true;
    }
    final sourceText = normalizeForSearch(
      '${match.itemTitle} ${match.fileName} ${match.relativePath}',
    );
    for (final needle in _researchEligibleNeedles) {
      if (sourceText.contains(needle)) return true;
    }
    return false;
  }

  static bool isFrontMatterOrEditorialHit(CommentaryResearchMatchItem match) {
    final text = normalizeForSearch(
      '${match.itemTitle} ${match.fileName} ${match.relativePath} '
      '${match.originalReferenceText} ${commentaryDisplayText(match)}',
    );
    if (_looksLikeEditorialOpening(text)) return true;
    for (final needle in _frontMatterNeedles) {
      if (text.contains(needle)) return true;
    }
    for (final needle in _editorialNeedles) {
      if (text.contains(needle)) return true;
    }
    return false;
  }

  static bool isUsableResearchParagraph(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('...') || trimmed.startsWith('…')) return false;
    if (trimmed.endsWith('...') || trimmed.endsWith('…')) return false;
    if (trimmed.length < 80) return false;
    if (trimmed.length >= 220 &&
        !RegExp(r"""[.!?]["')\]]?\s*$""").hasMatch(trimmed)) {
      return false;
    }
    return true;
  }

  static bool isUsableCommentaryParagraph(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('...') || trimmed.startsWith('…')) return false;
    if (trimmed.endsWith('...') || trimmed.endsWith('…')) return false;
    if (trimmed.length < 80) return false;
    var terminal = trimmed;
    while (terminal.isNotEmpty &&
        <String>{
          '"',
          "'",
          ')',
          ']',
          '}',
        }.contains(terminal[terminal.length - 1])) {
      terminal = terminal.substring(0, terminal.length - 1).trimRight();
    }
    if (!RegExp(r'[.!?]$').hasMatch(terminal)) return false;
    return true;
  }

  static String commentaryDisplayText(CommentaryResearchMatchItem match) {
    final raw = match.fullParagraph ?? match.anchor ?? '';
    return _cleanCommentaryParagraphText(raw, match.itemTitle);
  }

  static bool isResearchPrecisionUseful(
    CommentaryResearchMatchItem match, {
    required int bookId,
    required int chapter,
    required int verse,
  }) {
    if (match.bookId != bookId || match.chapter != chapter) return false;
    if (match.verseStart <= 0 || match.verseEnd <= 0) return false;
    if (verse <= 0) return true;
    return true;
  }

  static int compareResearchPriority(
    CommentaryResearchMatchItem a,
    CommentaryResearchMatchItem b, {
    required int bookId,
    required int chapter,
    required int verse,
  }) {
    final aPriority = _researchPriority(
      a,
      bookId: bookId,
      chapter: chapter,
      verse: verse,
    );
    final bPriority = _researchPriority(
      b,
      bookId: bookId,
      chapter: chapter,
      verse: verse,
    );
    final priorityCmp = aPriority.compareTo(bPriority);
    if (priorityCmp != 0) return priorityCmp;
    final titleCmp = a.itemTitle.toLowerCase().compareTo(
      b.itemTitle.toLowerCase(),
    );
    if (titleCmp != 0) return titleCmp;
    final startCmp = a.verseStart.compareTo(b.verseStart);
    if (startCmp != 0) return startCmp;
    final endCmp = a.verseEnd.compareTo(b.verseEnd);
    if (endCmp != 0) return endCmp;
    return a.originalReferenceText.toLowerCase().compareTo(
      b.originalReferenceText.toLowerCase(),
    );
  }

  static String researchParagraphKey(CommentaryResearchMatchItem match) {
    return [
      _logicalBookIdentity(match),
      normalizeForSearch(match.epubHref ?? ''),
      (match.paragraphIndex ?? -1).toString(),
      normalizeForSearch(match.originalReferenceText),
      normalizeForSearch(match.anchor ?? match.fullParagraph ?? ''),
    ].join('::');
  }

  static String _logicalBookIdentity(CommentaryResearchMatchItem match) {
    final fileName = normalizeForSearch(match.fileName);
    final title = normalizeForSearch(match.itemTitle);
    return fileName.isNotEmpty ? '$fileName::$title' : title;
  }

  static int _researchPriority(
    CommentaryResearchMatchItem match, {
    required int bookId,
    required int chapter,
    required int verse,
  }) {
    if (match.bookId != bookId || match.chapter != chapter) return 10;
    if (verse > 0 && match.verseStart == verse && match.verseEnd == verse) {
      return 0;
    }
    if (verse > 0 && match.verseStart <= verse && match.verseEnd >= verse) {
      return 1;
    }
    if (match.verseStart == match.verseEnd) return 2;
    if (match.verseStart <= chapter && match.verseEnd >= chapter) return 3;
    return 4;
  }

  static int compareCommentaryPriority(
    CommentaryResearchMatchItem a,
    CommentaryResearchMatchItem b,
  ) {
    final verseStartCmp = a.verseStart.compareTo(b.verseStart);
    if (verseStartCmp != 0) return verseStartCmp;
    final verseEndCmp = a.verseEnd.compareTo(b.verseEnd);
    if (verseEndCmp != 0) return verseEndCmp;
    final spineCmp = (a.spineIndex ?? (1 << 30)).compareTo(
      b.spineIndex ?? (1 << 30),
    );
    if (spineCmp != 0) return spineCmp;
    final paraCmp = (a.paragraphIndex ?? (1 << 30)).compareTo(
      b.paragraphIndex ?? (1 << 30),
    );
    if (paraCmp != 0) return paraCmp;
    return commentaryDisplayText(a).compareTo(commentaryDisplayText(b));
  }

  static int _compareCommentaryQuality(
    CommentaryResearchMatchItem a,
    CommentaryResearchMatchItem b,
  ) {
    final scoreCmp = _commentaryQualityScore(
      a,
    ).compareTo(_commentaryQualityScore(b));
    if (scoreCmp != 0) return scoreCmp;
    return commentaryDisplayText(
      a,
    ).length.compareTo(commentaryDisplayText(b).length);
  }

  static int _commentaryQualityScore(CommentaryResearchMatchItem match) {
    final text = commentaryDisplayText(match);
    var score = text.length;
    if ((match.fullParagraph ?? '').trim().isNotEmpty) {
      score += 1000;
    }
    if (isUsableCommentaryParagraph(text)) {
      score += 200;
    }
    if (text.endsWith('.') || text.endsWith('!') || text.endsWith('?')) {
      score += 50;
    }
    return score;
  }

  static bool _looksLikeEditorialOpening(String value) {
    if (value.isEmpty) return false;
    final lead = value.length > 260 ? value.substring(0, 260) : value;
    const patterns = <String>[
      'volume 8 was published',
      'published to meet a crisis',
      'greatest crisis',
      'came from the press',
      'urgency of the matter',
      'steadying instruction was a large factor',
      'averting threatened disaster',
      'fifteen months after volume 7 was published',
      'the publishers',
      'publisher note',
      'preface',
      'foreword',
      'introduction',
      'in this volume',
      'the fifth book of the new testament',
      'the title cannot be found in the book itself',
      'one of the earliest manuscripts',
      'the codex sinaiticus',
      'gives as the title the simple word',
      'has been known from ancient times as',
    ];
    for (final pattern in patterns) {
      if (lead.contains(pattern)) return true;
    }
    return false;
  }

  static String normalizeForSearch(String value) {
    return value
        .toLowerCase()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanCommentaryParagraphText(
    String value,
    String sourceTitle,
  ) {
    var cleaned = value
        .replaceAll(
          RegExp(r'<script.*?</script>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style.*?</style>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    final title = sourceTitle.trim();
    if (title.isNotEmpty) {
      final escaped = RegExp.escape(title);
      final pattern = RegExp(
        '^$escaped(?:\\s*[:;,.\\-–—]\\s*|\\s+)',
        caseSensitive: false,
      );
      if (pattern.hasMatch(cleaned)) {
        cleaned = cleaned.replaceFirst(pattern, '').trim();
      }
    }
    return cleaned.replaceAll(RegExp(r'^[\s:;,.–—-]+'), '').trim();
  }

  static String _canonicalCommentaryText(String value) {
    return normalizeForSearch(_cleanCommentaryParagraphText(value, ''));
  }

  // Intentionally kept for future anchor normalization work.
  // ignore: unused_element
  static String _canonicalAnchor(String value) {
    return normalizeForSearch(
      value
          .replaceAll(
            RegExp(r'<script.*?</script>', caseSensitive: false, dotAll: true),
            ' ',
          )
          .replaceAll(
            RegExp(r'<style.*?</style>', caseSensitive: false, dotAll: true),
            ' ',
          )
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'"),
    );
  }

  static const List<String> _researchEligibleNeedles = <String>[
    'christ s object lessons',
    'education',
    'patriarchs and prophets',
    'prophets and kings',
    'the desire of ages',
    'the great controversy',
    'the great controversy 1888',
    'the ministry of healing',
    'steps to christ',
    'acts of the apostles',
    'early writings',
    'gospel workers',
    'life sketches of ellen g white',
    'thoughts from the mount of blessing',
    'testimonies for the church vol 1',
    'testimonies for the church vol 2',
    'testimonies for the church vol 3',
    'testimonies for the church vol 4',
    'testimonies for the church vol 5',
    'testimonies for the church vol 6',
    'testimonies for the church vol 7',
    'testimonies for the church vol 8',
    'testimonies for the church vol 9',
    'spiritual gifts vol 1',
    'christ s object lessons col',
    'ministry of healing mh',
    'desire of ages da',
    'patriarchs and prophets pp',
    'prophets and kings pk',
    'steps to christ sc',
    'acts of the apostles aa',
    'early writings ew',
    'gospel workers gw',
    'life sketches ls',
  ];

  static const List<String> _frontMatterNeedles = <String>[
    'preface',
    'foreword',
    'introduction',
    'intro',
    'contents',
    'table of contents',
    'toc',
    'title page',
    'titlepage',
    'copyright',
    'publisher',
    'editorial',
    'editor',
    'index',
    'appendix',
    'about',
    'dedication',
    'abbreviations',
    'illustrations',
    'list of',
    'cover',
    'nav',
    'metadata',
  ];

  static const List<String> _editorialNeedles = <String>[
    'the publishers send out this work',
    'this book reader',
    'this book is not published',
    'it is rare indeed',
    'as early as',
    'the present work now appearing',
    'the fundamental principles clearly',
    'the story of',
    'this volume presents',
    'the reader is not published',
    'this chapter is based on',
    'the first comprehensive article on this subject',
    'the second in a series of',
    'the publishers',
    'publisher s',
    'published to meet a crisis',
    'greatest crisis',
    'came from the press',
    'urgency of the matter',
    'time of its issuance',
    'it was not known how the tide would turn',
    'steadying instruction was a large factor',
    'averting threatened disaster',
    'volume 8 was published',
    'the fifth book of the new testament',
    'the title cannot be found in the book itself',
    'one of the earliest manuscripts',
    'the codex sinaiticus',
    'gives as the title the simple word',
    'has been known from ancient times as',
  ];
}
