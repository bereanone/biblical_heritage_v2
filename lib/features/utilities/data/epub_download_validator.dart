import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Why a freshly downloaded EPUB candidate was rejected before it was
/// allowed to become the app-managed `.epub` file. Kept coarse-grained on
/// purpose: the downloader only needs to decide "unavailable" vs "retry
/// later" vs "corrupt", not render a diagnostic UI from this alone.
enum EpubDownloadRejectionReason {
  /// Response body was empty or too small to possibly be a zip.
  empty,

  /// Body does not start with a local-file-header/empty-archive zip
  /// signature — typically an HTML error page, a JSON error payload, or a
  /// login/challenge page saved with a `.epub` extension.
  notAZipFile,

  /// Zip signature was present but the archive could not be decoded (a
  /// truncated / interrupted download).
  corruptZip,

  /// Valid zip, but no `META-INF/container.xml` entry — not an EPUB
  /// package at all.
  missingContainerXml,

  /// `container.xml` did not resolve to a usable OPF rootfile path.
  unresolvableRootfile,

  /// The OPF path named by `container.xml` is not actually present in the
  /// archive. This is the exact shape EGW's media CDN returns for titles
  /// that only have a stub/teaser package: a container.xml that points at
  /// `OEBPS/content.opf`, but no such entry exists.
  missingOpf,

  /// OPF exists but has no `<manifest>` items.
  missingManifest,

  /// OPF exists but has no `<spine>` itemrefs.
  missingSpine,

  /// Every spine itemref pointed at a manifest item whose href is absent
  /// from the archive, or whose content has no extractable readable text.
  noReadableContent,

  /// An explicit expected title was supplied and the OPF title is clearly
  /// for a different work.
  titleMismatch,
}

class EpubDownloadValidationResult {
  const EpubDownloadValidationResult._({
    required this.isValid,
    this.rejectionReason,
    this.detail,
    this.opfTitle,
    this.spineItemCount = 0,
    this.readableContentCount = 0,
  });

  const EpubDownloadValidationResult.valid({
    required String opfTitle,
    required int spineItemCount,
    required int readableContentCount,
  }) : this._(
         isValid: true,
         opfTitle: opfTitle,
         spineItemCount: spineItemCount,
         readableContentCount: readableContentCount,
       );

  const EpubDownloadValidationResult.invalid({
    required EpubDownloadRejectionReason reason,
    required String detail,
    String? opfTitle,
    int spineItemCount = 0,
    int readableContentCount = 0,
  }) : this._(
         isValid: false,
         rejectionReason: reason,
         detail: detail,
         opfTitle: opfTitle,
         spineItemCount: spineItemCount,
         readableContentCount: readableContentCount,
       );

  final bool isValid;
  final EpubDownloadRejectionReason? rejectionReason;
  final String? detail;
  final String? opfTitle;
  final int spineItemCount;
  final int readableContentCount;

  /// True for rejection shapes that indicate the source itself has no real
  /// EPUB for this title (a structurally incomplete/placeholder package),
  /// as opposed to a transient network failure or file corruption. Callers
  /// use this to decide "mark unavailable" vs "treat as a failed/invalid
  /// download eligible for retry".
  bool get looksLikePlaceholder =>
      !isValid &&
      (rejectionReason == EpubDownloadRejectionReason.missingOpf ||
          rejectionReason == EpubDownloadRejectionReason.missingManifest ||
          rejectionReason == EpubDownloadRejectionReason.missingSpine ||
          rejectionReason == EpubDownloadRejectionReason.noReadableContent);
}

/// Validates raw downloaded bytes before they are ever allowed to become an
/// app-managed `.epub` file. Every check here is structural (zip / OPF /
/// spine / readable content); nothing here activates canonical import — see
/// `LibraryDocumentCanonicalizer` for that, which runs only after a file
/// passes this validator and is safely on disk.
class EpubDownloadValidator {
  const EpubDownloadValidator._();

  static const int _minPlausibleZipBytes =
      22; // smallest possible EOCD-only zip

