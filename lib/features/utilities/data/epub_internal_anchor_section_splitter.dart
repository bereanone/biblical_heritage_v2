import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'pioneer_epub_inspection_parser.dart';

/// One authored navigation target that lands inside a single EPUB body
/// file, used to split that file's raw markup into per-anchor sections.
class EpubAnchorTarget {
  const EpubAnchorTarget({required this.title, required this.anchor});

  final String title;
  final String anchor;
}

/// One slice of an EPUB body file's markup, from one authored navigation
/// target's anchor up to the next.
class EpubAnchorSplitSection {
  const EpubAnchorSplitSection({required this.title, required this.html});

  final String title;
  final String html;
}

/// Splits a single EPUB body file's raw markup into multiple titled
/// sections wherever the book's own table of contents (an NCX or an EPUB3
/// `nav.xhtml` document) places 2+ authored destinations inside that one
/// file via distinct internal anchors -- the "single-spine-file" shape
/// produced by tools (e.g. Capture Clipper) that emit one physical file per
/// book rather than one per chapter. Left unsplit, every paragraph in that
/// one file is misattributed to whichever heading happens to come first
/// (e.g. every chapter shows up labeled "INTRODUCTION").
///
/// This mirrors the anchor-to-next-anchor slicing already proven in
/// `pioneer_text_import_service.dart`'s NCX-anchored EPUB importer
/// (`_parseNcxAnchoredEpubSections`), generalized to also read an EPUB3
/// `nav.xhtml`-style navigation document, and reduced to operate on
/// already-decoded raw HTML for one file at a time rather than an entire
/// archive -- so any pipeline that already reads a spine file's own bytes
/// can call it per-file without adopting a different section-reading
/// strategy.
class EpubInternalAnchorSectionSplitter {
  const EpubInternalAnchorSectionSplitter._();

  /// Reads every authored navigation target in [archive], grouped by the
  /// normalized package-relative path it targets, in authored document
  /// order. Prefers an NCX (`.ncx`) navMap when present; falls back to an
  /// EPUB3 `<nav>` document otherwise. A whole-file destination is retained:
  /// when it is the authored parent immediately before two or more anchored
  /// children, it owns the file's leading slice up to the first child anchor.
  static Map<String, List<EpubAnchorTarget>> readTargetsByPath({
    required Archive archive,
    required String fallbackTitle,
  }) {
    final targets = readNavigationTargets(
      archive: archive,
      fallbackTitle: fallbackTitle,
    );

    final byPath = <String, List<EpubAnchorTarget>>{};
    for (final target in targets) {
      byPath
          .putIfAbsent(
            normalizedEpubPathKey(target.path),
            () => <EpubAnchorTarget>[],
          )
          .add(EpubAnchorTarget(title: target.title, anchor: target.anchor));
    }
    return byPath;
  }

  /// The source-authored Contents, distinct from inferred headings/page labels.
  static List<PioneerEpubNavigationTarget> readNavigationTargets({
    required Archive archive,
    required String fallbackTitle,
  }) {
    final ncxTargets = PioneerEpubNavigationParser.parse(
      archive: archive,
      fallbackTitle: fallbackTitle,
    );
    return ncxTargets.isNotEmpty
        ? ncxTargets
        : _readNavDocumentTargets(
            archive: archive,
            fallbackTitle: fallbackTitle,
          );
  }

  /// Normalizes an EPUB package-relative path the same way for both the
  /// targets this splitter reads and the spine paths callers already track,
  /// so `readTargetsByPath`'s keys line up with a caller's own path keys.
  static String normalizedEpubPathKey(String path) =>
      p.normalize(path).toLowerCase();

  static List<PioneerEpubNavigationTarget> _readNavDocumentTargets({
    required Archive archive,
    required String fallbackTitle,
  }) {
    ArchiveFile? navEntry;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final basename = p.basename(entry.name).toLowerCase();
      if (basename == 'nav.xhtml' || basename == 'toc.xhtml') {
        navEntry = entry;
        break;
      }
    }
    if (navEntry == null) return const <PioneerEpubNavigationTarget>[];

