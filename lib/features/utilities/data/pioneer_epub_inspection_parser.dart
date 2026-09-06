import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Read-only EPUB container inspection.
///
/// This helper deliberately has no database, filesystem, network, catalog, or
/// import-route dependency. It reports the package's authored entry names in
/// archive/spine order; it never edits text, headings, or metadata.
class PioneerEpubArchiveInspection {
  const PioneerEpubArchiveInspection._({
    required this.archive,
    required this.isValidZip,
    required this.hasMimeType,
    required this.hasContainerXml,
    required this.opfPath,
    required this.manifestCount,
    required this.spineCount,
    required this.spineHrefs,
    required this.xhtmlHtmlEntries,
    required this.selectedContentFiles,
  });

  final Archive? archive;
  final bool isValidZip;
  final bool hasMimeType;
  final bool hasContainerXml;
  final String? opfPath;
  final int manifestCount;
  final int spineCount;
  final List<String> spineHrefs;
  final List<String> xhtmlHtmlEntries;
  final List<String> selectedContentFiles;

  static PioneerEpubArchiveInspection inspect(Uint8List bytes) {
    // `ZipDecoder` accepts arbitrary short byte sequences as an empty archive.
    // Treat a missing ZIP local-header/end-of-central-directory signature as
    // invalid rather than silently describing it as an empty EPUB.
    final hasZipSignature =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
        (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
    if (!hasZipSignature) {
      return const PioneerEpubArchiveInspection._(
        archive: null,
        isValidZip: false,
        hasMimeType: false,
        hasContainerXml: false,
        opfPath: null,
        manifestCount: 0,
        spineCount: 0,
        spineHrefs: <String>[],
        xhtmlHtmlEntries: <String>[],
        selectedContentFiles: <String>[],
      );
    }
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (_) {
      return const PioneerEpubArchiveInspection._(
        archive: null,
        isValidZip: false,
        hasMimeType: false,
        hasContainerXml: false,
        opfPath: null,
        manifestCount: 0,
        spineCount: 0,
        spineHrefs: <String>[],
        xhtmlHtmlEntries: <String>[],
        selectedContentFiles: <String>[],
      );
    }

    final containerEntry = archive.findFile('META-INF/container.xml');
    final opfPath = containerEntry == null
        ? null
        : _opfPathFromContainer(containerEntry);
    final opf = opfPath == null ? null : archive.findFile(opfPath);
    final opfXml = opf == null || !opf.isFile
        ? null
        : utf8.decode(opf.content as List<int>, allowMalformed: true);
    final manifest = opfXml == null
        ? const <String, String>{}
        : _manifest(opfXml);
    final spineHrefs = opfXml == null
        ? const <String>[]
        : _spineHrefs(opfXml, manifest, opfPath!);
    final xhtmlHtmlEntries =
        archive.files
            .where((entry) {
              final name = p.normalize(entry.name).toLowerCase();
              return entry.isFile &&
                  (name.endsWith('.xhtml') || name.endsWith('.html'));
            })
            .map((entry) => p.normalize(entry.name))
            .toList()
          ..sort();
    final selected = spineHrefs.isEmpty
        ? List<String>.of(xhtmlHtmlEntries)
        : List<String>.of(spineHrefs);

    return PioneerEpubArchiveInspection._(
      archive: archive,
      isValidZip: true,
      hasMimeType: archive.findFile('mimetype') != null,
      hasContainerXml: containerEntry != null,
      opfPath: opfPath,
      manifestCount: opfXml == null
          ? 0
          : RegExp(
              r'<item\b[^>]*>',
              caseSensitive: false,
            ).allMatches(opfXml).length,
      spineCount: opfXml == null
          ? 0
          : RegExp(
              r'<itemref\b[^>]*>',
              caseSensitive: false,
            ).allMatches(opfXml).length,
      spineHrefs: List.unmodifiable(spineHrefs),
      xhtmlHtmlEntries: List.unmodifiable(xhtmlHtmlEntries),
      selectedContentFiles: List.unmodifiable(selected),
    );
  }
}

/// One authored NCX navigation target, in document order.
///
/// This is deliberately only a read model. Consumers decide whether and how
/// to persist it; this parser never changes a title, heading, or source body.
class PioneerEpubNavigationTarget {
  const PioneerEpubNavigationTarget({
    required this.title,
    required this.path,
    required this.anchor,
    required this.depth,
  });

