import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_archive_org_install_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('downloads are restricted to archive.org over https', () {
    expect(
      PioneerArchiveOrgInstallService.isTrustedDownloadUri(
        Uri.parse('https://archive.org/download/foo/bar.epub'),
      ),
      isTrue,
    );
    expect(
      PioneerArchiveOrgInstallService.isTrustedDownloadUri(
        Uri.parse('http://archive.org/download/foo/bar.epub'),
      ),
      isFalse,
    );
    expect(
      PioneerArchiveOrgInstallService.isTrustedDownloadUri(
        Uri.parse('https://evil.example.com/download/foo/bar.epub'),
      ),
      isFalse,
    );
  });

  test('title dedup normalization ignores case and extra whitespace', () {
    expect(
      PioneerArchiveOrgInstallService.normalizeTitleForDedup(
        'Daniel and  the Revelation',
      ),
      PioneerArchiveOrgInstallService.normalizeTitleForDedup(
        '  daniel AND THE revelation  ',
      ),
    );
    expect(
      PioneerArchiveOrgInstallService.normalizeTitleForDedup(
        'Lessons on Faith',
      ),
      isNot(
        PioneerArchiveOrgInstallService.normalizeTitleForDedup(
          'Daniel and the Revelation',
        ),
      ),
    );
  });

  test('canonical identity is code-based and preserves distinct editions', () {
    expect(
      PioneerArchiveOrgInstallService.canonicalLibraryItemId(
        author: 'Uriah Smith',
        canonicalCode: 'DAR',
      ),
      'pioneer_uriah_smith_dar',
    );
    expect(
      PioneerArchiveOrgInstallService.canonicalLibraryItemId(
        author: 'Uriah Smith',
        canonicalCode: 'DAR1909',
      ),
      isNot('pioneer_uriah_smith_dar'),
    );
  });

  test(
    'destination file name only folds in the code when titles collide',
    () {
      // No collision: the plain sanitized title is used, matching every
      // already-downloaded file on disk today.
      expect(
        PioneerArchiveOrgInstallService.destinationFileNameFor(
          title: 'The Atonement',
          code: 'ATO',
          titleCollisionCounts: const {'The Atonement': 1},
        ),
        'The Atonement.epub',
      );
      // Colliding titles (e.g. Uriah Smith's DAR and DAR1909 editions of
      // "Daniel and The Revelation") must resolve to distinct file names —
      // otherwise the second download silently overwrites the first on disk
      // while both still get their own `library_items` row, leaving one row
      // pointing at a file that is no longer what it claims to be.
      const collidingTitle = 'Daniel and The Revelation';
      final dar = PioneerArchiveOrgInstallService.destinationFileNameFor(
        title: collidingTitle,
        code: 'DAR',
        titleCollisionCounts: const {'Daniel and The Revelation': 2},
      );
      final dar1909 = PioneerArchiveOrgInstallService.destinationFileNameFor(
        title: collidingTitle,
        code: 'DAR1909',
        titleCollisionCounts: const {'Daniel and The Revelation': 2},
      );
      expect(dar, isNot(dar1909));
      expect(dar, endsWith('.epub'));
      expect(dar1909, endsWith('.epub'));
      expect(dar, contains('DAR'));
      expect(dar1909, contains('DAR1909'));
    },
  );

  test(
    'the bundled manifest never lets two works collide on the same file name',
    () async {
      final raw = await rootBundle.loadString(
        PioneerArchiveOrgInstallService.manifestAssetKey,
      );
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final authors = decoded['authors'] as List;

      final titleCollisionCounts = <String, int>{};
      final allWorks = <Map<String, Object?>>[];
      for (final entry in authors) {
        final works = (entry as Map<String, Object?>)['works'] as List;
        for (final workEntry in works) {
          final work = workEntry as Map<String, Object?>;
          allWorks.add(work);
          final base = (work['title'] as String)
              .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
              .trim();
          titleCollisionCounts.update(
            base,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }

      final resolvedFileNames = <String>{};
      for (final work in allWorks) {
        final fileName = PioneerArchiveOrgInstallService.destinationFileNameFor(
          title: work['title'] as String,
          code: work['code'] as String,
          titleCollisionCounts: titleCollisionCounts,
        );
        expect(
          resolvedFileNames.add(fileName),
          isTrue,
          reason:
              'Two manifest works resolved to the same destination file '
              'name ($fileName) — one would silently overwrite the other '
              'on disk.',
        );
      }
    },
  );

  test(
    'bundled manifest only lists authors with real archive.org EPUB files',
    () async {
      final raw = await rootBundle.loadString(
        PioneerArchiveOrgInstallService.manifestAssetKey,
      );
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final authors = decoded['authors'] as List;
      expect(authors, isNotEmpty);

      final seenTitles = <String>{};
      var sawFp1872Alias = false;
      for (final entry in authors) {
        final map = entry as Map<String, Object?>;
        final identifier = map['identifier'] as String;
        expect(identifier, startsWith('adventist-pioneer-authors-'));
        final works = map['works'] as List;
        expect(works, isNotEmpty, reason: '$identifier has no works');
        for (final workEntry in works) {
          final work = workEntry as Map<String, Object?>;
          expect(work['code'], isNotEmpty);
          expect(work['title'], isNotEmpty);
          expect(work['file_name'], endsWith('.epub'));
          if (work['code'] == 'FPSDA') {
            expect(work['canonical_code'], 'FP1872');
            expect(work['aliases'], containsAll(<String>['FPSDA', 'FP187']));
            sawFp1872Alias = true;
          }
          seenTitles.add(work['title'] as String);
        }
      }

      // The self-captured "Daniel and the Revelation" bundled with the app
      // (assets/scans/DAR) also exists on archive.org under Uriah Smith —
      // this is exactly the case the title-dedup check in install() exists
      // to catch, so it must still be present in the manifest for that
      // regression path to be exercised rather than silently vanishing.
      expect(seenTitles, contains('Daniel and The Revelation'));
      expect(sawFp1872Alias, isTrue);
    },
  );
}
