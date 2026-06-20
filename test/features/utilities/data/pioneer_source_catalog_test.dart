import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the pioneer source catalog from assets', () async {
    final catalog = await PioneerSourceCatalog.load();

    expect(catalog.authorCount, 4);
    expect(catalog.workCount, 8);

    final uriahSmith = catalog.authorById('uriah_smith');
    expect(uriahSmith, isNotNull);
    expect(uriahSmith!.name, 'Uriah Smith');
    expect(
      uriahSmith.works.map((work) => work.title),
      contains('Daniel and the Revelation'),
    );

    final danielAndTheRevelation = catalog.workById(
      'daniel_and_the_revelation',
    );
    expect(danielAndTheRevelation, isNotNull);
    expect(danielAndTheRevelation!.abbreviation, 'DAR');
    expect(danielAndTheRevelation.verified, isTrue);
    expect(danielAndTheRevelation.sourceType, 'epub');
    expect(danielAndTheRevelation.sourceTypeLabel, 'EPUB');
    expect(danielAndTheRevelation.sourceUrl, isNotNull);
    expect(danielAndTheRevelation.sourceSiteLabel, 'Archive.org');
    expect(danielAndTheRevelation.friendlyAvailabilityLabel, 'Available');
    expect(danielAndTheRevelation.friendlySourceStatusLabel, 'Archive.org');
    expect(danielAndTheRevelation.isImportable, isTrue);
    expect(
      danielAndTheRevelation.stableLibraryItemId,
      'library_item_research_pioneer_uriah_smith_daniel_and_the_revelation',
    );

    final uslp = catalog.workById('the_united_states_in_the_light_of_prophecy');
    expect(uslp, isNotNull);
    expect(uslp!.verified, isTrue);
    expect(uslp.sourceType, 'html');
    expect(uslp.sourceUrl, isNotNull);
    expect(uslp.sourceSiteLabel, 'Project Gutenberg');
    expect(uslp.isImportable, isTrue);
    expect(uslp.friendlyAvailabilityLabel, 'Available');
    expect(
      catalog.importableWorks.map((work) => work.title),
      containsAll([
        'Daniel and the Revelation',
        'The United States in the Light of Prophecy',
      ]),
    );
  });

  test(
    'supports selecting multiple importable works and ignores source-needed items',
    () async {
      final catalog = await PioneerSourceCatalog.load();
      final selection = PioneerSourceSelection.empty()
          .toggle('daniel_and_the_revelation')
          .toggle('the_united_states_in_the_light_of_prophecy')
          .toggle('history_of_the_sabbath');

      expect(selection.selectedCount, 3);
      expect(
        selection.selectedWorks(catalog).map((work) => work.title),
        containsAll([
          'Daniel and the Revelation',
          'The United States in the Light of Prophecy',
          'History of the Sabbath',
        ]),
      );
      expect(
        selection.importableSelectedWorks(catalog).map((work) => work.title),
        containsAll([
          'Daniel and the Revelation',
          'The United States in the Light of Prophecy',
        ]),
      );
      expect(selection.blockedSelectedWorks(catalog), hasLength(1));
      expect(selection.canImport(catalog), isTrue);
      expect(
        selection.importBlockMessage(catalog),
        '1 selected work need a verified source first.',
      );
    },
  );

  test('tolerates missing optional source fields and keeps source-needed items blocked', () async {
    final catalog = await PioneerSourceCatalog.load();

    for (final work in catalog.works.where((work) => !work.isImportable)) {
      expect(work.sourceUrl, isNull);
      expect(work.verified, isFalse);
      expect(work.isImportable, isFalse);
      expect(work.friendlySourceStatusLabel, 'No verified source');
    }
  });

  test('starts with no selected works', () {
    final selection = PioneerSourceSelection.empty();

    expect(selection.selectedCount, 0);
    expect(selection.selectedWorkIds, isEmpty);
  });
}