  final String title;
  final String path;
  final String anchor;
  final int depth;
}

/// Reads the authored NCX hierarchy from an already-loaded EPUB archive.
///
/// It has no source-profile, catalog, database, filesystem, or import-route
/// dependency. [fallbackTitle] is used only when an NCX label is empty.
class PioneerEpubNavigationParser {
  const PioneerEpubNavigationParser._();

  static List<PioneerEpubNavigationTarget> parse({
    required Archive archive,
    required String fallbackTitle,
  }) {
    final ncxEntry = archive.files.cast<ArchiveFile?>().firstWhere(
      (entry) =>
          entry?.isFile == true &&
          p.normalize(entry!.name).toLowerCase().endsWith('.ncx'),
      orElse: () => null,
    );
    if (ncxEntry == null) return const <PioneerEpubNavigationTarget>[];

    final ncxPath = p.normalize(ncxEntry.name);
    final ncxDirectory = p.dirname(ncxPath);
    final ncx = utf8.decode(
      ncxEntry.content as List<int>,
      allowMalformed: true,
    );
    // An NCX's authored chapter hierarchy lives in <navMap>; a sibling
    // <pageList> (printed-page-number targets, e.g. "iv", "v", "vi" mapped
    // onto anchors inside ordinary chapter files) uses the exact same
    // <navLabel><text>...</text></navLabel><content src=".../>" shape and
    // would otherwise be scooped up as if it were real chapter/section
    // navigation -- multiple page numbers landing in one chapter file then
    // look identical to a genuine multi-chapter single-spine-file book.
    // Scope the scan to <navMap> when present; fall back to the whole
    // document only for a malformed NCX with no <navMap> tag at all, same
    // as before this exclusion existed.
    final navMapMatch = RegExp(
      r'<navMap\b[^>]*>(.*?)</navMap>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(ncx);
    final navMapSource = navMapMatch?.group(1) ?? ncx;
    final tokenPattern = RegExp(
      r'<(/?navPoint\b[^>]*>)|<navLabel\b[^>]*>\s*<text\b[^>]*>(.*?)</text>\s*</navLabel>\s*<content\b[^>]*\bsrc\s*=\s*["'
      ']([^"'
      ']+)["'
      '][^>]*/?>',
      caseSensitive: false,
      dotAll: true,
    );

    final targets = <PioneerEpubNavigationTarget>[];
    var currentDepth = 0;
    for (final match in tokenPattern.allMatches(navMapSource)) {
      final navPointMatch = match.group(1);
      if (navPointMatch != null) {
        currentDepth = navPointMatch.startsWith('/')
            ? (currentDepth > 0 ? currentDepth - 1 : 0)
            : currentDepth + 1;
        continue;
      }
      final source = (match.group(3) ?? '').trim();
      final hashIndex = source.indexOf('#');
      final encodedPath = hashIndex < 0
          ? source
          : source.substring(0, hashIndex);
      if (encodedPath.isEmpty) continue;
      final anchor = hashIndex < 0
          ? ''
          : Uri.decodeComponent(source.substring(hashIndex + 1));
      final title = _plainText(match.group(2) ?? '');
      targets.add(
        PioneerEpubNavigationTarget(
          title: title.isEmpty ? fallbackTitle : title,
          path: _normalizeEpubPath(
            p.join(ncxDirectory, Uri.decodeFull(encodedPath)),
          ),
          anchor: anchor,
          depth: currentDepth > 0 ? currentDepth - 1 : 0,
        ),
      );
    }
    return List<PioneerEpubNavigationTarget>.unmodifiable(targets);
  }
}

/// Stateless XHTML text helpers used by the EPUB parser.
///
/// They operate only on the supplied markup. In particular, they do not
/// correct spelling or select/filter source content.
class PioneerEpubHtmlBodyParser {
  const PioneerEpubHtmlBodyParser._();

