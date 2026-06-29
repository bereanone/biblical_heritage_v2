import 'pioneer_source_catalog.dart';

const int kPioneerMinimumReadyHtmlLength = 12000;

class PioneerLinkInfo {
  const PioneerLinkInfo({
    required this.href,
    required this.text,
    required this.kind,
  });

  final String href;
  final String text;
  final String kind;

  bool get isToc => kind == 'toc' || text.toLowerCase().contains('contents');
  bool get isReadPage => kind == 'read-page' || href.contains('/read?');
  bool get isNext => kind == 'next';
  bool get isPrevious => kind == 'previous';
}

class PioneerPageStructure {
  const PioneerPageStructure({
    required this.title,
    required this.author,
    required this.currentPanelId,
    required this.currentIndex,
    required this.tocLinks,
    required this.readPageLinks,
    required this.nextUrl,
    required this.previousUrl,
    required this.paragraphMarkers,
  });

  final String title;
  final String author;
  final String currentPanelId;
  final int? currentIndex;
  final List<PioneerLinkInfo> tocLinks;
  final List<PioneerLinkInfo> readPageLinks;
  final String? nextUrl;
  final String? previousUrl;
  final List<String> paragraphMarkers;

  bool get hasTocLinks => tocLinks.isNotEmpty;
  bool get hasReadPageLinks => readPageLinks.isNotEmpty;
}

class PioneerPageInspection {
  const PioneerPageInspection({
    required this.isReady,
    required this.manualVerificationRequired,
    required this.reason,
    required this.currentUrl,
    required this.title,
    required this.bodyPreview,
    required this.outerHtmlLength,
    required this.structure,
    this.outerHtml,
  });

  final bool isReady;
  final bool manualVerificationRequired;
  final String reason;
  final String currentUrl;
  final String title;
  final String bodyPreview;
  final int outerHtmlLength;
  final PioneerPageStructure structure;
  final String? outerHtml;

  bool get isChallenge => manualVerificationRequired && !isReady;
}

class PioneerSectionCaptureLink {
  const PioneerSectionCaptureLink({
    required this.title,
    required this.href,
    required this.index,
  });

  final String title;
  final String href;
  final int? index;
}

PioneerPageStructure inspectPioneerPageStructure({
  required String currentUrl,
  required String title,
  required String bodyText,
  required String outerHtml,
}) {
  final normalizedUrl = currentUrl.trim();
  final normalizedTitle = title.trim();
  final normalizedBody = bodyText.trim();
  final normalizedHtml = outerHtml.trim();

  final panelMatch = RegExp(r'[?&]panels=([^&]+)').firstMatch(normalizedUrl);
  final indexMatch = RegExp(r'[?&]index=(\d+)').firstMatch(normalizedUrl);
  final currentPanelId = panelMatch?.group(1)?.trim() ?? '';
  final currentIndex = int.tryParse(indexMatch?.group(1) ?? '');

  final paragraphMarkers = <String>{};
  for (final match in RegExp(
    r'\b[A-Z0-9]{2,12}\s+\d+(?:[.:]\d+)+\b',
  ).allMatches(normalizedBody)) {
    paragraphMarkers.add(match.group(0)!.trim());
  }

  final links = _extractAnchorLinks(normalizedHtml);
  final tocLinks = <PioneerLinkInfo>[];
  final readPageLinks = <PioneerLinkInfo>[];
  String? nextUrl;
  String? previousUrl;
  for (final link in links) {
    if (link.isToc) {
      tocLinks.add(link);
    }
    if (link.isReadPage) {
      readPageLinks.add(link);
    }
    if (link.isNext && nextUrl == null) {
      nextUrl = link.href;
    }
    if (link.isPrevious && previousUrl == null) {
      previousUrl = link.href;
    }
  }

  return PioneerPageStructure(
    title: normalizedTitle,
    author:
        _extractHtmlMetaValue(normalizedHtml, const ['author', 'og:author']) ??
        '',
    currentPanelId: currentPanelId,
    currentIndex: currentIndex,
    tocLinks: List<PioneerLinkInfo>.unmodifiable(tocLinks),
    readPageLinks: List<PioneerLinkInfo>.unmodifiable(readPageLinks),
    nextUrl: nextUrl,
    previousUrl: previousUrl,
    paragraphMarkers: List<String>.unmodifiable(
      (paragraphMarkers.toList()..sort()),
    ),
  );
}

