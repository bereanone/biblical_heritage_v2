import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// The bytes of a cover image embedded in an EPUB's own manifest, plus the
/// file extension it should be saved with.
class EpubCoverImage {
  const EpubCoverImage({required this.bytes, required this.extension});

  final Uint8List bytes;

  /// Includes the leading dot, e.g. `.jpg`.
  final String extension;
}

/// Locates and extracts the cover image an EPUB itself declares via its OPF
/// manifest (`properties="cover-image"`, a `<meta name="cover">` reference,
/// a conventionally-named cover/titlepage file, or an `<img>` inside a
/// cover/titlepage/early-spine XHTML page). Returns `null` when the EPUB
/// declares no cover by any of those means — callers should treat that as
/// "this book has no embedded cover" rather than retrying with a different
/// heuristic.
class LibraryEpubCoverExtractor {
  const LibraryEpubCoverExtractor._();

  static EpubCoverImage? extractCoverImage(Uint8List epubBytes) {
    final archive = ZipDecoder().decodeBytes(epubBytes, verify: false);
    final packageInfo = _readEpubPackageInfo(archive);
    final coverHref = packageInfo.coverImagePath;
    if (coverHref == null || coverHref.trim().isEmpty) return null;

    final entry = packageInfo.findArchiveEntry(archive, coverHref);
    if (entry == null || !entry.isFile) return null;
    final content = entry.content as List<int>;
    if (content.isEmpty) return null;

    return EpubCoverImage(
      bytes: Uint8List.fromList(content),
      extension: _coverImageExtension(entry.name),
    );
  }

  static _EpubPackageInfo _readEpubPackageInfo(Archive archive) {
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

    return _EpubPackageInfo(coverImagePath: coverImagePath);
  }

  static String? _attributeValue(String tag, String name) {
    final match = RegExp(
      '$name="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1);
  }

  static String? _discoverCoverImagePath({
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

    final spineCandidates = <_EpubManifestItem>[];
    for (final item in manifest.values) {
      if (!item.href.toLowerCase().endsWith('.xhtml')) continue;
      spineCandidates.add(item);
    }
    spineCandidates.sort((left, right) {
      final leftName = p.basename(left.href).toLowerCase();
      final rightName = p.basename(right.href).toLowerCase();
      final leftScore = _coverFallbackScore(leftName);
      final rightScore = _coverFallbackScore(rightName);
      if (leftScore != rightScore) return leftScore.compareTo(rightScore);
      return left.href.compareTo(right.href);
    });

    for (final item in spineCandidates.take(4)) {
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

  static int _coverFallbackScore(String basename) {
    if (basename == 'cover.xhtml') return 0;
    if (basename == 'titlepage.xhtml') return 1;
    if (basename.startsWith('cover')) return 2;
    if (basename.startsWith('title')) return 3;
    return 4;
  }

  static bool _looksLikeCoverImagePath(String pathValue) {
    final lower = pathValue.toLowerCase();
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

  static bool _isImageExtension(String pathValue) {
    final ext = p.extension(pathValue).toLowerCase();
    return const <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
    }.contains(ext);
  }

  static String _coverImageExtension(String fileName) {
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
}

class _EpubPackageInfo {
  const _EpubPackageInfo({this.coverImagePath});

  final String? coverImagePath;

  ArchiveFile? findArchiveEntry(Archive archive, String pathValue) {
    final normalized = p.normalize(pathValue).toLowerCase();
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (p.normalize(file.name).toLowerCase() == normalized) {
        return file;
      }
    }
    return null;
  }
}

class _EpubManifestItem {
  const _EpubManifestItem({required this.href, required this.properties});

  final String href;
  final String properties;
}