  static String? extractBody(String raw) => RegExp(
    r'<body\b[^>]*>(.*?)</body>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(raw)?.group(1);

  static String plainText(String value) => value
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

/// Pure comparison normalization used by the existing filtering policy.
/// It never changes stored authored text.
class PioneerEpubFilteringNormalization {
  const PioneerEpubFilteringNormalization._();

  static String collapseWhitespace(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String comparisonKey(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Current front-matter classification policy for public-domain Pioneer
/// EPUB parsing. Dependency-free: no database, filesystem, network,
/// catalog, or import-route access.
class PioneerEpubFrontMatterClassifier {
  const PioneerEpubFrontMatterClassifier._();

  static const Set<String> _frontMatterTitles = <String>{
    'cover',
    'contents',
    'table of contents',
    'toc',
    'copyright',
    'title page',
    'titlepage',
    'illustrations',
    'publication information',
    'source credits',
    'publisher note',
    'editor note',
    'editorial note',
    'publisher',
    'preface to the edition',
  };

  static const Set<String> _bodyStartTitles = <String>{
    'preface',
    'introduction',
    'chapter 1',
    'chapter i',
    'chapter one',
    'part 1',
    'part i',
  };

  static bool isSectionFrontMatter({
    required String title,
    required String rawText,
  }) {
    final normalizedTitle = PioneerEpubFilteringNormalization.comparisonKey(
      title,
    );
    if (normalizedTitle.isEmpty) return true;
    if (_frontMatterTitles.contains(normalizedTitle)) return true;

    final normalizedText = PioneerEpubFilteringNormalization.collapseWhitespace(
      rawText,
    );
    if (normalizedText.isEmpty) return true;

    final lowerText = normalizedText.toLowerCase();
    if (lowerText.contains('adventist pioneer library')) return true;
    if (lowerText.contains('www.aplib.org')) return true;
    if (lowerText.contains('isbn:')) return true;
    if (lowerText.contains('published in the usa')) return true;
    if (lowerText.contains('originally published in')) return true;
    if (lowerText.contains('the original table of contents contained')) {
      return true;
    }
    if (lowerText.contains('support the ministry') ||
        lowerText.contains('donate') ||
        lowerText.contains('donation')) {
      return true;
    }
    if (RegExp(
      r'^©\s*\d{4}\s+adventist pioneer library$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    if (RegExp(
      r'^\+?\d[\d\s().-]{7,}$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    if (RegExp(
          r'^\d{1,5}\s+[A-Za-z][A-Za-z0-9 .,\-#/&()]*$',
          caseSensitive: false,
        ).hasMatch(normalizedText) &&
        (lowerText.contains('road') ||
            lowerText.contains('street') ||
            lowerText.contains('avenue') ||
            lowerText.contains('lane') ||
            lowerText.contains('drive') ||
            lowerText.contains('highway') ||
            lowerText.contains('oregon') ||
            lowerText.contains('usa') ||
            lowerText.contains('aplib'))) {
      return true;
    }
    if (RegExp(
      r'^(january|february|march|april|may|june|july|august|september|october|november|december),\s*\d{4}$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    return false;
  }

  static bool isBodyStartTitle(String title) {
    final normalizedTitle = PioneerEpubFilteringNormalization.comparisonKey(
      title,
    );
    return _bodyStartTitles.contains(normalizedTitle);
  }

  static List<String> filterLeadingFrontMatterParagraphs(
    List<String> paragraphs,
  ) {
    var firstBodyParagraphIndex = 0;
    var foundBodyParagraph = false;
    for (var i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i].trim();
      if (paragraph.isEmpty) continue;
      if (_looksLikeFrontMatterParagraph(paragraph)) {
        continue;
      }
      firstBodyParagraphIndex = i;
      foundBodyParagraph = true;
      break;
    }
    if (!foundBodyParagraph) {
      return const <String>[];
    }
    if (firstBodyParagraphIndex <= 0) {
      return List<String>.unmodifiable(paragraphs);
    }
    return List<String>.unmodifiable(
      paragraphs.sublist(firstBodyParagraphIndex),
    );
  }

  static bool _looksLikeFrontMatterParagraph(String text) {
    final normalizedText = PioneerEpubFilteringNormalization.collapseWhitespace(
      text,
    );
    if (normalizedText.isEmpty) return true;
    final lowerText = normalizedText.toLowerCase();
    if (lowerText.contains('adventist pioneer library')) return true;
    if (lowerText.contains('www.aplib.org')) return true;
    if (lowerText.contains('isbn:')) return true;
    if (lowerText.contains('published in the usa')) return true;
    if (lowerText.contains('originally published in')) return true;
    if (lowerText.contains('the original table of contents contained')) {
      return true;
    }
    if (RegExp(
      r'^©\s*\d{4}\s+adventist pioneer library$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    if (RegExp(
      r'^\+?\d[\d\s().-]{7,}$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    if (RegExp(
          r'^\d{1,5}\s+[A-Za-z][A-Za-z0-9 .,\-#/&()]*$',
          caseSensitive: false,
        ).hasMatch(normalizedText) &&
        (lowerText.contains('road') ||
            lowerText.contains('street') ||
            lowerText.contains('avenue') ||
            lowerText.contains('lane') ||
            lowerText.contains('drive') ||
            lowerText.contains('highway') ||
            lowerText.contains('oregon') ||
            lowerText.contains('usa') ||
            lowerText.contains('aplib'))) {
      return true;
    }
    return false;
  }
}

/// Current retention policy for public-domain EPUB parsing.
class PioneerEpubRetentionPolicy {
  const PioneerEpubRetentionPolicy._();

  static bool shouldSkipSection({
    required String title,
    required String rawText,
  }) => PioneerEpubFrontMatterClassifier.isSectionFrontMatter(
    title: title,
    rawText: rawText,
  );

  static List<String> filterLeadingFrontMatterParagraphs(
    List<String> paragraphs,
  ) => PioneerEpubFrontMatterClassifier.filterLeadingFrontMatterParagraphs(
    paragraphs,
  );
}

/// Current quality-validation policy for public-domain EPUB parsing.
class PioneerEpubQualityValidationPolicy {
  const PioneerEpubQualityValidationPolicy._();

  static bool isMeaningfulBodySection({
    required String title,
    required String rawText,
  }) => !PioneerEpubFrontMatterClassifier.isSectionFrontMatter(
    title: title,
    rawText: rawText,
  );
}

/// An already-classified authored XHTML block. Classification policy stays
/// with the caller; this model performs no source-profile selection.
class PioneerEpubContentBlock {
  const PioneerEpubContentBlock({
    required this.kind,
    required this.text,
    this.referenceCode,
  });

  final String kind;
  final String text;
  final String? referenceCode;
}

class PioneerEpubUnfilteredSection {
  const PioneerEpubUnfilteredSection({
    required this.href,
    required this.title,
    required this.paragraphs,
    required this.spineIndex,
  });

  final String href;
  final String title;
  final List<String> paragraphs;
  final int spineIndex;
}

/// Deterministically groups caller-classified blocks without skipping content.
class PioneerEpubSectionParser {
  const PioneerEpubSectionParser._();

  static List<PioneerEpubUnfilteredSection> sectionize({
    required Iterable<PioneerEpubContentBlock> blocks,
    required String fallbackTitle,
    required String baseHref,
    required int startingSpineIndex,
  }) {
    final sections = <PioneerEpubUnfilteredSection>[];
    var title = fallbackTitle;
    var index = startingSpineIndex;
    var number = 1;
    final paragraphs = <String>[];
    String href() => number == 1 ? baseHref : '$baseHref#section-$number';
    void flush() {
      if (paragraphs.isEmpty) return;
      sections.add(
        PioneerEpubUnfilteredSection(
          href: href(),
          title: title,
          paragraphs: List.unmodifiable(paragraphs),
          spineIndex: index++,
        ),
      );
      number++;
      paragraphs.clear();
      title = fallbackTitle;
    }

    for (final block in blocks) {
      if (block.kind == 'heading') {
        flush();
        title = block.text;
      } else if (block.text.trim().isNotEmpty) {
        paragraphs.add(block.text.trim());
      }
    }
    flush();
    return List.unmodifiable(sections);
  }
}

String? _opfPathFromContainer(ArchiveFile entry) {
  final xml = utf8.decode(entry.content as List<int>, allowMalformed: true);
  final raw = RegExp(
    r'full-path="([^"]+)"',
    caseSensitive: false,
  ).firstMatch(xml)?.group(1);
  return raw == null || raw.trim().isEmpty ? null : _normalizeEpubPath(raw);
}

Map<String, String> _manifest(String opfXml) {
  final result = <String, String>{};
  for (final match in RegExp(
    r'<item\b([^>]*)>',
    caseSensitive: false,
  ).allMatches(opfXml)) {
    final attributes = match.group(1) ?? '';
    final id = _attribute(attributes, 'id');
    final href = _attribute(attributes, 'href');
    if (id != null && href != null) {
      result[id] = href;
    }
  }
  return result;
}

List<String> _spineHrefs(
  String opfXml,
  Map<String, String> manifest,
  String opfPath,
) {
  final base = p.dirname(opfPath);
  final result = <String>[];
  for (final match in RegExp(
    r'<itemref\b([^>]*)>',
    caseSensitive: false,
  ).allMatches(opfXml)) {
    final idref = _attribute(match.group(1) ?? '', 'idref');
    final href = idref == null ? null : manifest[idref];
    if (href != null && href.trim().isNotEmpty) {
      result.add(_normalizeEpubPath(p.join(base, href)));
    }
  }
  return result;
}

String? _attribute(String attributes, String name) => RegExp(
  '$name\\s*=\\s*(["\\\'])(.*?)\\1',
  caseSensitive: false,
).firstMatch(attributes)?.group(2);

String _normalizeEpubPath(String value) =>
    p.normalize(value).replaceAll('\\', '/');

String _plainText(String value) => value
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
