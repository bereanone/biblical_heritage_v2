import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the pioneer source catalog from assets', () async {
    final catalog = await PioneerSourceCatalog.load();

    expect(catalog.authorCount, 4);
    expect(catalog.workCount, greaterThanOrEqualTo(4));

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
    expect(
      danielAndTheRevelation.stableLibraryItemId,
      'library_item_research_pioneer_uriah_smith_daniel_and_the_revelation',
    );
    expect(danielAndTheRevelation.isImportable, isFalse);
    expect(danielAndTheRevelation.friendlyAvailabilityLabel, 'Source needed');
    expect(
      danielAndTheRevelation.friendlySourceStatusLabel,
      'No verified source',
    );
    expect(danielAndTheRevelation.sourceUrl, isNull);
  });

  test(
    'supports selecting multiple works and blocks source-needed items',
    () async {
      final catalog = await PioneerSourceCatalog.load();
      final selection = PioneerSourceSelection.empty()
          .toggle('daniel_and_the_revelation')
          .toggle('history_of_the_sabbath');

      expect(selection.selectedCount, 2);
      expect(
        selection.selectedWorks(catalog).map((work) => work.title),
        containsAll(['Daniel and the Revelation', 'History of the Sabbath']),
      );
      expect(selection.importableSelectedWorks(catalog), isEmpty);
      expect(selection.blockedSelectedWorks(catalog), hasLength(2));
      expect(selection.canImport(catalog), isFalse);
      expect(
        selection.importBlockMessage(catalog),
        'No selected Pioneer work has a verified source yet.',
      );
    },
  );

  test('tolerates missing optional source URLs', () async {
    final catalog = await PioneerSourceCatalog.load();

    for (final work in catalog.works) {
      expect(work.sourceUrl, isNull);
      expect(work.isImportable, isFalse);
      expect(work.friendlySourceStatusLabel, 'No verified source');
    }
  });
}
