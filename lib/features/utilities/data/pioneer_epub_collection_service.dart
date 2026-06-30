import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import 'pioneer_ellenwhite_audio_service.dart';
import 'pioneer_source_catalog.dart';

typedef PioneerEpubCollectionFetcher = Future<Uint8List> Function(Uri uri);

class PioneerEpubCollectionService {
  PioneerEpubCollectionService({
    PioneerEpubCollectionFetcher? fetcher,
    Future<String> Function()? cacheRootPathResolver,
    Future<PioneerSourceCatalog> Function()? catalogLoader,
    Future<PioneerSourceCatalog> Function(bool refresh)? directCatalogLoader,
  }) : _fetcher = fetcher ?? _downloadBytes,
       _cacheRootPathResolver =
           cacheRootPathResolver ?? _defaultCacheRootPathResolver,
       _catalogLoader = catalogLoader ?? PioneerSourceCatalog.load,
       _directCatalogLoader =
           directCatalogLoader ??
           ((refresh) => PioneerEllenWhiteAudioService.instance.loadCatalog(
             refresh: refresh,
           ));

  static final PioneerEpubCollectionService instance =
      PioneerEpubCollectionService();

  static final Uri collectionUri = Uri.parse(
    'https://adventaudio.org/files/ebooks/zip/Epub.zip',
  );
  static const String collectionPageUrl =
      'https://www.aplib.org/resources/pioneers-ebooks/';

  final PioneerEpubCollectionFetcher _fetcher;
  final Future<String> Function() _cacheRootPathResolver;
  final Future<PioneerSourceCatalog> Function() _catalogLoader;
  final Future<PioneerSourceCatalog> Function(bool refresh)
  _directCatalogLoader;

  Future<PioneerSourceCatalog> loadCatalog({bool refresh = false}) async {
    final archiveBytes = await _loadArchiveBytes(refresh: refresh);
    final archive = ZipDecoder().decodeBytes(archiveBytes, verify: false);
    final archiveCatalog = _buildCatalog(archive);
    final directCatalog = await _directCatalogLoader(refresh);
    final curatedCatalog = await _catalogLoader();
    final zipEntryCatalog = PioneerSourceCatalog.merge([
      archiveCatalog,
      directCatalog,
      curatedCatalog,
    ]);
    return zipEntryCatalog.validateZipEntries(
      archive.files
          .where(
            (entry) =>
                entry.isFile &&
                p.normalize(entry.name).toLowerCase().endsWith('.epub'),
          )
          .map((entry) => p.normalize(entry.name)),
    );
  }

  Future<Uint8List> _loadArchiveBytes({bool refresh = false}) async {
    final cacheFile = await _cacheFile();
    if (!refresh && await cacheFile.exists()) {
      return cacheFile.readAsBytes();
    }

    final bytes = await _fetcher(collectionUri);
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsBytes(bytes, flush: true);
    return bytes;
  }

  Future<File> _cacheFile() async {
    final root = await _cacheRootPathResolver();
    return File(
      p.join(root, 'eLibrary_Downloads', 'Pioneer', 'pioneers_ebooks_epub.zip'),
    );
  }

