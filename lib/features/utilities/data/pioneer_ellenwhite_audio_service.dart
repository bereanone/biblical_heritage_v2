import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'pioneer_source_catalog.dart';

typedef PioneerEllenWhiteAudioFetcher = Future<String> Function(Uri uri);

class PioneerEllenWhiteAudioService {
  PioneerEllenWhiteAudioService({PioneerEllenWhiteAudioFetcher? fetcher})
    : _fetcher = fetcher ?? _downloadHtml;

  static final PioneerEllenWhiteAudioService instance =
      PioneerEllenWhiteAudioService();

  static final Uri collectionUri = Uri.parse(
    'https://ellenwhiteaudio.org/ebooks-of-the-pioneers/',
  );

  static const String collectionPageUrl =
      'https://ellenwhiteaudio.org/ebooks-of-the-pioneers/';

  final PioneerEllenWhiteAudioFetcher _fetcher;

  Future<PioneerSourceCatalog>? _cachedCatalog;

  Future<PioneerSourceCatalog> loadCatalog({bool refresh = false}) {
    if (!refresh && _cachedCatalog != null) {
      return _cachedCatalog!;
    }
    final future = _loadCatalog();
    _cachedCatalog = future;
    return future;
  }

  Future<PioneerSourceCatalog> _loadCatalog() async {
    try {
      final html = await _fetcher(collectionUri);
      return _parseCatalog(html);
    } catch (error, stackTrace) {
      debugPrint('EllenWhiteAudio discovery failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return PioneerSourceCatalog(
        authors: const <PioneerSourceAuthor>[],
        authorsById: const <String, PioneerSourceAuthor>{},
        worksById: const <String, PioneerSourceWork>{},
      );
    }
  }

  PioneerSourceCatalog _parseCatalog(String html) {
    final headingPattern = RegExp(
      r'<h([2-4])\b[^>]*>(.*?)</h\1>',
      caseSensitive: false,
      dotAll: true,
    );
    final headingMatches = headingPattern.allMatches(html).toList(growable: false);
    if (headingMatches.isEmpty) {
      return PioneerSourceCatalog(
        authors: const <PioneerSourceAuthor>[],
        authorsById: const <String, PioneerSourceAuthor>{},
        worksById: const <String, PioneerSourceWork>{},
      );
    }

    final authors = <PioneerSourceAuthor>[];
    for (var i = 0; i < headingMatches.length; i++) {
      final headingMatch = headingMatches[i];
      final headingText = _cleanText(headingMatch.group(2) ?? '');
      if (!_looksLikeAuthorHeading(headingText)) continue;

      final sectionStart = headingMatch.end;
      final sectionEnd =
          i + 1 < headingMatches.length ? headingMatches[i + 1].start : html.length;
      final sectionHtml = html.substring(sectionStart, sectionEnd);
      final works = _parseWorksForAuthor(headingText, sectionHtml);
      if (works.isEmpty) continue;

      authors.add(
        PioneerSourceAuthor(
          id: _stableId(headingText),
          name: headingText,
          sourceFamily: 'EllenWhiteAudio',
          works: List<PioneerSourceWork>.unmodifiable(works),
          sortKey: headingText.toLowerCase(),
        ),
      );
    }

    authors.sort((left, right) {
      final compare = left.sortKey.compareTo(right.sortKey);
      if (compare != 0) return compare;
      return left.name.compareTo(right.name);
    });

    final authorsById = <String, PioneerSourceAuthor>{
      for (final author in authors) author.id: author,
    };
    final worksById = <String, PioneerSourceWork>{
      for (final author in authors)
        for (final work in author.works)
          work.id: work,
    };
    return PioneerSourceCatalog(
      authors: List<PioneerSourceAuthor>.unmodifiable(authors),
      authorsById: Map<String, PioneerSourceAuthor>.unmodifiable(authorsById),
      worksById: Map<String, PioneerSourceWork>.unmodifiable(worksById),
    );
  }

