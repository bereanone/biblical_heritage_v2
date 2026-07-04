import 'dart:convert';

class EgwCopiedRangeParagraph {
  const EgwCopiedRangeParagraph({
    required this.ref,
    required this.page,
    required this.text,
  });

  final String? ref;
  final int? page;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{
    'ref': ref,
    'page': page,
    'text': text,
  };
}

class EgwCopiedRangeSection {
  const EgwCopiedRangeSection({required this.title, required this.paragraphs});

  final String title;
  final List<EgwCopiedRangeParagraph> paragraphs;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'paragraphs': paragraphs.map((paragraph) => paragraph.toJson()).toList(),
  };
}

class EgwCopiedRangeDocument {
  const EgwCopiedRangeDocument({
    required this.workAbbreviation,
    required this.sections,
  });

  final String workAbbreviation;
  final List<EgwCopiedRangeSection> sections;

  Map<String, Object?> toJson() => <String, Object?>{
    'workAbbreviation': workAbbreviation,
    'sections': sections.map((section) => section.toJson()).toList(),
  };
}

class EgwCopiedRangeParagraphPreview {
  const EgwCopiedRangeParagraphPreview({
    required this.ref,
    required this.page,
    required this.snippet,
  });

  final String ref;
  final int? page;
  final String snippet;

  Map<String, Object?> toJson() => <String, Object?>{
    'ref': ref,
    'page': page,
    'snippet': snippet,
  };
}

class EgwCopiedRangeParseReport {
  const EgwCopiedRangeParseReport({
    required this.workAbbreviation,
    required this.headingCount,
    required this.paragraphCount,
    required this.firstRef,
    required this.lastRef,
    required this.duplicateRefs,
    required this.paragraphsWithoutRef,
    required this.emptyParagraphRefs,
    required this.pageNumbers,
    required this.pageNumbersNonDecreasing,
    required this.warnings,
    required this.sampleParagraphs,
    required this.isValid,
  });

  final String workAbbreviation;
  final int headingCount;
  final int paragraphCount;
  final String? firstRef;
  final String? lastRef;
  final List<String> duplicateRefs;
  final List<String> paragraphsWithoutRef;
  final List<String> emptyParagraphRefs;
  final List<int> pageNumbers;
  final bool pageNumbersNonDecreasing;
  final List<String> warnings;
  final List<EgwCopiedRangeParagraphPreview> sampleParagraphs;
  final bool isValid;

  Map<String, Object?> toJson() => <String, Object?>{
    'workAbbreviation': workAbbreviation,
    'headingCount': headingCount,
    'paragraphCount': paragraphCount,
    'firstRef': firstRef,
    'lastRef': lastRef,
    'duplicateRefs': duplicateRefs,
    'paragraphsWithoutRef': paragraphsWithoutRef,
    'emptyParagraphRefs': emptyParagraphRefs,
    'pageNumbers': pageNumbers,
    'pageNumbersNonDecreasing': pageNumbersNonDecreasing,
    'warnings': warnings,
    'sampleParagraphs': sampleParagraphs.map((item) => item.toJson()).toList(),
    'isValid': isValid,
  };
}

class EgwCopiedRangeParseResult {
  const EgwCopiedRangeParseResult({
    required this.document,
    required this.report,
  });

  final EgwCopiedRangeDocument document;
  final EgwCopiedRangeParseReport report;
}

class EgwBrowserCaptureNormalizationResult {
  const EgwBrowserCaptureNormalizationResult({
    required this.workAbbreviation,
    required this.workTitle,
    required this.author,
    required this.normalizedText,
    required this.droppedLines,
  });

  final String workAbbreviation;
  final String? workTitle;
  final String? author;
  final String normalizedText;
  final List<String> droppedLines;
}

class EgwBrowserCaptureNormalizer {
  const EgwBrowserCaptureNormalizer();