  static EpubDownloadValidationResult validate(
    Uint8List bytes, {
    String? expectedTitle,
  }) {
    if (bytes.isEmpty) {
      return const EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.empty,
        detail: 'Response body was empty.',
      );
    }
    if (bytes.length < _minPlausibleZipBytes || !_hasZipSignature(bytes)) {
      return EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.notAZipFile,
        detail:
            'Response does not start with a zip signature (${bytes.length} bytes); '
            'likely an HTML/JSON error page or redirect saved with a .epub extension.',
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (e) {
      return EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.corruptZip,
        detail: 'Zip could not be decoded (truncated/corrupt download): $e',
      );
    }

    final containerEntry = _findEntry(archive, 'META-INF/container.xml');
    if (containerEntry == null) {
      return const EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.missingContainerXml,
        detail: 'Archive has no META-INF/container.xml; not an EPUB package.',
      );
    }

    final containerXml = _decodeText(containerEntry);
    final rootfilePath = _extractRootfilePath(containerXml);
    if (rootfilePath == null || rootfilePath.isEmpty) {
      return const EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.unresolvableRootfile,
        detail: 'container.xml has no resolvable <rootfile full-path="...">.',
      );
    }

    final opfEntry = _findEntry(archive, rootfilePath);
    if (opfEntry == null) {
      return EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.missingOpf,
        detail:
            'container.xml references "$rootfilePath" but no such entry exists '
            'in the archive — this is a placeholder/teaser package, not a full EPUB.',
      );
    }

    final opfXml = _decodeText(opfEntry);
    final opfTitle = _extractOpfTitle(opfXml);
    final opfDir = _dirName(rootfilePath);

    if (expectedTitle != null &&
        expectedTitle.trim().isNotEmpty &&
        opfTitle != null &&
        opfTitle.trim().isNotEmpty &&
        !_titlesPlausiblyMatch(opfTitle, expectedTitle)) {
      return EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.titleMismatch,
        detail:
            'OPF title "$opfTitle" does not match requested title "$expectedTitle".',
        opfTitle: opfTitle,
      );
    }

    final manifestItems = _extractManifestItems(opfXml);
    if (manifestItems.isEmpty) {
      return EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.missingManifest,
        detail: 'OPF has no usable <manifest> <item> entries.',
        opfTitle: opfTitle,
      );
    }

    final spineIdrefs = _extractSpineIdrefs(opfXml);
    if (spineIdrefs.isEmpty) {
      return EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.missingSpine,
        detail: 'OPF has no usable <spine> <itemref> entries.',
        opfTitle: opfTitle,
      );
    }

    var readableContentCount = 0;
    for (final idref in spineIdrefs) {
      final href = manifestItems[idref];
      if (href == null || href.isEmpty) continue;
      final resolvedPath = _joinEpubPath(opfDir, href);
      final contentEntry = _findEntry(archive, resolvedPath);
      if (contentEntry == null) continue;
      final text = _stripTags(_decodeText(contentEntry));
      if (text.trim().length >= 10) {
        readableContentCount += 1;
      }
    }

    if (readableContentCount == 0) {
      return EpubDownloadValidationResult.invalid(
        reason: EpubDownloadRejectionReason.noReadableContent,
        detail:
            'No spine item resolved to an archive entry with readable text content.',
        opfTitle: opfTitle,
        spineItemCount: spineIdrefs.length,
      );
    }

    return EpubDownloadValidationResult.valid(
      opfTitle: opfTitle ?? '',
      spineItemCount: spineIdrefs.length,
      readableContentCount: readableContentCount,
    );
  }

  static bool _hasZipSignature(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // Local file header "PK\x03\x04", empty-archive EOCD "PK\x05\x06", or
    // spanned-archive marker "PK\x07\x08" are the only valid starts for a
    // zip stream we'd ever accept as a fresh download.
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        ((bytes[2] == 0x03 && bytes[3] == 0x04) ||
            (bytes[2] == 0x05 && bytes[3] == 0x06) ||
            (bytes[2] == 0x07 && bytes[3] == 0x08));
  }

  static ArchiveFile? _findEntry(Archive archive, String path) {
    final normalized = _normalizePath(path);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (_normalizePath(file.name) == normalized) return file;
    }
    return null;
  }

  static String _normalizePath(String path) {
    return path.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  }

  static String _decodeText(ArchiveFile entry) {
    final content = entry.content as List<int>;
    return utf8.decode(content, allowMalformed: true);
  }

  static String? _extractRootfilePath(String containerXml) {
    final match = RegExp(
      r'''<rootfile\b[^>]*\bfull-path\s*=\s*(["'])([^"']+)\1''',
      caseSensitive: false,
    ).firstMatch(containerXml);
    return match?.group(2)?.trim();
  }

  static String? _extractOpfTitle(String opfXml) {
    final match = RegExp(
      r'<dc:title[^>]*>(.*?)</dc:title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(opfXml);
    if (match == null) return null;
    return _stripTags(match.group(1) ?? '').trim();
  }

  /// Maps manifest item id -> href.
  static Map<String, String> _extractManifestItems(String opfXml) {
    final manifestMatch = RegExp(
      r'<manifest\b[^>]*>(.*?)</manifest>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(opfXml);
    if (manifestMatch == null) return const <String, String>{};
    final manifestBody = manifestMatch.group(1) ?? '';
    final items = <String, String>{};
    for (final itemMatch in RegExp(
      r'<item\b([^>]*)/?>',
      caseSensitive: false,
    ).allMatches(manifestBody)) {
      final attrs = itemMatch.group(1) ?? '';
      final id = _extractAttr(attrs, 'id');
      final href = _extractAttr(attrs, 'href');
      if (id != null && href != null && id.isNotEmpty && href.isNotEmpty) {
        items[id] = href;
      }
    }
    return items;
  }

  static List<String> _extractSpineIdrefs(String opfXml) {
    final spineMatch = RegExp(
      r'<spine\b[^>]*>(.*?)</spine>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(opfXml);
    if (spineMatch == null) return const <String>[];
    final spineBody = spineMatch.group(1) ?? '';
    final idrefs = <String>[];
    for (final itemrefMatch in RegExp(
      r'<itemref\b([^>]*)/?>',
      caseSensitive: false,
    ).allMatches(spineBody)) {
      final attrs = itemrefMatch.group(1) ?? '';
      final idref = _extractAttr(attrs, 'idref');
      if (idref != null && idref.isNotEmpty) {
        idrefs.add(idref);
      }
    }
    return idrefs;
  }

  static String? _extractAttr(String attrs, String name) {
    final match = RegExp(
      '''$name\\s*=\\s*(["'])([^"']*)\\1''',
      caseSensitive: false,
    ).firstMatch(attrs);
    return match?.group(2);
  }

  static String _dirName(String path) {
    final normalized = _normalizePath(path);
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? '' : normalized.substring(0, slash);
  }

  static String _joinEpubPath(String dir, String href) {
    final cleanHref = href.split('#').first.trim();
    if (dir.isEmpty) return _normalizePath(cleanHref);
    if (cleanHref.startsWith('/')) return _normalizePath(cleanHref);
    return _normalizePath('$dir/$cleanHref');
  }

  static String _stripTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'&[a-zA-Z#0-9]+;'), ' ');
  }

  /// Word-level, order-independent overlap check. Catalog titles and OPF
  /// titles for the same real work routinely differ in word order, a
  /// trailing "(EGW)"/leading "EGW", singular/plural, or minor OCR'd
  /// wording ("Testimony" vs "Testimony[sic: Foe]") — none of that means the
  /// package is wrong. This only rejects when the two titles share no
  /// meaningful content words at all, which is what an actually-unrelated
  /// or actually-wrong package looks like.
  static bool _titlesPlausiblyMatch(String opfTitle, String expectedTitle) {
    // Catalog "titles" are sometimes just the bare book code (e.g. "10MR",
    // "SHM-apx") with no real display title seeded — never real prose, and
    // real prose titles always contain whitespace, so this is a reliable
    // way to tell "nothing to compare" apart from an actual title.
    if (!expectedTitle.trim().contains(RegExp(r'\s'))) return true;
    final expectedTokens = _titleTokens(expectedTitle);
    if (expectedTokens.length < 2) return true;
    final opfTokens = _titleTokens(opfTitle);
    if (opfTokens.isEmpty) return true;
    final overlap = expectedTokens.intersection(opfTokens).length;
    if (overlap == 0) return false;
    return overlap / expectedTokens.length >= 0.2;
  }

  static const Set<String> _titleStopwords = <String>{
    'a',
    'an',
    'and',
    'the',
    'of',
    'for',
    'to',
    'in',
    'on',
    'our',
    'no',
  };

  static Set<String> _titleTokens(String value) {
    return value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length > 1 && !_titleStopwords.contains(token))
        .toSet();
  }
}