  PioneerSourceCatalog _buildCatalog(Archive archive) {
    final totalArchiveEntryCount = archive.files.length;
    final epubEntries =
        archive.files
            .where(
              (entry) =>
                  entry.isFile &&
                  p.normalize(entry.name).toLowerCase().endsWith('.epub'),
            )
            .toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));

    final authorMap = <String, _AuthorGroup>{};
    final seenWorkIds = <String>{};
    final authorEntryCounts = <String, int>{};
    var unknownAuthorCount = 0;
    var duplicateEntriesSkipped = 0;
    for (final entry in epubEntries) {
      final descriptor = _describeEntry(entry.name);
      final workId = pioneerSourceWorkIdentityKey(
        provider: 'aplib',
        authorName: descriptor.authorName,
        title: descriptor.title,
        sourceType: 'epub',
        zipEntry: p.normalize(entry.name),
        sourceUrl: collectionUri.toString(),
      );
      if (!seenWorkIds.add(workId)) {
        duplicateEntriesSkipped += 1;
        continue;
      }
      final authorKey = _stableId(descriptor.authorName);
      final group = authorMap.putIfAbsent(
        authorKey,
        () => _AuthorGroup(
          id: authorKey,
          name: descriptor.authorName,
          sortKey: descriptor.authorName.toLowerCase(),
        ),
      );
      authorEntryCounts[group.name] = (authorEntryCounts[group.name] ?? 0) + 1;
      if (descriptor.needsReview) {
        unknownAuthorCount += 1;
      }
      group.works.add(
        PioneerSourceWork(
          id: workId,
          authorId: group.id,
          authorName: group.name,
          sourceFamily: 'Adventist Pioneer Library',
          title: descriptor.title,
          abbreviation: _abbreviationForTitle(descriptor.title),
          group: 'Pioneer Authors',
          subgroup: descriptor.needsReview ? 'Needs review' : 'EPUB',
          availability: descriptor.needsReview
              ? PioneerSourceAvailability.sourceNeeded
              : PioneerSourceAvailability.available,
          verified: !descriptor.needsReview,
          catalogImportable: !descriptor.needsReview,
          sourceType: 'epub',
          sourceUrl: collectionUri.toString(),
          collectionUrl: collectionPageUrl,
          captureUrl: null,
          readerUrl: null,
          directFileUrl: null,
          directFileType: null,
          sourceLabel: 'APLIB',
          notes: descriptor.needsReview
              ? 'Needs review • Source file: ${descriptor.sourceFileName}'
              : null,
          sourceCandidates: [
            PioneerSourceCandidate(
              provider: 'aplib',
              sourceType: 'epubZipEntry',
              url: collectionUri.toString(),
              zipEntry: p.normalize(entry.name),
              priority: 10,
              qualityTier: 'epub',
              availability: descriptor.needsReview
                  ? PioneerSourceAvailability.sourceNeeded
                  : PioneerSourceAvailability.available,
              notes: descriptor.needsReview
                  ? 'Needs review • Source file: ${descriptor.sourceFileName}'
                  : null,
            ),
          ],
        ),
      );
    }

    final authors = authorMap.values.toList(growable: false)
      ..sort((left, right) {
        final compare = left.sortKey.compareTo(right.sortKey);
        if (compare != 0) return compare;
        return left.name.compareTo(right.name);
      });

    return PioneerSourceCatalog(
      authors: List<PioneerSourceAuthor>.unmodifiable(
        authors
            .map(
              (group) => PioneerSourceAuthor(
                id: group.id,
                name: group.name,
                sourceFamily: 'Adventist Pioneer Library',
                works: List<PioneerSourceWork>.unmodifiable(
                  group.works..sort((a, b) => a.title.compareTo(b.title)),
                ),
                sortKey: group.sortKey,
              ),
            )
            .toList(growable: false),
      ),
      authorsById: Map<String, PioneerSourceAuthor>.unmodifiable({
        for (final group in authors)
          group.id: PioneerSourceAuthor(
            id: group.id,
            name: group.name,
            sourceFamily: 'Adventist Pioneer Library',
            works: List<PioneerSourceWork>.unmodifiable(
              group.works..sort((a, b) => a.title.compareTo(b.title)),
            ),
            sortKey: group.sortKey,
          ),
      }),
      worksById: Map<String, PioneerSourceWork>.unmodifiable({
        for (final group in authors)
          for (final work in group.works) work.id: work,
      }),
      diagnostics: PioneerEpubCollectionDiagnostics(
        totalArchiveEntryCount: totalArchiveEntryCount,
        epubEntryCount: epubEntries.length,
        authorCount: authors.length,
        unknownAuthorCount: unknownAuthorCount,
        duplicateEntriesSkipped: duplicateEntriesSkipped,
        authorEntryCounts: Map<String, int>.unmodifiable(authorEntryCounts),
      ),
    );
  }
}

class _AuthorGroup {
  _AuthorGroup({required this.id, required this.name, required this.sortKey});

  final String id;
  final String name;
  final String sortKey;
  final List<PioneerSourceWork> works = <PioneerSourceWork>[];
}

class _EntryDescriptor {
  const _EntryDescriptor({
    required this.authorName,
    required this.title,
    required this.needsReview,
    required this.sourceFileName,
  });

  final String authorName;
  final String title;
  final bool needsReview;
  final String sourceFileName;
}

String _abbreviationForTitle(String title) {
  final words = title
      .split(RegExp(r'\s+'))
      .where((word) => word.trim().isNotEmpty)
      .take(4)
      .map((word) => word.substring(0, 1).toUpperCase())
      .join();
  return words.isEmpty ? 'EPUB' : words;
}