  EgwBrowserCaptureNormalizationResult normalize(
    String text, {
    String workAbbreviation = 'DAR',
    String? fallbackTitle,
    String? fallbackAuthor,
  }) {
    final abbreviation = _normalizeWhitespace(workAbbreviation).toUpperCase();
    final pageMarkerPattern = _pageMarkerPattern(abbreviation);
    final lines = const LineSplitter()
        .convert(text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
        .map(_cleanBrowserCaptureLine)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    final droppedLines = <String>[];
    final workTitle = _detectBrowserCaptureTitle(
      lines,
      abbreviation: abbreviation,
      fallbackTitle: fallbackTitle,
    );
    final author =
        _detectBrowserCaptureAuthor(lines) ??
        (fallbackAuthor == null ? null : _normalizeWhitespace(fallbackAuthor));
    final sectionTitle = workTitle == null || workTitle.isEmpty
        ? 'Browser Capture'
        : workTitle;
    final normalizedLines = <String>['Chapter 1 — $sectionTitle'];
    final pendingBodyLines = <String>[];
    var sawRef = false;
    int? currentPage;

    void addDropped(String line) {
      if (line.isNotEmpty) {
        droppedLines.add(line);
      }
    }

    void flushBodyForRef(String ref) {
      final bodyLines = sawRef
          ? _filterBrowserBodyLines(
              pendingBodyLines,
              title: workTitle,
              abbreviation: abbreviation,
            )
          : _firstBrowserBodyLines(
              pendingBodyLines,
              title: workTitle,
              abbreviation: abbreviation,
            );
      for (final line in pendingBodyLines) {
        if (!bodyLines.contains(line)) {
          addDropped(line);
        }
      }
      pendingBodyLines.clear();

      final page = _pageNumberFromParagraphRef(ref);
      if (page != null && page != currentPage) {
        normalizedLines.add('$abbreviation $page');
        currentPage = page;
      }
      normalizedLines.addAll(bodyLines);
      normalizedLines.add(ref);
      sawRef = true;
    }

    for (final line in lines) {
      if (_isBrowserChromeLine(line) || _isBrowserTocLine(line, abbreviation)) {
        addDropped(line);
        continue;
      }
      if (pageMarkerPattern.hasMatch(line)) {
        final page = int.tryParse(line.split(RegExp(r'\s+')).last);
        if (page != null && page != currentPage) {
          normalizedLines.add(line);
          currentPage = page;
        }
        continue;
      }
      final paragraphRef = _normalizedParagraphRef(line, abbreviation);
      if (paragraphRef != null) {
        flushBodyForRef(line);
        continue;
      }
      pendingBodyLines.add(line);
    }

    for (final line in pendingBodyLines) {
      addDropped(line);
    }

    return EgwBrowserCaptureNormalizationResult(
      workAbbreviation: abbreviation,
      workTitle: workTitle,
      author: author,
      normalizedText: '${normalizedLines.join('\n')}\n',
      droppedLines: droppedLines,
    );
  }
}

class _BufferedParagraph {
  _BufferedParagraph({List<String>? lines, this.page})
    : lines = lines ?? <String>[];

  final List<String> lines;
  int? page;

