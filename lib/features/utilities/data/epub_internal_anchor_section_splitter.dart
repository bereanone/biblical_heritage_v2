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
  /// EPUB3 `<nav>` document otherwise. Targets with no fragment (whole-file
  /// destinations) are dropped, since they carry nothing to split by.
  static Map<String, List<EpubAnchorTarget>> readTargetsByPath({
    required Archive archive,
    required String fallbackTitle,
  }) {
    final ncxTargets = PioneerEpubNavigationParser.parse(
      archive: archive,
      fallbackTitle: fallbackTitle,
    );
    final targets = ncxTargets.isNotEmpty
        ? ncxTargets
        : _readNavDocumentTargets(archive: archive, fallbackTitle: fallbackTitle);

    final byPath = <String, List<EpubAnchorTarget>>{};
    for (final target in targets) {
      if (target.anchor.isEmpty) continue;
      byPath
          .putIfAbsent(normalizedEpubPathKey(target.path), () => <EpubAnchorTarget>[])
          .add(EpubAnchorTarget(title: target.title, anchor: target.anchor));
    }
    return byPath;
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

  /// Slices [rawHtml] (one EPUB body file's full markup) into one section
  /// per entry of [targets], each running from its own anchor (an
  /// `id="..."`/`name="..."` attribute anywhere in the markup) up to the
  /// next target's anchor, or to the end of the file for the last target.
  /// Consecutive targets that share the exact same anchor collapse onto the
  /// last one, so an identical anchor's earlier target doesn't spawn an
  /// empty, duplicate section; a target whose anchor never actually appears
  /// in [rawHtml] is skipped rather than guessed at. Returns one section
  /// covering the whole file, titled [wholeFileTitle], when fewer than 2
  /// targets survive that resolution -- a single destination is not a
  /// split, and this keeps existing one-section-per-file behavior for
  /// ordinary EPUBs untouched.
  static List<EpubAnchorSplitSection> splitByAnchors({
    required String rawHtml,
    required List<EpubAnchorTarget> targets,
    required String wholeFileTitle,
  }) {
    if (targets.length < 2) {
      return <EpubAnchorSplitSection>[
        EpubAnchorSplitSection(title: wholeFileTitle, html: rawHtml),
      ];
    }

    final sections = <EpubAnchorSplitSection>[];
    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      final startMatch = _anchorPattern(target.anchor).firstMatch(rawHtml);
      if (startMatch == null) continue;

      var end = rawHtml.length;
      for (
        var nextIndex = index + 1;
        nextIndex < targets.length;
        nextIndex++
      ) {
        final next = targets[nextIndex];
        if (next.anchor == target.anchor) {
          end = startMatch.start;
          break;
        }
        final nextMatches = _anchorPattern(
          next.anchor,
        ).allMatches(rawHtml, startMatch.end);
        if (nextMatches.isNotEmpty) {
          end = nextMatches.first.start;
          break;
        }
      }

      if (end <= startMatch.start) continue;
      sections.add(
        EpubAnchorSplitSection(
          title: target.title,
          html: rawHtml.substring(startMatch.start, end),
        ),
      );
    }

    return sections.isEmpty
        ? <EpubAnchorSplitSection>[
            EpubAnchorSplitSection(title: wholeFileTitle, html: rawHtml),
          ]
        : sections;
  }

  static RegExp _anchorPattern(String anchor) => RegExp(
    '<[^>]*\\b(?:id|name)\\s*=\\s*["\\\']${RegExp.escape(anchor)}'
    '["\\\'][^>]*>',
    caseSensitive: false,
  );
}
