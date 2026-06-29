// ignore_for_file: unused_element

part of 'commentary_research_library_service.dart';

mixin _CommentaryResearchLibraryServiceEpubParsingSupport {
  Future<List<_EpubSectionChunk>> _readBodySections({
    required File file,
    required String libraryItemId,
    _IndexingStats? stats,
    bool includeFrontMatter = false,
    bool preserveHeadingBlocks = false,
  }) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final packageInfo = _readEpubPackageInfo(archive);
    final sections = <_EpubSectionChunk>[];
    final fileId = libraryItemId;

    for (final entry in archive) {
      if (!entry.isFile) continue;
      final entryName = p.normalize(entry.name);
      final lowerName = entryName.toLowerCase();
      if (!lowerName.endsWith('.xhtml') && !lowerName.endsWith('.html')) {
        continue;
      }

      final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final title =
          _extractSectionTitle(raw) ?? p.basenameWithoutExtension(entryName);
      final decision = _classifyEpubSection(
        entryName: entryName,
        sectionTitle: title,
        raw: raw,
        packageInfo: packageInfo,
      );
      final keepFrontMatter =
          includeFrontMatter &&
          (decision.category == 'front_matter' ||
              decision.category == 'editorial');
      if (decision.shouldSkip && !keepFrontMatter) {
        stats?.recordSkippedSection(
          libraryItemId: fileId,
          hrefPath: entryName,
          sectionTitle: title,
          reasonSkipped: decision.reason,
          category: decision.category,
        );
        continue;
      }

      final blocks = _extractBodyBlocks(
        raw: raw,
        chapterPath: entryName,
        sectionTitle: title,
        includeHeadingBlocks: preserveHeadingBlocks,
      );
      final paragraphs = blocks
          .where((block) => block.kind == 'paragraph')
          .map((block) => block.html)
          .toList(growable: false);
      if (blocks.isEmpty) {
        stats?.recordSkippedSection(
          libraryItemId: fileId,
          hrefPath: entryName,
          sectionTitle: title,
          reasonSkipped: 'No readable HTML content.',
          category: 'other',
        );
        continue;
      }

      stats?.sectionsIndexed += 1;
      sections.add(
        _EpubSectionChunk(
          entryName: entryName,
          sectionTitle: title,
          paragraphs: paragraphs,
          blocks: blocks,
          spineIndex: packageInfo.spineIndexForPath(entryName),
        ),
      );
    }

    if (sections.isEmpty) {
      stats?.indexingErrors.add('${file.path}: no readable HTML content.');
    }
    return sections;
  }

  _EpubSectionDecision _classifyEpubSection({
    required String entryName,
    required String sectionTitle,
    required String raw,
    required _EpubPackageInfo packageInfo,
  }) {
    final normalized = entryName.toLowerCase();
    final fileName = p.basename(normalized);
    final bodyText = _stripHtml(raw);
    final bodyPreview = CommentaryResearchFilters.normalizeForSearch(
      bodyText.length > 180 ? bodyText.substring(0, 180) : bodyText,
    );
    final titleText = CommentaryResearchFilters.normalizeForSearch(
      sectionTitle,
    );
    final sourceText = CommentaryResearchFilters.normalizeForSearch(
      '$sectionTitle $fileName $normalized $bodyPreview',
    );

    if (packageInfo.isNavigationPath(normalized) ||
        fileName == 'nav.xhtml' ||
        fileName == 'toc.xhtml' ||
        fileName == 'toc.ncx' ||
        fileName == 'cover.xhtml' ||
        fileName == 'titlepage.xhtml') {
      return _EpubSectionDecision.skip(
        category: 'navigation',
        reason: 'Navigation or table-of-contents document.',
        sectionTitle: sectionTitle,
      );
    }

    if (!packageInfo.isBodyPath(normalized)) {
      return _EpubSectionDecision.skip(
        category: 'metadata',
        reason: 'Not part of the EPUB spine.',
        sectionTitle: sectionTitle,
      );
    }

    if (_looksLikeFrontMatterSection(
      titleText: titleText,
      fileName: fileName,
      bodyPreview: bodyPreview,
      sourceText: sourceText,
    )) {
      final category =
          _looksLikeEditorialSection(
            titleText: titleText,
            fileName: fileName,
            bodyPreview: bodyPreview,
            sourceText: sourceText,
          )
          ? 'editorial'
          : 'front_matter';
      return _EpubSectionDecision.skip(
        category: category,
        reason: 'Front-matter or editorial section.',
        sectionTitle: sectionTitle,
      );
    }

    return _EpubSectionDecision.keep(sectionTitle: sectionTitle);
  }

  bool _looksLikeFrontMatterSection({
    required String titleText,
    required String fileName,
    required String bodyPreview,
    required String sourceText,
  }) {
    final exactTitleNeedles = <String>{
      'preface',
      'foreword',
      'introduction',
      'intro',
      'contents',
      'table of contents',
      'title page',
      'titlepage',
      'copyright',
      'publisher note',
      'editor note',
      'editorial note',
      'about this book',
      'about the author',
      'publication information',
      'source credits',
      'list of illustrations',
      'abbreviations',
      'dedication',
      'index',
      'bibliography',
      'metadata',
    };
    final filenameNeedles = <String>{
      'nav.xhtml',
      'toc.xhtml',
      'toc.ncx',
      'cover.xhtml',
      'titlepage.xhtml',
    };
    final titleStartsWith = <String>[
      'preface',
      'foreword',
      'introduction',
      'appendix',
      'index',
      'bibliography',
      'about this book',
      'about the author',
      'publication information',
      'source credits',
    ];

    if (filenameNeedles.contains(fileName)) return true;
    if (exactTitleNeedles.contains(titleText)) return true;
    for (final prefix in titleStartsWith) {
      if (titleText.startsWith(prefix)) return true;
    }

    final previewNeedles = <String>[
      'publisher note',
      'editor note',
      'editorial note',
      'table of contents',
      'copyright',
      'publication information',
      'source credits',
      'about this book',
      'about the author',
    ];
    for (final needle in previewNeedles) {
      if (bodyPreview.contains(needle)) return true;
    }

    return sourceText.contains('title page') ||
        sourceText.contains('table of contents') ||
        sourceText.contains('source credits');
  }

  bool _looksLikeEditorialSection({
    required String titleText,
    required String fileName,
    required String bodyPreview,
    required String sourceText,
  }) {
    final needles = <String>[
      'publisher note',
      'editor note',
      'editorial note',
      'source credits',
      'publication information',
      'about this book',
      'about the author',
    ];
    for (final needle in needles) {
      if (titleText.contains(needle) ||
          fileName.contains(needle) ||
          bodyPreview.contains(needle) ||
          sourceText.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  String? _extractSectionTitle(String raw) {
    final titleMatch = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    final headingMatch = RegExp(
      r'<h[1-6][^>]*>(.*?)</h[1-6]>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    final candidate = _stripHtml(
      headingMatch?.group(1) ?? titleMatch?.group(1) ?? '',
    );
    return candidate.trim().isEmpty ? null : candidate.trim();
  }

  _EpubPackageInfo _readEpubPackageInfo(Archive archive) {
    final containerEntry = archive.findFile('META-INF/container.xml');
    if (containerEntry == null) {
      return const _EpubPackageInfo();
    }
    final containerXml = utf8.decode(
      containerEntry.content as List<int>,
      allowMalformed: true,
    );
    final opfPathMatch = RegExp(
      r'full-path="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(containerXml);
    final opfPath = opfPathMatch?.group(1);
    if (opfPath == null || opfPath.trim().isEmpty) {
      return const _EpubPackageInfo();
    }
    final opfEntry = archive.findFile(opfPath);
    if (opfEntry == null) {
      return const _EpubPackageInfo();
    }
    final opfXml = utf8.decode(
      opfEntry.content as List<int>,
      allowMalformed: true,
    );
    final opfDir = p.dirname(opfPath);
    final manifest = <String, _EpubManifestItem>{};
    for (final match in RegExp(
      r'<item\b[^>]*>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final tag = match.group(0) ?? '';
      final id = _attributeValue(tag, 'id');
      final href = _attributeValue(tag, 'href');
      final properties = _attributeValue(tag, 'properties');
      if (id == null || href == null) continue;
      final normalizedPath = p.normalize(p.join(opfDir, href));
      manifest[id] = _EpubManifestItem(
        href: normalizedPath,
        properties: properties ?? '',
      );
    }
    final coverImagePath = _discoverCoverImagePath(
      archive: archive,
      opfXml: opfXml,
      manifest: manifest,
    );

    final spinePaths = <String>[];
    for (final match in RegExp(
      r'<itemref\b[^>]*>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final tag = match.group(0) ?? '';
      final idref = _attributeValue(tag, 'idref');
      final linear = _attributeValue(tag, 'linear');
      if (idref == null || linear?.toLowerCase() == 'no') continue;
      final item = manifest[idref];
      if (item == null) continue;
      spinePaths.add(item.href.toLowerCase());
    }

    final navigationPaths = <String>{};
    for (final item in manifest.values) {
      final basename = p.basename(item.href).toLowerCase();
      if (item.properties.toLowerCase().contains('nav') ||
          basename == 'nav.xhtml' ||
          basename == 'toc.xhtml' ||
          basename == 'toc.ncx' ||
          basename == 'cover.xhtml' ||
          basename == 'titlepage.xhtml') {
        navigationPaths.add(item.href.toLowerCase());
      }
    }

    return _EpubPackageInfo(
      coverImagePath: coverImagePath,
      spinePaths: spinePaths.toSet(),
      spineOrderedPaths: List<String>.unmodifiable(
        spinePaths.map((path) => p.normalize(path).toLowerCase()),
      ),
      navigationPaths: navigationPaths,
    );
  }

  String? _attributeValue(String tag, String name) {
    final match = RegExp(
      '$name="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1);
  }

  String? _extractClassName(String attrs) {
    final match = RegExp(
      r'''class\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(attrs);
    final value = match?.group(1)?.trim();
    return value != null && value.isNotEmpty ? value : null;
  }

  String? _discoverCoverImagePath({
    required Archive archive,
    required String opfXml,
    required Map<String, _EpubManifestItem> manifest,
  }) {
    final coverIdMatch = RegExp(
      r'<meta\b[^>]*name="cover"[^>]*content="([^"]+)"',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(opfXml);
    final coverId = coverIdMatch?.group(1)?.trim();
    if (coverId != null && coverId.isNotEmpty) {
      final manifestItem = manifest[coverId];
      if (manifestItem != null) {
        return manifestItem.href;
      }
    }

    for (final item in manifest.values) {
      if (item.properties.toLowerCase().contains('cover-image')) {
        return item.href;
      }
    }

    for (final item in manifest.values) {
      if (_looksLikeCoverImagePath(item.href)) {
        return item.href;
      }
    }

    for (final item in manifest.values) {
      final basename = p.basename(item.href).toLowerCase();
      if (basename != 'cover.xhtml' && basename != 'titlepage.xhtml') {
        continue;
      }
      final entry = archive.findFile(item.href);
      if (entry == null || !entry.isFile) continue;
      final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final imgMatch = RegExp(
        r'<(?:img|image)\b[^>]*(?:src|href|xlink:href)="([^"]+)"',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(raw);
      final href = imgMatch?.group(1)?.trim();
      if (href == null || href.isEmpty) continue;
      return p.normalize(p.join(p.dirname(item.href), href));
    }

    return null;
  }

  bool _looksLikeCoverImagePath(String path) {
    final lower = path.toLowerCase();
    final basename = p.basename(lower);
    if (!_isImageExtension(lower)) return false;
    return basename.startsWith('cover') ||
        basename.startsWith('front-cover') ||
        basename.startsWith('frontcover') ||
        basename == 'titlepage.jpg' ||
        basename == 'titlepage.jpeg' ||
        basename == 'titlepage.png' ||
        basename == 'titlepage.webp';
  }

  bool _isImageExtension(String path) {
    final ext = p.extension(path).toLowerCase();
    return const <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
    }.contains(ext);
  }

  String _coverImageExtension(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    if (const <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
    }.contains(ext)) {
      return ext;
    }
    return '.jpg';
  }

  List<_NavigationEntryDraft> _extractNavigationEntriesFromDocument({
    required String raw,
    required String basePath,
    required String libraryItemId,
    required String navType,
    required String deviceId,
    required String createdAt,
    required String updatedAt,
  }) {
    final entries = <_NavigationEntryDraft>[];
    var sortOrder = 0;
    final navigationSource = navType.toLowerCase() == 'toc'
        ? _extractTocDocument(raw)
        : raw;
    final anchorPattern = RegExp(
      r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in anchorPattern.allMatches(navigationSource)) {
      final href = match.group(1)?.trim() ?? '';
      final label = _stripHtml(match.group(2) ?? '').trim();
      if (href.isEmpty || label.isEmpty) continue;
      final hrefParts = href.split('#');
      final resolvedPath = p.normalize(
        p.join(p.dirname(basePath), hrefParts.first),
      );
      final anchorId = hrefParts.length > 1
          ? hrefParts.sublist(1).join('#')
          : null;
      entries.add(
        _NavigationEntryDraft(
          id: 'nav_${_slug(libraryItemId)}_${_slug(basePath)}_$sortOrder',
          libraryItemId: libraryItemId,
          parentId: null,
          label: label,
          href: resolvedPath,
          anchorId: anchorId,
          spineIndex: null,
          sortOrder: sortOrder,
          depth: _estimateNavDepth(navigationSource, match.start),
          navType: navType,
          contentKind: _navigationContentKind(
            label: label,
            href: resolvedPath,
            navType: navType,
          ),
          createdAt: createdAt,
          updatedAt: updatedAt,
          deviceId: deviceId,
        ),
      );
      sortOrder += 1;
    }
    return entries;
  }

  List<LibraryBookBlock> _extractBodyBlocks({
    required String raw,
    required String chapterPath,
    required String sectionTitle,
    required bool includeHeadingBlocks,
  }) {
    final bodyMatch = RegExp(
      r'<body\b[^>]*>(.*?)</body>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    final source = bodyMatch?.group(1) ?? raw;
    final blocks = <LibraryBookBlock>[];
    final stack = <_HtmlBlockFrame>[];
    final blockPattern = RegExp(
      r'<(/?)(h[1-6]|p|div|blockquote)\b([^>]*)>',
      caseSensitive: false,
      dotAll: true,
    );
    var bodyOrder = 0;

    for (final match in blockPattern.allMatches(source)) {
      final isClosing = (match.group(1) ?? '').isNotEmpty;
      final tag = (match.group(2) ?? '').toLowerCase();
      final attrs = match.group(3) ?? '';
      final token = match.group(0) ?? '';

      if (!isClosing) {
        if (token.endsWith('/>')) {
          continue;
        }
        stack.add(
          _HtmlBlockFrame(
            tag: tag,
            attrs: attrs,
            start: match.start,
            contentStart: match.end,
          ),
        );
        continue;
      }

      final openIndex = stack.lastIndexWhere((frame) => frame.tag == tag);
      if (openIndex < 0) continue;
      final frame = stack.removeAt(openIndex);
      final innerHtml = source.substring(frame.contentStart, match.start);
      final text = libraryCleanVisibleMarginArtifacts(_stripHtml(innerHtml));
      if (text.isEmpty) continue;
      if (_isHiddenLikeBlock(attrs: frame.attrs, innerHtml: innerHtml) ||
          _isFootnoteOrEndnoteBlock(attrs: frame.attrs)) {
        continue;
      }
      final hasBlockquoteAncestor = stack
          .take(openIndex)
          .any((ancestor) => ancestor.tag == 'blockquote');
      if (hasBlockquoteAncestor && tag != 'blockquote') {
        continue;
      }

      final headingLevel = tag.startsWith('h')
          ? int.tryParse(tag.substring(1))
          : null;
      final explicitAnchorId = _extractAnchorIdFromHtml(
        attrs: frame.attrs,
        innerHtml: innerHtml,
      );
      final headingLike =
          headingLevel != null ||
          _looksLikeHeadingLikeBlock(
            tag: tag,
            attrs: frame.attrs,
            innerHtml: innerHtml,
            text: text,
          );
      final hasNestedBlockTags = RegExp(
        r'<(/?)(h[1-6]|p|div)\b',
        caseSensitive: false,
      ).hasMatch(innerHtml);

      if (tag == 'div' && hasNestedBlockTags) {
        continue;
      }

      if (headingLike) {
        if (!includeHeadingBlocks) continue;
        bodyOrder += 1;
        blocks.add(
          LibraryBookBlock(
            html: source.substring(frame.start, match.end),
            text: text,
            kind: 'heading',
            sourceTag: tag,
            className: _extractClassName(frame.attrs),
            headingLevel: headingLevel ?? _headingLevelForHeadingLike(attrs),
            anchorId: explicitAnchorId?.trim().isNotEmpty == true
                ? explicitAnchorId!.trim()
                : _generatedHeadingAnchor(
                    chapterPath: chapterPath,
                    headingIndex: bodyOrder,
                    headingText: text,
                    explicitAnchorId: explicitAnchorId,
                  ),
            bodyOrder: bodyOrder,
          ),
        );
        continue;
      }

      bodyOrder += 1;
      blocks.add(
        LibraryBookBlock(
          html: source.substring(frame.start, match.end),
          text: text,
          kind: tag == 'blockquote' ? 'blockquote' : 'paragraph',
          sourceTag: tag,
          className: _extractClassName(frame.attrs),
          anchorId: explicitAnchorId?.trim().isNotEmpty == true
              ? explicitAnchorId!.trim()
              : null,
          bodyOrder: bodyOrder,
        ),
      );
    }

    return blocks;
  }

  bool _isHiddenLikeBlock({required String attrs, required String innerHtml}) {
    final normalizedAttrs = attrs.toLowerCase();
    final normalizedInner = innerHtml.toLowerCase();

    if (normalizedAttrs.contains('hidden') ||
        normalizedAttrs.contains('aria-hidden="true"') ||
        normalizedAttrs.contains("aria-hidden='true'") ||
        normalizedAttrs.contains('display:none') ||
        normalizedAttrs.contains('display: none') ||
        normalizedAttrs.contains('visibility:hidden') ||
        normalizedAttrs.contains('visibility: hidden')) {
      return true;
    }

    final classMatch = RegExp(
      r'''class\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(attrs);
    if (classMatch != null) {
      final classValue = classMatch.group(1)!.toLowerCase();
      final classTokens = classValue.split(RegExp(r'[\s_-]+'));
      if (classTokens.contains('nav') ||
          classTokens.contains('toc') ||
          classTokens.contains('metadata') ||
          classTokens.contains('meta') ||
          classTokens.contains('alternate') ||
          classTokens.contains('hidden') ||
          classTokens.contains('sr') ||
          classTokens.contains('only') ||
          classValue.contains('visually-hidden')) {
        return true;
      }
    }

    if (RegExp(
      r'<(nav|script|style|meta|link)\b',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(normalizedInner)) {
      return true;
    }

    return false;
  }

  bool _isFootnoteOrEndnoteBlock({required String attrs}) {
    final normalizedAttrs = attrs.toLowerCase();

    final classMatch = RegExp(
      r'''class\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(attrs);
    if (classMatch != null) {
      final classValue = classMatch.group(1)!.toLowerCase();
      final classTokens = classValue.split(RegExp(r'[\s_-]+'));
      if (classTokens.any(
        (token) =>
            token.contains('footnote') ||
            token.contains('endnote') ||
            token.contains('rearnote') ||
            token.contains('chapternote') ||
            token.contains('sourcenote') ||
            token.contains('sourcecredit') ||
            token == 'reference',
      )) {
        return true;
      }
    }

    if (RegExp(
      r'''(?:epub:type|type|role)\s*=\s*["'][^"']*(footnote|endnote|rearnote|reference)[^"']*["']''',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(normalizedAttrs)) {
      return true;
    }

    return false;
  }

  String _extractTocDocument(String raw) {
    final tocNavPattern = RegExp(
      r'''<nav\b[^>]*(?:epub:type|type)\s*=\s*["']toc["'][^>]*>.*?</nav>''',
      caseSensitive: false,
      dotAll: true,
    );
    final tocMatch = tocNavPattern.firstMatch(raw);
    if (tocMatch != null) {
      return tocMatch.group(0) ?? raw;
    }

    final navPattern = RegExp(
      r'<nav\b[^>]*>.*?</nav>',
      caseSensitive: false,
      dotAll: true,
    );
    final navMatch = navPattern.firstMatch(raw);
    return navMatch?.group(0) ?? raw;
  }

  bool _isChapterTitleBlock(String text, {required String sectionTitle}) {
    final normalizedBlock = _normalizeNavigationText(text);
    final normalizedTitle = _normalizeNavigationText(sectionTitle);
    if (normalizedBlock.isEmpty || normalizedTitle.isEmpty) return false;
    return normalizedBlock == normalizedTitle;
  }

  bool _looksLikeHeadingLikeBlock({
    required String tag,
    required String attrs,
    required String innerHtml,
    required String text,
  }) {
    if (tag.startsWith('h')) return true;
    if (tag != 'p' && tag != 'div') return false;

    final normalizedText = _normalizeNavigationText(text);
    if (normalizedText.isEmpty) return false;

    if (RegExp(
      r'''class\s*=\s*["'][^"']*(heading|chapter|section|title|subhead|subtitle|headline|chapterhead|sectionhead|lessonhead|versehead|parthead|booktitle|chapter-title|section-title|sub-title|subheading)[^"']*["']''',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(attrs)) {
      return true;
    }

    if (RegExp(
      r'''style\s*=\s*["'][^"']*(font-weight\s*:\s*(bold|700|800)|text-align\s*:\s*center)[^"']*["']''',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(attrs)) {
      return true;
    }

    if (RegExp(
          r'<(strong|b)\b',
          caseSensitive: false,
          dotAll: true,
        ).hasMatch(innerHtml) &&
        normalizedText.split(RegExp(r'\s+')).length <= 16 &&
        normalizedText.length <= 140) {
      return true;
    }

    final lowerAttrs = attrs.toLowerCase();
    if ((lowerAttrs.contains('font-weight:bold') ||
            lowerAttrs.contains('font-weight: bold') ||
            lowerAttrs.contains('font-weight:700') ||
            lowerAttrs.contains('font-weight: 700')) &&
        normalizedText.split(RegExp(r'\s+')).length <= 16 &&
        normalizedText.length <= 140) {
      return true;
    }

    return false;
  }

  int? _headingLevelForHeadingLike(String attrs) {
    final inferred = RegExp(
      r'level\s*[:=]\s*([1-6])',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(attrs);
    final level = inferred?.group(1);
    if (level == null) return 4;
    return int.tryParse(level);
  }

  String? _extractAnchorIdFromHtml({
    required String attrs,
    required String innerHtml,
  }) {
    final explicit =
        _attributeValue(attrs, 'id') ?? _attributeValue(attrs, 'name');
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }

    final nestedAnchorMatch = RegExp(
      r'''<a\b[^>]*(?:id|name)\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(innerHtml);
    final nestedAnchor = nestedAnchorMatch?.group(1)?.trim();
    if (nestedAnchor != null && nestedAnchor.isNotEmpty) {
      return nestedAnchor;
    }

    final nestedSpanMatch = RegExp(
      r'''<(?:span|div)\b[^>]*(?:id|name)\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(innerHtml);
    return nestedSpanMatch?.group(1)?.trim();
  }

  String _generatedHeadingAnchor({
    required String chapterPath,
    required int headingIndex,
    required String headingText,
    String? explicitAnchorId,
  }) {
    final preservedAnchor = explicitAnchorId?.trim();
    if (preservedAnchor != null && preservedAnchor.isNotEmpty) {
      return preservedAnchor;
    }

    final chapterSlug = _slug(p.basenameWithoutExtension(chapterPath));
    final headingSlug = _slug(headingText);
    if (headingSlug.isEmpty) {
      return '${chapterSlug}_heading_$headingIndex';
    }
    return '${chapterSlug}_heading_${headingIndex}_$headingSlug';
  }

  String _navigationEntryKey(String label, String? href, String? anchorId) {
    return [
      _normalizeNavigationText(label),
      _navigationHrefKey(href),
      _normalizeNavigationText(anchorId ?? ''),
    ].join('|');
  }

  String _navigationHrefKey(String? href) {
    final trimmed = href?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    final base = trimmed.split('#').first;
    return p.normalize(base).toLowerCase();
  }

  int _compareNavigationDrafts(
    _NavigationEntryDraft a,
    _NavigationEntryDraft b,
  ) {
    final leftSort = a.sortOrder ?? 1 << 30;
    final rightSort = b.sortOrder ?? 1 << 30;
    final sortCompare = leftSort.compareTo(rightSort);
    if (sortCompare != 0) return sortCompare;

    final leftDepth = a.depth ?? 0;
    final rightDepth = b.depth ?? 0;
    final depthCompare = leftDepth.compareTo(rightDepth);
    if (depthCompare != 0) return depthCompare;

    final parentCompare = (a.parentId ?? '').compareTo(b.parentId ?? '');
    if (parentCompare != 0) return parentCompare;

    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  }

  int _estimateNavDepth(String raw, int anchorStart) {
    final prefix = raw.substring(0, anchorStart);
    final opened = RegExp(
      r'<ol\b',
      caseSensitive: false,
    ).allMatches(prefix).length;
    final closed = RegExp(
      r'</ol>',
      caseSensitive: false,
    ).allMatches(prefix).length;
    final depth = opened - closed;
    return depth < 0 ? 0 : depth;
  }

  String _stripHtml(String text) {
    var out = text
        .replaceAll(
          RegExp(r'<script.*?</script>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style.*?</style>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    out = out
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // Collapse whitespace first — numeric entities like &#160; are 6 ASCII
    // chars and survive the collapse as-is, so they can be decoded afterwards
    // without being swallowed by the \s+ replacement or .trim().
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final code = int.tryParse(m.group(1)!, radix: 16);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        })
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        });
  }

  String _slug(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _navigationContentKind({
    required String label,
    required String? href,
    required String navType,
  }) {
    final normalizedLabel = _normalizeNavigationText(label);
    final normalizedHref = _normalizeNavigationText(
      p.basenameWithoutExtension(href ?? ''),
    );
    final combined = '$normalizedLabel $normalizedHref';

    if (_isNavigationCoverLabel(combined)) return 'cover';
    if (_isNavigationTitlePageLabel(combined)) return 'title_page';
    if (_isNavigationTocLabel(combined) || navType.toLowerCase() == 'toc') {
      return 'toc';
    }
    if (_isNavigationAboutLabel(combined)) return 'about';
    if (_isNavigationCopyrightLabel(combined)) return 'copyright';
    if (_isNavigationForewordLabel(combined)) return 'foreword';
    if (_isNavigationPrefaceLabel(combined)) return 'preface';
    if (_isNavigationIntroductionLabel(combined)) return 'introduction';
    if (_isNavigationAppendixLabel(combined)) return 'appendix';
    if (_isNavigationBodyLabel(combined)) return 'body';
    return 'unknown';
  }

  bool _isNavigationCoverLabel(String value) {
    return value.contains('cover');
  }

  bool _isNavigationTitlePageLabel(String value) {
    return value.contains('title page') || value.contains('titlepage');
  }

  bool _isNavigationTocLabel(String value) {
    return value.contains('table of contents') ||
        value == 'toc' ||
        value.startsWith('toc ') ||
        value.contains(' contents') ||
        value.startsWith('nav ');
  }

  bool _isNavigationAboutLabel(String value) {
    return value.contains('about book') ||
        value.contains('aboutbook') ||
        value.contains('information about this book') ||
        value.contains('about this book') ||
        value.contains('about the author');
  }

  bool _isNavigationCopyrightLabel(String value) {
    return value.contains('copyright') ||
        value.contains('publisher') ||
        value.contains('editorial') ||
        value.contains('publication information') ||
        value.contains('source credits');
  }

  bool _isNavigationForewordLabel(String value) {
    return value.startsWith('foreword');
  }

  bool _isNavigationPrefaceLabel(String value) {
    return value.startsWith('preface');
  }

  bool _isNavigationIntroductionLabel(String value) {
    return value.startsWith('introduction') ||
        value.startsWith('intro') ||
        value.contains('to the reader') ||
        value.contains('for the reader');
  }

  bool _isNavigationAppendixLabel(String value) {
    return value.startsWith('appendix') ||
        value.contains('back matter') ||
        value.contains('afterword') ||
        value.contains('bibliography') ||
        value.contains('index');
  }

  bool _isNavigationBodyLabel(String value) {
    if (value.isEmpty) return false;
    const prefixes = <String>['chapter', 'section', 'day', 'lesson', 'part'];
    for (final prefix in prefixes) {
      if (value.startsWith(prefix)) return true;
    }

    return RegExp(
          r'^(chapter|section|day|lesson|part)\s+\d+',
        ).hasMatch(value) ||
        RegExp(
          r'^(chapter|section|day|lesson|part)\s+[ivxlcdm]+',
        ).hasMatch(value) ||
        RegExp(r'^\d+[\s\.\)]').hasMatch(value);
  }

  String _normalizeNavigationText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