  String get text => _normalizeWhitespace(lines.join(' '));
}

String _normalizeWhitespace(String text) {
  return text.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _cleanBrowserCaptureLine(String text) {
  return _normalizeWhitespace(text.replaceAll(RegExp(r'[\uE000-\uF8FF]'), ''));
}

String? _detectBrowserCaptureTitle(
  List<String> lines, {
  required String abbreviation,
  String? fallbackTitle,
}) {
  final fallback = fallbackTitle == null
      ? null
      : _normalizeWhitespace(fallbackTitle);
  if (fallback != null && fallback.isNotEmpty) {
    return fallback;
  }

  final pageTitlePattern = RegExp(r'^(.+?)\s+p\.\d+$', caseSensitive: false);
  for (final line in lines) {
    final match = pageTitlePattern.firstMatch(line);
    if (match != null) {
      final title = _normalizeWhitespace(match.group(1)!);
      if (title.isNotEmpty && !_looksLikeBrowserChromeTitle(title)) {
        return title;
      }
    }
  }

  final refPattern = _paragraphRefPattern(abbreviation);
  final firstRefIndex = lines.indexWhere(refPattern.hasMatch);
  final headerLines = firstRefIndex < 0
      ? lines
      : lines.take(firstRefIndex).toList();
  for (final line in headerLines) {
    final candidate = line.endsWith('.')
        ? line.substring(0, line.length - 1)
        : line;
    if (candidate.length <= 80 &&
        !_looksLikeBrowserChromeTitle(candidate) &&
        !_looksLikeBodyParagraph(candidate)) {
      return _normalizeWhitespace(candidate);
    }
  }
  return null;
}

String? _detectBrowserCaptureAuthor(List<String> lines) {
  final authorPattern = RegExp(
    r'^By\s+(.+?)(?:\s+\(\d{4}\))?$',
    caseSensitive: false,
  );
  for (final line in lines) {
    final match = authorPattern.firstMatch(line);
    if (match != null) {
      final author = _normalizeWhitespace(match.group(1)!);
      if (author.isNotEmpty) {
        return author;
      }
    }
  }
  return null;
}

bool _looksLikeBrowserChromeTitle(String line) {
  final lower = line.toLowerCase();
  return lower.isEmpty ||
      lower == 'main' ||
      lower == 'english' ||
      lower == 'search' ||
      lower == 'search for books' ||
      lower == 'all collections' ||
      lower == 'adventist pioneer library' ||
      lower == 'pioneer authors' ||
      lower.startsWith('egw writings') ||
      lower.startsWith('url:') ||
      lower.startsWith('title:') ||
      lower.startsWith('capture method:');
}

bool _looksLikeBodyParagraph(String line) {
  return line.length > 120 ||
      line.contains('“') ||
      line.contains('”') ||
      line.contains(';') ||
      line.contains(':—');
}

bool _isBrowserChromeLine(String line) {
  final lower = line.toLowerCase();
  const exactChromeLines = <String>{
    'writings',
    'whiteestate.org | ellenwhite.org',
    'login',
    'register',
    'all collections',
    'categories',
    'titles',
    'audiobooks',
    'my library',
    'workspaces',
    'study center',
    'history',
    'subscriptions',
    'biography ellen g. white',
    'about egw writings',
    'faq',
    'bibliography',
    'more info',
    'main',
    'english',
    'adventist pioneer library',
    'pioneer authors',
    'search',
    'search for books',
    'cookie notice',
    'decline',
    'accept',
  };
  return exactChromeLines.contains(lower) ||
      lower.startsWith('url:') ||
      lower.startsWith('title:') ||
      lower.startsWith('capture method:') ||
      lower.startsWith('copyright,') ||
      lower.startsWith('version:') ||
      lower.contains('cookies are used by the white estate');
}

bool _isBrowserTocLine(String line, String abbreviation) {
  if (_looksLikeBodyParagraph(line)) {
    return false;
  }
  final escaped = RegExp.escape(abbreviation);
  return RegExp('^$escaped\\s+\\D').hasMatch(line) ||
      RegExp('^[A-Z]{2,8}\\s+.+').hasMatch(line) &&
          !RegExp(r'^[A-Z]{2,8}\s+\d').hasMatch(line);
}

List<String> _firstBrowserBodyLines(
  List<String> lines, {
  required String? title,
  required String abbreviation,
}) {
  final filtered = _filterBrowserBodyLines(
    lines,
    title: title,
    abbreviation: abbreviation,
  );
  final firstBodyIndex = filtered.indexWhere(_looksLikeBodyParagraph);
  if (firstBodyIndex >= 0) {
    return filtered.skip(firstBodyIndex).toList(growable: false);
  }
  return filtered.isEmpty ? const <String>[] : <String>[filtered.last];
}

List<String> _filterBrowserBodyLines(
  List<String> lines, {
  required String? title,
  required String abbreviation,
}) {
  return lines
      .where(
        (line) =>
            !_isBrowserChromeLine(line) &&
            !_isBrowserTocLine(line, abbreviation) &&
            !_isBrowserTitleLine(line, title),
      )
      .toList(growable: false);
}

bool _isBrowserTitleLine(String line, String? title) {
  if (title == null || title.isEmpty) {
    return false;
  }
  final normalizedLine = _normalizeWhitespace(line).toLowerCase();
  final normalizedTitle = _normalizeWhitespace(title).toLowerCase();
  return normalizedLine == normalizedTitle ||
      normalizedLine == '$normalizedTitle.' ||
      RegExp(
        '^${RegExp.escape(normalizedTitle)}\\s+p\\.\\d+\$',
      ).hasMatch(normalizedLine);
}

int? _pageNumberFromParagraphRef(String ref) {
  final match = RegExp(r'\s+(\d+)\.\d+$').firstMatch(ref);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String _snippet(String text, {int limit = 120}) {
  final normalized = _normalizeWhitespace(text);
  if (normalized.length <= limit) {
    return normalized;
  }
  return '${normalized.substring(0, limit - 1).trimRight()}…';
}

RegExp _pageMarkerPattern(String abbreviation) {
  return RegExp('^${RegExp.escape(abbreviation)}\\s+\\d+\$');
}

RegExp _paragraphRefPattern(String abbreviation) {
  return RegExp('^\\{?${RegExp.escape(abbreviation)}\\s+\\d+\\.\\d+\\}?\$');
}

String? _normalizedParagraphRef(String line, String abbreviation) {
  final normalized = _normalizeWhitespace(line);
  if (normalized.isEmpty) return null;
  final refPattern = RegExp(
    '^\\{?${RegExp.escape(abbreviation)}\\s+\\d+\\.\\d+\\}?\$',
  );
  if (!refPattern.hasMatch(normalized)) {
    return null;
  }
  return _normalizeWhitespace(
    normalized.replaceAll(RegExp(r'^[{\[]\s*|\s*[}\]]$'), ''),
  );
}

EgwCopiedRangeParseResult parseEgwCopiedRangeText(
  String text, {
  String workAbbreviation = 'DAR',
}) {
  final abbreviation = _normalizeWhitespace(workAbbreviation).toUpperCase();
  final pageMarkerPattern = _pageMarkerPattern(abbreviation);
  final sections = <EgwCopiedRangeSection>[];
  EgwCopiedRangeSection? currentSection;
  int? currentPage;
  var buffer = _BufferedParagraph(page: currentPage);
  final warnings = <String>[];
  final paragraphsWithoutRef = <String>[];
  final emptyParagraphRefs = <String>[];
  final pageNumbers = <int>[];
  final refsInOrder = <String>[];
  final seenRefs = <String>{};
  final duplicateRefs = <String>{};

  void ensureSection(String title) {
    final section = EgwCopiedRangeSection(
      title: title,
      paragraphs: <EgwCopiedRangeParagraph>[],
    );
    sections.add(section);
    currentSection = section;
  }

  void flushBuffer({String? ref}) {
    if (currentSection == null) {
      ensureSection('Unsectioned text');
    }
    final textValue = buffer.text;
    if (textValue.isEmpty && ref == null) {
      buffer = _BufferedParagraph(page: currentPage);
      return;
    }
    if (ref == null) {
      paragraphsWithoutRef.add(_snippet(textValue));
      warnings.add('Paragraph without ref: ${_snippet(textValue)}');
    } else if (textValue.isEmpty) {
      emptyParagraphRefs.add(ref);
      warnings.add('Empty paragraph text for ref $ref');
    } else {
      refsInOrder.add(ref);
      if (!seenRefs.add(ref)) {
        duplicateRefs.add(ref);
      }
    }
    currentSection!.paragraphs.add(
      EgwCopiedRangeParagraph(
        ref: ref,
        page: buffer.page ?? currentPage,
        text: textValue,
      ),
    );
    buffer = _BufferedParagraph(page: currentPage);
  }

  for (final rawLine in const LineSplitter().convert(
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
  )) {
    final line = _normalizeWhitespace(rawLine);
    if (line.isEmpty) {
      continue;
    }

    if (pageMarkerPattern.hasMatch(line)) {
      if (buffer.lines.isNotEmpty) {
        flushBuffer();
      }
      final pageNumber = int.tryParse(line.split(RegExp(r'\s+')).last);
      if (pageNumber == null) {
        warnings.add('Could not parse page marker: $line');
        continue;
      }
      if (pageNumbers.isNotEmpty && pageNumber < pageNumbers.last) {
        warnings.add(
          'Page number decreased from ${pageNumbers.last} to $pageNumber',
        );
      }
      pageNumbers.add(pageNumber);
      currentPage = pageNumber;
      buffer = _BufferedParagraph(page: currentPage);
      continue;
    }

    final paragraphRef = _normalizedParagraphRef(line, abbreviation);
    if (paragraphRef != null) {
      if (buffer.lines.isEmpty) {
        warnings.add('Ref marker without preceding paragraph text: $line');
        emptyParagraphRefs.add(paragraphRef);
        refsInOrder.add(paragraphRef);
        if (!seenRefs.add(paragraphRef)) {
          duplicateRefs.add(paragraphRef);
        }
        if (currentSection == null) {
          ensureSection('Unsectioned text');
        }
        currentSection!.paragraphs.add(
          EgwCopiedRangeParagraph(
            ref: paragraphRef,
            page: currentPage,
            text: '',
          ),
        );
        continue;
      }
      flushBuffer(ref: paragraphRef);
      continue;
    }

    final normalizedHeading =
        _normalizeHeadingLine(line) ??
        (_looksLikeStandaloneHeadingLine(line)
            ? (_normalizeWhitespace(line).endsWith('.')
                  ? _normalizeWhitespace(line)
                  : '${_normalizeWhitespace(line)}.')
            : null);
    if (normalizedHeading != null) {
      if (buffer.lines.isNotEmpty) {
        flushBuffer();
      }
      ensureSection(normalizedHeading);
      currentPage = null;
      buffer = _BufferedParagraph(page: currentPage);
      continue;
    }

    if (buffer.lines.isNotEmpty) {
      buffer.lines.add(line);
    } else {
      buffer = _BufferedParagraph(lines: <String>[line], page: currentPage);
    }
  }

  if (buffer.lines.isNotEmpty) {
    flushBuffer();
  }

  final firstRef = refsInOrder.isEmpty ? null : refsInOrder.first;
  final lastRef = refsInOrder.isEmpty ? null : refsInOrder.last;
  final duplicateRefList = duplicateRefs.toList(growable: false)..sort();
  final pageNumbersNonDecreasing = pageNumbers.asMap().entries.every(
    (entry) => entry.key == 0 || entry.value >= pageNumbers[entry.key - 1],
  );
  final validationWarnings = <String>[
    ...warnings,
    if (sections.isEmpty) 'No chapter or section headings were detected.',
    if (sections.isNotEmpty &&
        sections.every((section) => section.paragraphs.isEmpty))
      'No paragraphs were detected.',
    if (firstRef == null) 'No paragraph refs were detected.',
    if (lastRef == null) 'No last ref could be determined.',
    if (duplicateRefList.isNotEmpty)
      'Duplicate refs detected: ${duplicateRefList.join(', ')}',
    if (emptyParagraphRefs.isNotEmpty)
      'Empty paragraph refs detected: ${emptyParagraphRefs.join(', ')}',
    if (!pageNumbersNonDecreasing) 'Page numbers are not nondecreasing.',
  ];

  final paragraphCount = sections.fold<int>(
    0,
    (sum, section) => sum + section.paragraphs.length,
  );
  final sampleParagraphs = <EgwCopiedRangeParagraphPreview>[
    for (final section in sections)
      for (final paragraph in section.paragraphs)
        if (paragraph.ref != null)
          EgwCopiedRangeParagraphPreview(
            ref: paragraph.ref!,
            page: paragraph.page,
            snippet: _snippet(paragraph.text),
          ),
  ].take(10).toList(growable: false);

  final isValid =
      sections.isNotEmpty &&
      paragraphCount > 0 &&
      firstRef != null &&
      lastRef != null &&
      duplicateRefList.isEmpty &&
      emptyParagraphRefs.isEmpty &&
      pageNumbersNonDecreasing;

  return EgwCopiedRangeParseResult(
    document: EgwCopiedRangeDocument(
      workAbbreviation: abbreviation,
      sections: sections,
    ),
    report: EgwCopiedRangeParseReport(
      workAbbreviation: abbreviation,
      headingCount: sections.length,
      paragraphCount: paragraphCount,
      firstRef: firstRef,
      lastRef: lastRef,
      duplicateRefs: duplicateRefList,
      paragraphsWithoutRef: paragraphsWithoutRef,
      emptyParagraphRefs: emptyParagraphRefs,
      pageNumbers: pageNumbers,
      pageNumbersNonDecreasing: pageNumbersNonDecreasing,
      warnings: validationWarnings,
      sampleParagraphs: sampleParagraphs,
      isValid: isValid,
    ),
  );
}

String? _normalizeHeadingLine(String line) {
  final normalized = _normalizeWhitespace(line);
  final match = RegExp(
    r'^(Chapter|Section)\s+(\d+)\s*[\.\-—]\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (match == null) return null;
  final label = match.group(1) ?? 'Chapter';
  final number = match.group(2) ?? '1';
  final title = match.group(3);
  if (title == null) return null;
  return '${label[0].toUpperCase()}${label.substring(1).toLowerCase()} $number — ${_normalizeWhitespace(title).replaceAll(RegExp(r'\.+$'), '').trim()}';
}

bool _looksLikeStandaloneHeadingLine(String line) {
  final normalized = _normalizeWhitespace(line).replaceAll(RegExp(r'\.+$'), '');
  if (normalized.isEmpty) return false;
  if (RegExp(r'^(CHAPTER|SECTION)\s+([IVXLCDM]+|\d+)\b').hasMatch(normalized)) {
    return true;
  }
  if (normalized.split(RegExp(r'\s+')).length > 16) return false;
  return normalized == normalized.toUpperCase();
}
