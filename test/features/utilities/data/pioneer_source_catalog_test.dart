import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads the pioneer source catalog with text-capture-first display',
    () async {
      final catalog = await PioneerSourceCatalog.load();

      expect(catalog.authorCount, greaterThan(0));
      expect(catalog.workCount, greaterThan(0));

      final danielAndTheRevelation = catalog.workById(
        'daniel_and_the_revelation',
      );
      expect(danielAndTheRevelation, isNotNull);
      expect(danielAndTheRevelation!.abbreviation, 'DAR');
      expect(danielAndTheRevelation.sourceTypeLabel, 'EGW Reader Capture');
      expect(danielAndTheRevelation.sourceSiteLabel, 'EGW Writings');
      expect(danielAndTheRevelation.launchUrl, contains('egwwritings.org'));
      expect(danielAndTheRevelation.textCaptureStatus.label, 'Capture needed');
      expect(danielAndTheRevelation.isImportable, isFalse);
      expect(danielAndTheRevelation.compactImportStatusLabel, 'Capture needed');
      expect(
        danielAndTheRevelation.effectiveSourceCandidates
            .where((candidate) => candidate.isLegacyFileCandidate)
            .isNotEmpty,
        isTrue,
      );
      expect(
        danielAndTheRevelation.preferredSourceCandidate!.isLegacyFileCandidate,
        isFalse,
      );
      expect(
        danielAndTheRevelation.stableLibraryItemId,
        'library_item_research_pioneer_uriah_smith_daniel_and_the_revelation',
      );
    },
  );

  test('parses work thumbnail metadata and fallback cover labels', () {
    final catalog = PioneerSourceCatalog.fromJson({
      'authors': [
        {
          'author_id': 'a_t_jones',
          'author_name': 'A. T. Jones',
          'works': [
            {
              'work_id': 'the_american_papacy',
              'title': 'The American Papacy',
              'abbreviation': 'TAP',
              'group': 'Pioneer Authors',
              'subgroup': 'Religious Liberty',
              'availability_status': 'source_needed',
              'source_type': 'egwReadPage',
              'source_url': 'https://egwwritings.org/read?panels=p1200.2',
              'source_label': 'EGW Writings',
              'thumbnail_url': 'https://egwwritings.org/covers/tap.jpg',
              'cached_thumbnail_path': 'TextCaptures/covers/tap.jpg',
              'verified': true,
            },
          ],
        },
      ],
    });

    final work = catalog.workById('the_american_papacy')!;
    expect(work.thumbnailUrl, 'https://egwwritings.org/covers/tap.jpg');
    expect(work.coverImagePath, 'TextCaptures/covers/tap.jpg');
    expect(work.fallbackCoverLabel, 'TAP');
    expect(work.launchUrl, 'https://egwwritings.org/read?panels=p1200.2');
    expect(work.textCaptureStatus, PioneerTextCaptureStatus.captureNeeded);
  });

  test('captured text source is importable and selected for import', () {
    final catalog = PioneerSourceCatalog.fromJson({
      'authors': [
        {
          'author_id': 'uriah_smith',
          'author_name': 'Uriah Smith',
          'works': [
            {
              'work_id': 'captured_uslp',
              'title': 'The United States in the Light of Prophecy',
              'abbreviation': 'USLP',
              'group': 'Pioneer Authors',
              'subgroup': 'Prophecy',
              'availability_status': 'available',
              'source_type': 'capturedHtml',
              'source_url': 'asset://test/uslp.html',
              'source_label': 'EGW Writings',
              'verified': true,
              'importable': true,
              'source_candidates': [
                {
                  'provider': 'egwWritings',
                  'source_type': 'capturedHtml',
                  'url': 'asset://test/uslp.html',
                  'priority': 1,
                  'quality_tier': 'capturedhtml',
                  'availability': 'available',
                },
              ],
            },
            {
              'work_id': 'needs_capture',
              'title': 'Needs Capture',
              'abbreviation': 'NC',
              'group': 'Pioneer Authors',
              'subgroup': 'Prophecy',
              'availability_status': 'source_needed',
              'source_type': 'egwReadPage',
              'source_url': 'https://egwwritings.org/read?panels=p1300.2',
              'source_label': 'EGW Writings',
              'verified': true,
            },
          ],
        },
      ],
    });

    final importableTitles = catalog.importableWorks
        .map((work) => work.title)
        .toList(growable: false);
    expect(importableTitles, ['The United States in the Light of Prophecy']);

    final selection = PioneerSourceSelection.fromWorkIds([
      'captured_uslp',
      'needs_capture',
    ]);
    expect(selection.selectedCount, 2);
    expect(selection.importableSelectedWorks(catalog), hasLength(1));
    expect(selection.blockedSelectedWorks(catalog), hasLength(1));
    expect(
      selection.importBlockMessage(catalog),
      '1 selected work need a verified source first.',
    );
  });

  test('direct file candidates are hidden from source preference', () {
    final catalog = PioneerSourceCatalog.fromJson({
      'authors': [
        {
          'author_id': 'uriah_smith',
          'author_name': 'Uriah Smith',
          'works': [
            {
              'work_id': 'daniel_and_the_revelation',
              'title': 'Daniel and the Revelation',
              'abbreviation': 'DAR',
              'group': 'Pioneer Authors',
              'subgroup': 'Prophecy',
              'availability_status': 'available',
              'source_type': 'egwReadPage',
              'source_url': 'https://egwwritings.org/read?panels=p1297.2',
              'source_label': 'EGW Writings',
              'verified': true,
              'source_candidates': [
                {
                  'provider': 'aplib',
                  'source_type': 'epubZipEntry',
                  'url': 'https://example.com/archive.zip',
                  'zip_entry': 'Set/DAR.epub',
                  'priority': 1,
                  'quality_tier': 'epub',
                  'availability': 'available',
                },
                {
                  'provider': 'egwWritings',
                  'source_type': 'readerPage',
                  'url': 'https://egwwritings.org/read?panels=p1297.2',
                  'priority': 50,
                  'quality_tier': 'reader',
                  'availability': 'available',
                },
              ],
            },
          ],
        },
      ],
    });

    final work = catalog.workById('daniel_and_the_revelation')!;
    expect(work.preferredSourceCandidate!.providerLabel, 'EGW Writings');
    expect(work.sourceTypeLabel, 'EGW Reader Capture');
    expect(work.preferredImportCandidate, isNull);
    expect(work.compactImportStatusLabel, 'Capture needed');
  });

  test('starts with no selected works', () async {
    final catalog = await PioneerSourceCatalog.load();

    final selection = PioneerSourceSelection.empty();

    expect(selection.selectedCount, 0);
    expect(selection.selectedWorks(catalog), isEmpty);
    expect(selection.canImport(catalog), isFalse);
    expect(
      selection.importBlockMessage(catalog),
      'Select one or more works to import.',
    );
  });
}