    final navPath = p.normalize(navEntry.name);
    final navDirectory = p.dirname(navPath);
    final raw = utf8.decode(
      navEntry.content as List<int>,
      allowMalformed: true,
    );
    final tocMatch = RegExp(
      r'''<nav\b[^>]*(?:epub:type|type)\s*=\s*["']toc["'][^>]*>(.*?)</nav>''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    final navMatch =
        tocMatch ??
        RegExp(
          r'<nav\b[^>]*>(.*?)</nav>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(raw);
    final source = navMatch?.group(1) ?? raw;

    final anchorPattern = RegExp(
      r'''<a\b[^>]*href\s*=\s*(["'])([^"']+)\1[^>]*>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    );
    final targets = <PioneerEpubNavigationTarget>[];
    for (final match in anchorPattern.allMatches(source)) {
      final href = (match.group(2) ?? '').trim();
      if (href.isEmpty) continue;
      final hashIndex = href.indexOf('#');
      final encodedPath = hashIndex < 0 ? href : href.substring(0, hashIndex);
      if (encodedPath.isEmpty) continue;
      final anchor = hashIndex < 0
          ? ''
          : Uri.decodeComponent(href.substring(hashIndex + 1));
      final title = PioneerEpubHtmlBodyParser.plainText(match.group(3) ?? '');
      targets.add(
        PioneerEpubNavigationTarget(
          title: title.isEmpty ? fallbackTitle : title,
          path: p.normalize(p.join(navDirectory, Uri.decodeFull(encodedPath))),
          anchor: anchor,
          depth: 0,
        ),
      );
    }
    return List<PioneerEpubNavigationTarget>.unmodifiable(targets);
  }

  /// Split only at resolved, distinct text-block boundaries in source order.
  /// Concatenating the slices reproduces the original markup byte for byte.
  /// A broken navigation target keeps the whole file intact for inspection.
  static List<EpubAnchorSplitSection> splitByAnchors({
    required String rawHtml,
    required List<EpubAnchorTarget> targets,
    required String wholeFileTitle,
  }) {
    List<EpubAnchorSplitSection> wholeFile() => [
      EpubAnchorSplitSection(title: wholeFileTitle, html: rawHtml),
    ];
    final boundaries = <int, EpubAnchorTarget>{};
    for (final target in targets.where((target) => target.anchor.isNotEmpty)) {
      final matches = _anchorPattern(
        target.anchor,
      ).allMatches(rawHtml).toList();
      if (matches.length != 1) return wholeFile();
      boundaries[_containingBlockStart(rawHtml, matches.single.start)] = target;
    }
    if (boundaries.length < 2) return wholeFile();
    final starts = boundaries.keys.toList()..sort();
    final prefix = rawHtml.substring(0, starts.first);
    final visiblePrefix = prefix
        .replaceAll(
          RegExp(r'<head\b.*?</head\s*>', caseSensitive: false, dotAll: true),
          '',
        )
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&(?:nbsp|#160|#xA0);', caseSensitive: false), '')
        .trim();
    final sections = <EpubAnchorSplitSection>[];
    if (visiblePrefix.isNotEmpty) {
      final parents = targets.where((target) => target.anchor.isEmpty);
      sections.add(
        EpubAnchorSplitSection(
          title: parents.isEmpty ? wholeFileTitle : parents.first.title,
          html: prefix,
        ),
      );
    }
    for (var index = 0; index < starts.length; index++) {
      final start = index == 0 && sections.isEmpty ? 0 : starts[index];
      final end = index + 1 < starts.length
          ? starts[index + 1]
          : rawHtml.length;
      sections.add(
        EpubAnchorSplitSection(
          title: boundaries[starts[index]]!.title,
          html: rawHtml.substring(start, end),
        ),
      );
    }
    return sections;
  }

  /// Producers often put an empty span inside H2 rather than its id on H2.
  /// Starting at that span severs the heading and silently loses its text.
  static int _containingBlockStart(String html, int anchorStart) {
    final stack = <({String tag, int start})>[];
    final tags = RegExp(
      r'<(/?)(h[1-6]|p|li|blockquote|pre|div)\b[^>]*>',
      caseSensitive: false,
    );
    for (final tag in tags.allMatches(html.substring(0, anchorStart))) {
      final name = tag.group(2)!.toLowerCase();
      if (tag.group(1) == '/') {
        final index = stack.lastIndexWhere((entry) => entry.tag == name);
        if (index >= 0) stack.removeRange(index, stack.length);
      } else if (!tag.group(0)!.endsWith('/>')) {
        stack.add((tag: name, start: tag.start));
      }
    }
    return stack.isEmpty ? anchorStart : stack.last.start;
  }

  static RegExp _anchorPattern(String anchor) => RegExp(
    '<[^>]*\\b(?:id|name)\\s*=\\s*["\\\']${RegExp.escape(anchor)}'
    '["\\\'][^>]*>',
    caseSensitive: false,
  );
}