  List<PioneerSourceWork> _parseWorksForAuthor(
    String authorName,
    String sectionHtml,
  ) {
    final anchorPattern = RegExp(
      r'<a\b([^>]*)href="([^"]+)"([^>]*)>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );
    final anchors = anchorPattern.allMatches(sectionHtml).toList(growable: false);
    if (anchors.isEmpty) return const <PioneerSourceWork>[];

    final imageAnchors = <RegExpMatch>[];
    for (final anchor in anchors) {
      if (_isImageAnchor(anchor)) {
        imageAnchors.add(anchor);
      }
    }
    if (imageAnchors.isEmpty) {
      return _parseFallbackWorks(authorName, sectionHtml, anchors);
    }

    final works = <PioneerSourceWork>[];
    for (var i = 0; i < imageAnchors.length; i++) {
      final imageAnchor = imageAnchors[i];
      final rowStart = imageAnchor.start;
      final rowEnd =
          i + 1 < imageAnchors.length ? imageAnchors[i + 1].start : sectionHtml.length;
      final rowHtml = sectionHtml.substring(rowStart, rowEnd);
      final work = _parseWorkRow(authorName, rowHtml);
      if (work != null) {
        works.add(work);
      }
    }
    return works;
  }

  List<PioneerSourceWork> _parseFallbackWorks(
    String authorName,
    String sectionHtml,
    List<RegExpMatch> anchors,
  ) {
    final works = <PioneerSourceWork>[];
    final fileAnchors = anchors.where(_isFileAnchor).toList(growable: false);
    for (var i = 0; i < fileAnchors.length; i++) {
      final rowStart = i == 0 ? 0 : fileAnchors[i - 1].end;
      final rowEnd = i + 1 < fileAnchors.length ? fileAnchors[i + 1].start : sectionHtml.length;
      final rowHtml = sectionHtml.substring(rowStart, rowEnd);
      final work = _parseWorkRow(authorName, rowHtml);
      if (work != null) {
        works.add(work);
      }
    }
    return works;
  }

  PioneerSourceWork? _parseWorkRow(
    String authorName,
    String rowHtml,
  ) {
    final anchorPattern = RegExp(
      r'<a\b([^>]*)href="([^"]+)"([^>]*)>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );
    final anchors = anchorPattern.allMatches(rowHtml).toList(growable: false);
    if (anchors.isEmpty) return null;

    String? epubUrl;
    String? pdfUrl;
    String? mobiUrl;
    RegExpMatch? firstFileAnchor;

    for (final anchor in anchors) {
      if (_isImageAnchor(anchor)) continue;
      final kind = _anchorKind(anchor);
      firstFileAnchor ??= anchor;
      switch (kind) {
        case 'epub':
          epubUrl ??= _normalizeUrl(anchor.group(2));
          break;
        case 'pdf':
          pdfUrl ??= _normalizeUrl(anchor.group(2));
          break;
        case 'mobi':
          mobiUrl ??= _normalizeUrl(anchor.group(2));
          break;
      }
    }

    if (epubUrl == null && pdfUrl == null && mobiUrl == null) {
      return null;
    }

    final imageAnchor = anchors.firstWhere(
      _isImageAnchor,
      orElse: () => anchors.first,
    );
    final titleStart = imageAnchor.end;
    final titleEnd = firstFileAnchor?.start ?? rowHtml.length;
    final rawTitle = _cleanText(rowHtml.substring(titleStart, titleEnd));
    final title = rawTitle.isNotEmpty ? rawTitle : _titleFromUrl(epubUrl ?? pdfUrl ?? mobiUrl);
    if (title.isEmpty) return null;

    final hasEpub = epubUrl != null;
    final hasAnySource = hasEpub || pdfUrl != null || mobiUrl != null;
    final availability = hasEpub
        ? PioneerSourceAvailability.available
        : PioneerSourceAvailability.sourceNeeded;

    final candidates = <PioneerSourceCandidate>[];
    if (epubUrl != null) {
      candidates.add(
        PioneerSourceCandidate(
          provider: 'ellenwhiteaudio',
          sourceType: 'directEpub',
          url: epubUrl,
          priority: 1,
          qualityTier: 'epub',
          availability: PioneerSourceAvailability.available,
          notes: 'Direct EPUB from EllenWhiteAudio.',
        ),
      );
    }
    if (pdfUrl != null) {
      candidates.add(
        PioneerSourceCandidate(
          provider: 'ellenwhiteaudio',
          sourceType: 'pdf',
          url: pdfUrl,
          priority: 30,
          qualityTier: 'pdf',
          availability: PioneerSourceAvailability.available,
          notes: 'PDF from EllenWhiteAudio.',
        ),
      );
    }
    if (mobiUrl != null) {
      candidates.add(
        PioneerSourceCandidate(
          provider: 'ellenwhiteaudio',
          sourceType: 'mobi',
          url: mobiUrl,
          priority: 40,
          qualityTier: 'html',
          availability: PioneerSourceAvailability.available,
          notes: 'MOBI from EllenWhiteAudio.',
        ),
      );
    }

    final workId = _stableId(title);
    return PioneerSourceWork(
      id: workId,
      authorId: _stableId(authorName),
      authorName: authorName,
      sourceFamily: 'EllenWhiteAudio',
      title: title,
      abbreviation: '',
      group: 'Pioneer Authors',
      subgroup: 'Pioneer',
      availability: availability,
      verified: hasAnySource,
      catalogImportable: hasEpub,
      sourceType: hasEpub ? 'directEpub' : (pdfUrl != null ? 'pdf' : 'mobi'),
      sourceUrl: epubUrl ?? pdfUrl ?? mobiUrl,
      collectionUrl: collectionPageUrl,
      captureUrl: null,
      readerUrl: null,
      directFileUrl: epubUrl,
      directFileType: hasEpub ? 'epub' : null,
      sourceLabel: 'EllenWhiteAudio',
      notes: 'Discovered from EllenWhiteAudio ebook listing.',
      sourceCandidates: List<PioneerSourceCandidate>.unmodifiable(candidates),
    );
  }

  bool _looksLikeAuthorHeading(String headingText) {
    final normalized = headingText.toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized.contains('adventist pioneer library')) return false;
    if (normalized.contains('pioneer library')) return false;
    if (normalized.contains('pioneer books')) return false;
    if (normalized.contains('ebooks of the pioneers')) return false;
    if (normalized.contains('ellenwhiteaudio')) return false;
    if (normalized.contains('main menu')) return false;
    if (normalized.contains('donate')) return false;
    return normalized.contains(' ') || normalized.contains('.');
  }

  bool _isImageAnchor(RegExpMatch match) {
    final innerHtml = match.group(4) ?? '';
    final text = _cleanText(innerHtml).toLowerCase();
    return innerHtml.toLowerCase().contains('<img') || text == 'image';
  }

  bool _isFileAnchor(RegExpMatch match) {
    final kind = _anchorKind(match);
    return kind == 'file' || kind == 'epub' || kind == 'pdf' || kind == 'mobi';
  }

  String _anchorKind(RegExpMatch match) {
    final href = _normalizeUrl(match.group(2));
    final innerHtml = match.group(4) ?? '';
    final text = _cleanText(innerHtml).toLowerCase();
    final lowerHref = href.toLowerCase();
    if (lowerHref.endsWith('.epub') || text == 'epub' || text == 'epub.') {
      return 'epub';
    }
    if (lowerHref.endsWith('.pdf') || text == 'pdf') {
      return 'pdf';
    }
    if (lowerHref.endsWith('.mobi') ||
        lowerHref.endsWith('.azw') ||
        lowerHref.endsWith('.prc') ||
        text == 'mobi' ||
        text == 'kindle') {
      return 'mobi';
    }
    return 'file';
  }

  String _normalizeUrl(String? href) {
    final normalized = href?.trim() ?? '';
    if (normalized.isEmpty) return '';
    return collectionUri.resolve(normalized).toString();
  }
}

Future<String> _downloadHtml(Uri uri) async {
  final client = HttpClient()..autoUncompress = true;
  try {
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'StudyBible2 Pioneer Discovery',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Unexpected HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    final bytes = await _consolidateHttpClientResponseBytes(response);
    return utf8.decode(bytes);
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> _consolidateHttpClientResponseBytes(
  HttpClientResponse response,
) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

String _cleanText(String input) {
  return input
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#8217;', "'")
      .replaceAll('&rsquo;', "'")
      .replaceAll('&#8211;', '-')
      .replaceAll('&#8212;', '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _titleFromUrl(String? url) {
  final normalized = url?.trim() ?? '';
  if (normalized.isEmpty) return '';
  final uri = Uri.tryParse(normalized);
  final segment = uri?.pathSegments.isNotEmpty == true
      ? uri!.pathSegments.last
      : normalized;
  final withoutExtension = segment.replaceAll(RegExp(r'\.[^.]+$'), '');
  return _cleanText(Uri.decodeFull(withoutExtension));
}

String _stableId(String value) {
  final normalized = value.toLowerCase().trim();
  if (normalized.isEmpty) return '';
  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