PioneerPageInspection inspectPioneerPage({
  required String currentUrl,
  required String title,
  required String bodyText,
  required String outerHtml,
}) {
  final normalizedUrl = currentUrl.trim();
  final normalizedTitle = title.trim();
  final normalizedBody = bodyText.trim();
  final normalizedHtml = outerHtml.trim();
  final bodyPreview = normalizedBody.length > 200
      ? normalizedBody.substring(0, 200)
      : normalizedBody;
  final structure = inspectPioneerPageStructure(
    currentUrl: currentUrl,
    title: title,
    bodyText: bodyText,
    outerHtml: outerHtml,
  );
  final searchBlob = [
    normalizedUrl,
    normalizedTitle,
    normalizedBody,
  ].join('\n').toLowerCase();

  bool containsAny(List<String> markers) {
    for (final marker in markers) {
      if (searchBlob.contains(marker.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  const challengeMarkers = <String>[
    'cloudflare',
    'cf-chl',
    'cf chl',
    'captcha',
    'challenge',
    'turnstile',
    'verify you are human',
    'performing security verification',
  ];

  if (normalizedUrl.isEmpty) {
    return PioneerPageInspection(
      isReady: false,
      manualVerificationRequired: false,
      reason: 'Open the Pioneer source page in the WebView first.',
      currentUrl: normalizedUrl,
      title: normalizedTitle,
      bodyPreview: bodyPreview,
      outerHtmlLength: normalizedHtml.length,
      structure: structure,
      outerHtml: normalizedHtml,
    );
  }

  if (normalizedTitle.toLowerCase().contains('just a moment') ||
      containsAny(challengeMarkers)) {
    return PioneerPageInspection(
      isReady: false,
      manualVerificationRequired: true,
      reason:
          'Manual verification required. Complete the challenge in the WebView, then tap Check Page again.',
      currentUrl: normalizedUrl,
      title: normalizedTitle,
      bodyPreview: bodyPreview,
      outerHtmlLength: normalizedHtml.length,
      structure: structure,
      outerHtml: normalizedHtml,
    );
  }

  if (normalizedHtml.length < kPioneerMinimumReadyHtmlLength) {
    return PioneerPageInspection(
      isReady: false,
      manualVerificationRequired: false,
      reason:
          'The page is still loading or the HTML is too short. Wait for the real content, then tap Check Page again.',
      currentUrl: normalizedUrl,
      title: normalizedTitle,
      bodyPreview: bodyPreview,
      outerHtmlLength: normalizedHtml.length,
      structure: structure,
      outerHtml: normalizedHtml,
    );
  }

  return PioneerPageInspection(
    isReady: true,
    manualVerificationRequired: false,
    reason: 'Page looks ready for capture.',
    currentUrl: normalizedUrl,
    title: normalizedTitle,
    bodyPreview: bodyPreview,
    outerHtmlLength: normalizedHtml.length,
    structure: structure,
    outerHtml: normalizedHtml,
  );
}

List<PioneerSectionCaptureLink> discoverPioneerSectionLinks({
  required String currentUrl,
  required PioneerSourceWork work,
  required String outerHtml,
}) {
  final currentUri = Uri.tryParse(currentUrl.trim());
  final currentPanelId =
      RegExp(r'[?&]panels=([^&]+)').firstMatch(currentUrl)?.group(1) ?? '';
  final seen = <String>{};
  final links = <PioneerSectionCaptureLink>[];

  for (final link in _extractAnchorLinks(outerHtml)) {
    if (!link.isReadPage || link.isNext || link.isPrevious) continue;
    final absoluteHref = _absolutePioneerHref(link.href, currentUri);
    if (absoluteHref == null) continue;
    final normalizedTitle = normalizePioneerCaptureLine(link.text);
    if (normalizedTitle.isEmpty || normalizedTitle.length > 120) continue;
    if (_isPioneerReaderChromeLabel(normalizedTitle)) continue;
    final linkPanelId =
        RegExp(r'[?&]panels=([^&]+)').firstMatch(absoluteHref)?.group(1) ?? '';
    if (currentPanelId.isNotEmpty &&
        linkPanelId.isNotEmpty &&
        linkPanelId != currentPanelId) {
      continue;
    }
    final key = _canonicalPioneerReaderHref(absoluteHref);
    if (!seen.add(key)) continue;
    final index = int.tryParse(
      RegExp(r'[?&]index=(\d+)').firstMatch(absoluteHref)?.group(1) ?? '',
    );
    links.add(
      PioneerSectionCaptureLink(
        title: normalizedTitle,
        href: absoluteHref,
        index: index,
      ),
    );
  }

  links.sort((left, right) {
    final leftIndex = left.index;
    final rightIndex = right.index;
    if (leftIndex != null && rightIndex != null) {
      return leftIndex.compareTo(rightIndex);
    }
    if (leftIndex != null) return -1;
    if (rightIndex != null) return 1;
    return 0;
  });
  return List<PioneerSectionCaptureLink>.unmodifiable(links);
}

String normalizePioneerCaptureLine(String value) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join(' ')
      .trim();
}

List<PioneerLinkInfo> _extractAnchorLinks(String outerHtml) {
  final links = <PioneerLinkInfo>[];
  final anchorPattern = RegExp(
    r'''<a\b([^>]*)href=(["'])([^"']+?)\2([^>]*)>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );
  for (final match in anchorPattern.allMatches(outerHtml)) {
    final attrs = '${match.group(1) ?? ''} ${match.group(4) ?? ''}'
        .toLowerCase();
    final href = (match.group(3) ?? '').trim();
    if (href.isEmpty) continue;
    final text = _stripHtml(match.group(5) ?? '');
    final kind = _linkKindFromAnchor(attrs, href, text);
    links.add(PioneerLinkInfo(href: href, text: text, kind: kind));
  }
  return links;
}

String _linkKindFromAnchor(String attrs, String href, String text) {
  final lowerHref = href.toLowerCase();
  final combined = '$attrs $lowerHref ${text.toLowerCase()}';
  if (combined.contains('rel="next"') ||
      combined.contains('aria-label="next"') ||
      combined.contains('next page') ||
      combined.contains('next')) {
    return 'next';
  }
  if (combined.contains('rel="prev"') ||
      combined.contains('aria-label="previous"') ||
      combined.contains('previous page') ||
      combined.contains('prev')) {
    return 'previous';
  }
  if (combined.contains('toc') ||
      combined.contains('table of contents') ||
      combined.contains('contents') ||
      lowerHref.contains('allcollection') ||
      lowerHref.contains('/collection')) {
    return 'toc';
  }
  if (lowerHref.contains('/read?')) {
    return 'read-page';
  }
  return 'link';
}

String? _extractHtmlMetaValue(String html, List<String> selectors) {
  for (final selector in selectors) {
    switch (selector) {
      case 'author':
        final authorMatch = RegExp(
          r'<meta\b[^>]*name="author"[^>]*content="([^"]+)"[^>]*>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(html);
        if (authorMatch != null &&
            (authorMatch.group(1)?.trim().isNotEmpty ?? false)) {
          return authorMatch.group(1)!.trim();
        }
        break;
      case 'og:author':
        final ogAuthorMatch = RegExp(
          r'<meta\b[^>]*property="og:author"[^>]*content="([^"]+)"[^>]*>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(html);
        if (ogAuthorMatch != null &&
            (ogAuthorMatch.group(1)?.trim().isNotEmpty ?? false)) {
          return ogAuthorMatch.group(1)!.trim();
        }
        break;
    }
  }
  return null;
}

bool _isPioneerReaderChromeLabel(String text) {
  final normalized = text.toLowerCase().trim();
  if (normalized.isEmpty) return true;
  return const <String>{
        'next',
        'previous',
        'prev',
        'contents',
        'table of contents',
        'search',
        'menu',
        'settings',
        'read',
        'listen',
        'share',
        'bookmark',
      }.contains(normalized) ||
      normalized.startsWith('copyright ') ||
      normalized.startsWith('egw writings');
}

String? _absolutePioneerHref(String href, Uri? currentUri) {
  final trimmed = href.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.hasScheme) return uri.toString();
  if (currentUri == null || !currentUri.hasScheme) return trimmed;
  return currentUri.resolveUri(uri).toString();
}

String _canonicalPioneerReaderHref(String href) {
  final uri = Uri.tryParse(href);
  if (uri == null) return href.trim();
  final panels = uri.queryParameters['panels'] ?? '';
  final index = uri.queryParameters['index'] ?? '';
  return '${uri.host}${uri.path}?panels=$panels&index=$index';
}

String _stripHtml(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