_EntryDescriptor _describeEntry(String entryName) {
  final normalizedName = p.normalize(entryName);
  final segments = normalizedName.split('/');
  final baseName = p
      .basenameWithoutExtension(entryName)
      .replaceAll('_', ' ')
      .trim();
  if (baseName.isEmpty) {
    return const _EntryDescriptor(
      authorName: 'Needs review',
      title: 'Unknown EPUB',
      needsReview: true,
      sourceFileName: '',
    );
  }

  final sourceFileName = p.basename(normalizedName);
  final title = _titleFromEntryBase(baseName);
  if (segments.length < 3 || segments[1].trim().isEmpty) {
    return _EntryDescriptor(
      authorName: 'Needs review',
      title: title,
      needsReview: true,
      sourceFileName: sourceFileName,
    );
  }

  final authorFolder = segments[1];
  final inferred = _canonicalizeAuthorFolder(authorFolder);
  return _EntryDescriptor(
    authorName: inferred.name,
    title: title,
    needsReview: inferred.needsReview,
    sourceFileName: sourceFileName,
  );
}

String _titleFromEntryBase(String baseName) {
  final delimiter = RegExp(r'\s+[–—-]\s+');
  final parts = baseName.split(delimiter);
  if (parts.length >= 2) {
    return _cleanTitle(parts.sublist(1).join(' - '));
  }
  return _cleanTitle(baseName);
}

class _CanonicalAuthor {
  const _CanonicalAuthor({required this.name, required this.needsReview});

  final String name;
  final bool needsReview;
}

_CanonicalAuthor _canonicalizeAuthorFolder(String rawAuthorFolder) {
  final normalized = rawAuthorFolder
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.isEmpty) {
    return const _CanonicalAuthor(name: 'Needs review', needsReview: true);
  }

  if (normalized.contains('modern') || normalized.contains('bischoff')) {
    return const _CanonicalAuthor(name: 'Needs review', needsReview: true);
  }

  const canonicalMap = <String, String>{
    'smith': 'Uriah Smith',
    'annie smith': 'Annie Smith',
    'rebekah smith': 'Rebekah Smith',
    'andrews': 'J. N. Andrews',
    'bates': 'Joseph Bates',
    'bliss': 'Sylvester Bliss',
    'bordeau': 'D. T. Bordeau',
    'butler': 'G. I. Butler',
    'cornell': 'M. E. Cornell',
    'cottrell': 'R. F. Cottrell',
    'crosier': 'O. R. L. Crosier',
    'daniells': 'A. G. Daniells',
    'fitch': 'Charles Fitch',
    'foy': 'William E. Foy',
    'hale': 'Apollos Hale',
    'haskell': 'S. N. Haskell',
    'james white': 'James White',
    'jones': 'A. T. Jones',
    'litch': 'Josiah Litch',
    'loughborough': 'J. N. Loughborough',
    'miller': 'William Miller',
    'preble': 'T. M. Preble',
    'prescott': 'W. W. Prescott',
    'snow': 'Samuel Snow',
    'sutherland': 'W. A. Sutherland',
    'waggoner ej': 'E. J. Waggoner',
    'waggoner jh': 'J. H. Waggoner',
  };
  final canonicalName = canonicalMap[normalized];
  if (canonicalName != null) {
    return _CanonicalAuthor(name: canonicalName, needsReview: false);
  }

  return _CanonicalAuthor(
    name: _cleanTitle(rawAuthorFolder),
    needsReview: false,
  );
}

String _cleanTitle(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String _stableId(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

Future<Uint8List> _downloadBytes(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'StudyBible2 Pioneer Library Import',
    );
    final response = await request.close();
    final bytes = await consolidateHttpClientResponseBytes(response);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        'Unexpected HTTP ${response.statusCode} downloading $uri',
      );
    }
    return Uint8List.fromList(bytes);
  } finally {
    client.close(force: true);
  }
}

Future<String> _defaultCacheRootPathResolver() async {
  final accessible = await LibraryRootService.instance
      .accessibleLibraryRootPath();
  if (accessible != null && accessible.trim().isNotEmpty) {
    return accessible;
  }
  return LibraryRootService.instance.defaultAppLibraryRootPath();
}
