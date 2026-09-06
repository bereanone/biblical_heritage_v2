import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/data/pioneer_epub_collection_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';

Uint8List _zipBytes(Iterable<MapEntry<String, List<int>>> files) {
  final archive = Archive();
  for (final entry in files) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

PioneerSourceCatalog _emptyCatalog() {
  return PioneerSourceCatalog.fromJson({'authors': []});
}

PioneerSourceCatalog _curatedMergeCatalog() {
  return PioneerSourceCatalog.fromJson({
    'authors': [
      {
        'author_id': 'uriah_smith',
        'author_name': 'Uriah Smith',
        'source_family': 'Pioneer',
        'sort_key': 'uriah smith',
        'works': [
          {
            'work_id': 'daniel_and_the_revelation',
            'title': 'Daniel and the Revelation',
            'abbreviation': 'DAR',
            'edition_label': '1897',
            'edition_year': 1897,
            'group': 'Pioneer Authors',
            'subgroup': 'Prophecy',
            'availability_status': 'source_needed',
            'source_type': 'epub',
            'source_family': 'AdventAudio',
            'collection_url':
                'https://www.aplib.org/resources/pioneers-ebooks/',
            'source_label': 'EGW Audio / AdventAudio',
            'verified': true,
            'importable': true,
            'source_candidates': [
              {
                'provider': 'adventaudio',
                'source_type': 'epub',
                'edition_label': '1897',
                'edition_year': 1897,
                'priority': 5,
                'quality_tier': 'epub',
                'availability': 'source_needed',
                'notes': 'EGW Audio / AdventAudio DAR 1897 EPUB URL needed.',
              },
              {
                'provider': 'aplib',
                'source_type': 'epubZipEntry',
                'url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
                'zip_entry': 'Epub/Smith/Daniel and the Revelation.epub',
                'edition_label': '1897',
                'edition_year': 1897,
                'priority': 10,
                'quality_tier': 'epub',
                'availability': 'available',
              },
              {
                'provider': 'egwWritings',
                'source_type': 'readerPage',
                'url': 'https://egwwritings.org/read?panels=p1297.2&index=0',
                'edition_label': '1897',
                'edition_year': 1897,
                'priority': 50,
                'quality_tier': 'reader',
                'availability': 'available',
              },
            ],
          },
          {
            'work_id': 'the_adventaudio_only_work',
            'title': 'The AdventAudio Only Work',
            'abbreviation': 'AAW',
            'group': 'Pioneer Authors',
            'subgroup': 'Prophecy',
            'availability_status': 'available',
            'source_type': 'epub',
            'source_family': 'AdventAudio',
            'collection_url':
                'https://www.aplib.org/resources/pioneers-ebooks/',
            'source_label': 'EGW Audio / AdventAudio',
            'verified': true,
            'importable': true,
            'source_candidates': [
              {
                'provider': 'adventaudio',
                'source_type': 'epub',
                'url': 'https://example.com/adventaudio-only.epub',
                'priority': 5,
                'quality_tier': 'epub',
                'availability': 'available',
              },
            ],
          },
        ],
      },
    ],
  });
}

PioneerSourceCatalog _directEllenWhiteAudioCatalog() {
  return PioneerSourceCatalog.fromJson({
    'authors': [
      {
        'author_id': 'uriah_smith',
        'author_name': 'Uriah Smith',
        'source_family': 'EllenWhiteAudio',
        'sort_key': 'uriah smith',
        'works': [
          {
            'work_id': 'daniel_and_the_revelation',
            'title': 'Daniel and the Revelation',
            'abbreviation': '',
            'group': 'Pioneer Authors',
            'subgroup': 'Pioneer',
            'availability_status': 'available',
            'source_type': 'directEpub',
            'source_family': 'EllenWhiteAudio',
            'collection_url':
                'https://ellenwhiteaudio.org/ebooks-of-the-pioneers/',
            'source_label': 'EllenWhiteAudio',
            'verified': true,
            'importable': true,
            'source_candidates': [
              {
                'provider': 'ellenwhiteaudio',
                'source_type': 'directEpub',
                'url':
                    'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel%20and%20the%20Revelation.epub',
                'priority': 1,
                'quality_tier': 'epub',
                'availability': 'available',
              },
            ],
          },
        ],
      },
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds authors and works from epub folders and reuses cache', () async {
    var fetchCount = 0;
    final cacheRoot = await Directory.systemTemp.createTemp(
      'pioneer_epub_collection_cache_',
    );
    addTearDown(() async {
      if (cacheRoot.existsSync()) {
        await cacheRoot.delete(recursive: true);
      }
    });

    final service = PioneerEpubCollectionService(
      fetcher: (uri) async {
        fetchCount += 1;
        return _zipBytes([
          MapEntry('Epub/Smith/Daniel and the Revelation.epub', [1, 2, 3, 4]),
          MapEntry('Epub/Smith/Mortal or Immortal? Which.epub', [5, 6, 7, 8]),
          MapEntry('Epub/Andrews/History of the Sabbath.epub', [9, 10, 11, 12]),
          MapEntry('Epub/Jones/The American Sentinel (1890).epub', [
            13,
            14,
            15,
            16,
          ]),
          MapEntry('Epub/Waggoner EJ/Christ and His Righteousness.epub', [
            17,
            18,
            19,
            20,
          ]),
          MapEntry('Epub/Ellen G. White - Keep the Sabbath Holy.epub', [
            21,
            22,
            23,
            24,
          ]),
        ]);
      },
      cacheRootPathResolver: () async => cacheRoot.path,
      catalogLoader: () async => _curatedMergeCatalog(),
      directCatalogLoader: (_) async => _emptyCatalog(),
      localCatalogLoader: () async => _emptyCatalog(),
    );

    final catalog = await service.loadCatalog();
    expect(fetchCount, 1);
    expect(catalog.authorCount, 5);
    expect(catalog.workCount, 7);
    expect(catalog.authorById('uriah_smith'), isNotNull);
    expect(catalog.authorById('j_n_andrews'), isNotNull);
    expect(catalog.authorById('a_t_jones'), isNotNull);
    expect(catalog.authorById('e_j_waggoner'), isNotNull);
    expect(catalog.authorById('needs_review'), isNotNull);

    final danielAndTheRevelation = catalog.works.firstWhere(
      (work) => work.title == 'Daniel and the Revelation',
    );
    final historyOfTheSabbath = catalog.works.firstWhere(
      (work) => work.title == 'History of the Sabbath',
    );
    final adventAudioOnly = catalog.works.firstWhere(
      (work) => work.title == 'The AdventAudio Only Work',
    );
    final keepTheSabbathHoly = catalog.works.firstWhere(
      (work) => work.title == 'Keep the Sabbath Holy',
    );

    expect(
      danielAndTheRevelation.id,
      startsWith('aplib_uriah_smith_daniel_and_the_revelation_epub_'),
    );
    expect(danielAndTheRevelation.authorName, 'Uriah Smith');
    expect(danielAndTheRevelation.sourceCandidates.length, 3);
    expect(danielAndTheRevelation.preferredImportCandidate, isNotNull);
    expect(danielAndTheRevelation.preferredImportCandidate!.provider, 'aplib');
    expect(
      danielAndTheRevelation.alternateSourceCandidates.any(
        (candidate) => candidate.provider == 'adventaudio',
      ),
      isTrue,
    );
    expect(danielAndTheRevelation.hasDeferredPdfSource, isFalse);
    expect(historyOfTheSabbath.id, startsWith('aplib_j_n_andrews_'));
    expect(adventAudioOnly.id, 'the_adventaudio_only_work');
    expect(adventAudioOnly.preferredImportCandidate, isNotNull);
    expect(
      keepTheSabbathHoly.id,
      startsWith('aplib_needs_review_keep_the_sabbath_holy_epub_'),
    );
    expect(keepTheSabbathHoly.notes, contains('Needs review'));
    expect(keepTheSabbathHoly.notes, contains('Source file:'));
    expect(catalog.diagnostics, isNotNull);
    expect(catalog.diagnostics!.totalArchiveEntryCount, 6);
    expect(catalog.diagnostics!.epubEntryCount, 6);
    expect(catalog.diagnostics!.authorCount, catalog.authorCount);
    expect(catalog.diagnostics!.unknownAuthorCount, 1);
    expect(catalog.diagnostics!.duplicateEntriesSkipped, 0);
    expect(catalog.diagnostics!.topAuthorCounts().first.value, 2);

    final cachedCatalog = await service.loadCatalog();
    expect(fetchCount, 1);
    expect(cachedCatalog.workCount, 7);
    expect(cachedCatalog.authorCount, catalog.authorCount);
  });

  test(
    'prefers EllenWhiteAudio direct EPUB over the missing APLIB ZIP entry',
    () async {
      final cacheRoot = await Directory.systemTemp.createTemp(
        'pioneer_epub_collection_cache_direct_',
      );
      addTearDown(() async {
        if (cacheRoot.existsSync()) {
          await cacheRoot.delete(recursive: true);
        }
      });

      final service = PioneerEpubCollectionService(
        fetcher: (uri) async {
          return _zipBytes([
            MapEntry('Epub/Smith/Daniel and the Revelation.epub', [1, 2, 3, 4]),
          ]);
        },
        cacheRootPathResolver: () async => cacheRoot.path,
        catalogLoader: () async => _curatedMergeCatalog(),
        directCatalogLoader: (_) async => _directEllenWhiteAudioCatalog(),
        localCatalogLoader: () async => _emptyCatalog(),
      );

      final catalog = await service.loadCatalog(refresh: true);
      final uriahSmith = catalog.authorById('uriah_smith');
      final darWorks =
          uriahSmith?.works
              .where((work) => work.title == 'Daniel and the Revelation')
              .toList(growable: false) ??
          const <PioneerSourceWork>[];
      expect(darWorks, hasLength(1));
      final danielAndTheRevelation = darWorks.single;

      expect(danielAndTheRevelation, isNotNull);
      expect(danielAndTheRevelation.title, 'Daniel and the Revelation');
      expect(danielAndTheRevelation.authorName, 'Uriah Smith');
      expect(danielAndTheRevelation.preferredImportCandidate, isNotNull);
      expect(
        danielAndTheRevelation.preferredImportCandidate!.provider,
        'ellenwhiteaudio',
      );
      expect(danielAndTheRevelation.isImportable, isTrue);
      expect(danielAndTheRevelation.sourceTypeLabel, 'EGW Reader Capture');
      expect(
        danielAndTheRevelation.sourceCandidates.any(
          (candidate) =>
              candidate.provider == 'aplib' &&
              candidate.sourceType == 'epubZipEntry',
        ),
        isTrue,
      );
      expect(
        danielAndTheRevelation.sourceCandidates.any(
          (candidate) =>
              candidate.provider == 'ellenwhiteaudio' &&
              candidate.sourceType == 'directEpub',
        ),
        isTrue,
      );
    },
  );

  test(
    'downgrades missing APLIB ZIP entries when the archive lacks them',
    () async {
      final cacheRoot = await Directory.systemTemp.createTemp(
        'pioneer_epub_collection_cache_missing_zip_',
      );
      addTearDown(() async {
        if (cacheRoot.existsSync()) {
          await cacheRoot.delete(recursive: true);
        }
      });

      final service = PioneerEpubCollectionService(
        fetcher: (uri) async {
          return _zipBytes([
            MapEntry('Epub/Smith/Poems, by Uriah Smith.epub', [1, 2, 3, 4]),
          ]);
        },
        cacheRootPathResolver: () async => cacheRoot.path,
        catalogLoader: () async => _curatedMergeCatalog(),
        directCatalogLoader: (_) async => _emptyCatalog(),
        localCatalogLoader: () async => _emptyCatalog(),
      );

      final catalog = await service.loadCatalog(refresh: true);
      final dar = catalog.workById('daniel_and_the_revelation');

      expect(dar, isNotNull);
      expect(dar!.availability, PioneerSourceAvailability.sourceNeeded);
      expect(dar.catalogImportable, isFalse);
      expect(dar.isImportable, isFalse);
      expect(dar.preferredImportCandidate, isNull);
      expect(
        dar.sourceCandidates
            .firstWhere((candidate) => candidate.provider == 'aplib')
            .availability,
        PioneerSourceAvailability.sourceNeeded,
      );
      expect(
        catalog.importableWorks.map((work) => work.title),
        isNot(contains('Daniel and the Revelation')),
      );
      expect(
        catalog.sourceNeededWorks.map((work) => work.title),
        contains('Daniel and the Revelation'),
      );
    },
  );

  test(
    'keeps same-title EPUB entries distinct when their source identity differs',
    () async {
      final cacheRoot = await Directory.systemTemp.createTemp(
        'pioneer_epub_collection_cache_identity_',
      );
      addTearDown(() async {
        if (cacheRoot.existsSync()) {
          await cacheRoot.delete(recursive: true);
        }
      });

      final service = PioneerEpubCollectionService(
        fetcher: (uri) async {
          return _zipBytes([
            MapEntry('Set A/Smith/Mortal or Immortal? Which.epub', [
              1,
              2,
              3,
              4,
            ]),
            MapEntry('Set B/Smith/Mortal or Immortal? Which.epub', [
              5,
              6,
              7,
              8,
            ]),
          ]);
        },
        cacheRootPathResolver: () async => cacheRoot.path,
        catalogLoader: () async => _emptyCatalog(),
        directCatalogLoader: (_) async => _emptyCatalog(),
        localCatalogLoader: () async => _emptyCatalog(),
      );

      final catalog = await service.loadCatalog(refresh: true);
      final uriahSmith = catalog.authorById('uriah_smith');

      expect(catalog.authorCount, 1);
      expect(catalog.workCount, 2);
      expect(uriahSmith, isNotNull);
      expect(uriahSmith!.works.length, 2);
      expect(
        uriahSmith.works.every(
          (work) => work.title == 'Mortal or Immortal? Which',
        ),
        isTrue,
      );
      expect(uriahSmith.works.map((work) => work.id).toSet().length, 2);
      expect(
        uriahSmith.works.first.id,
        startsWith('aplib_uriah_smith_mortal_or_immortal_which_epub_'),
      );
      expect(catalog.diagnostics!.duplicateEntriesSkipped, 0);
    },
  );

  test('dedupes exact duplicate source identities', () async {
    final cacheRoot = await Directory.systemTemp.createTemp(
      'pioneer_epub_collection_cache_dedup_',
    );
    addTearDown(() async {
      if (cacheRoot.existsSync()) {
        await cacheRoot.delete(recursive: true);
      }
    });

    final service = PioneerEpubCollectionService(
      fetcher: (uri) async {
        return _zipBytes([
          MapEntry('Epub/Smith/Exact Duplicate.epub', [1, 2, 3, 4]),
          MapEntry('Epub/Smith/./Exact Duplicate.epub', [1, 2, 3, 4]),
        ]);
      },
      cacheRootPathResolver: () async => cacheRoot.path,
      catalogLoader: () async => _emptyCatalog(),
      directCatalogLoader: (_) async => _emptyCatalog(),
      localCatalogLoader: () async => _emptyCatalog(),
    );

    final catalog = await service.loadCatalog(refresh: true);
    final uriahSmith = catalog.authorById('uriah_smith');

    expect(catalog.workCount, 1);
    expect(uriahSmith, isNotNull);
    expect(uriahSmith!.works.length, 1);
    expect(catalog.diagnostics!.duplicateEntriesSkipped, 1);
  });

  test(
    'discovers every structurally valid EPUB in the Pioneer folder',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'pioneer_local_folder_',
      );
      addTearDown(() => root.delete(recursive: true));
      final folder = Directory('${root.path}/ePubs/Pioneers')
        ..createSync(recursive: true);
      final validBytes = _zipBytes([
        MapEntry(
          'META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/>'
                  '</rootfiles></container>'
              .codeUnits,
        ),
        MapEntry(
          'OEBPS/content.opf',
          '<package><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
                  '<dc:title>Future Pioneer Work</dc:title>'
                  '<dc:creator>Future Pioneer Author</dc:creator>'
                  '</metadata></package>'
              .codeUnits,
        ),
      ]);
      File('${folder.path}/future_work.epub').writeAsBytesSync(validBytes);
      File('${folder.path}/broken.epub').writeAsStringSync('not a zip');
      File('${folder.path}/notes.txt').writeAsStringSync('ignored');

      final catalog = await loadPioneerCatalogFromFolder(folder.path);

      expect(catalog.workCount, 1);
      final work = catalog.workById('future_work');
      expect(work, isNotNull);
      expect(work!.title, 'Future Pioneer Work');
      expect(work.authorName, 'Future Pioneer Author');
      expect(work.preferredImportCandidate!.provider, 'cloudfiles');
      expect(work.preferredImportCandidate!.url, startsWith('file:'));
    },
  );

  test('resolves a selected EPUB directly from a Pioneers folder', () async {
    final root = await Directory.systemTemp.createTemp(
      'pioneer_selected_file_',
    );
    addTearDown(() => root.delete(recursive: true));
    final folder = Directory('${root.path}/ePubs/Pioneers')
      ..createSync(recursive: true);
    final file = File('${folder.path}/sanctification.epub')
      ..writeAsBytesSync(
        _zipBytes([
          MapEntry(
            'META-INF/container.xml',
            '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
                    '</rootfiles></container>'
                .codeUnits,
          ),
          MapEntry(
            'OPS/book.opf',
            '<package><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
                    '<dc:title>Sanctification</dc:title>'
                    '<dc:creator>Daniel T. Bordeau</dc:creator>'
                    '</metadata></package>'
                .codeUnits,
          ),
        ]),
      );

    final work = await loadPioneerWorkFromFolderFile(file.path);

    expect(work, isNotNull);
    expect(work!.id, 'sanctification');
    expect(work.title, 'Sanctification');
    expect(work.authorName, 'Daniel T. Bordeau');
  });

  test(
    'resolves any local generated EPUB idempotently from metadata',
    () async {
      final root = await Directory.systemTemp.createTemp('pioneer_local_epub_');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/newly-generated.epub')
        ..writeAsBytesSync(
          _zipBytes([
            MapEntry(
              'META-INF/container.xml',
              '<container><rootfiles><rootfile full-path="OPS/book.opf"/>'
                      '</rootfiles></container>'
                  .codeUnits,
            ),
            MapEntry(
              'OPS/book.opf',
              '<package><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
                      '<dc:title>The National Sunday Law [SL27]</dc:title>'
                      '<dc:creator>Alonzo T. Jones</dc:creator>'
                      '</metadata></package>'
                  .codeUnits,
            ),
          ]),
        );

      final first = await loadPioneerWorkFromLocalEpubFile(file.path);
      final second = await loadPioneerWorkFromLocalEpubFile(file.path);

      expect(first, isNotNull);
      expect(first!.id, 'sl27');
      expect(first.title, 'The National Sunday Law [SL27]');
      expect(first.authorName, 'Alonzo T. Jones');
      expect(second!.id, first.id);
      expect(second.stableLibraryItemId, first.stableLibraryItemId);
    },
  );
}
