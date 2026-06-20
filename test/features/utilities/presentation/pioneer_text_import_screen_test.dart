import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';
import 'package:studybible2/features/utilities/presentation/pioneer_text_import_screen.dart';

PioneerSourceCatalog _fakeCatalog() {
  return PioneerSourceCatalog.fromJson({
    'authors': [
      {
        'author_id': 'uriah_smith',
        'author_name': 'Uriah Smith',
        'sort_key': 'uriah smith',
        'works': [
          {
            'work_id': 'daniel_and_the_revelation',
            'title': 'Daniel and the Revelation',
            'abbreviation': 'DAR',
            'group': 'Pioneer Authors',
            'subgroup': 'Prophecy',
            'availability_status': 'available',
            'source_type': 'epub',
            'source_url':
                'https://archive.org/download/UriahSmithDanielAndTheRevelation.TheResponseOfHistoryToTheVoiceOf/1897_smith_danielAndTheRevelation.epub',
            'source_label': 'Archive.org',
            'verified': true,
            'importable': true,
          },
          {
            'work_id': 'the_united_states_in_the_light_of_prophecy',
            'title': 'The United States in the Light of Prophecy',
            'abbreviation': 'USLP',
            'group': 'Pioneer Authors',
            'subgroup': 'Prophecy',
            'availability_status': 'available',
            'source_type': 'html',
            'source_url':
                'https://www.gutenberg.org/files/12364/12364-h/12364-h.htm',
            'source_label': 'Project Gutenberg',
            'verified': true,
            'importable': true,
          },
        ],
      },
      {
        'author_id': 'jn_andrews',
        'author_name': 'J. N. Andrews',
        'sort_key': 'jn andrews',
        'works': [
          {
            'work_id': 'history_of_the_sabbath',
            'title': 'History of the Sabbath',
            'abbreviation': 'HST',
            'group': 'Pioneer Authors',
            'subgroup': 'Sabbath',
            'availability_status': 'source_needed',
          },
        ],
      },
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows available works near the top with no auto-selection', (tester) async {
    final catalog = _fakeCatalog();

    await tester.pumpWidget(
      MaterialApp(
        home: PioneerTextImportScreen(
          catalogFuture: Future.value(catalog),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available to import'), findsOneWidget);
    expect(find.textContaining('Daniel and the Revelation'), findsWidgets);
    expect(find.textContaining('The United States in the Light of Prophecy'), findsWidgets);
    expect(find.textContaining('Archive.org'), findsWidgets);
    expect(find.textContaining('Project Gutenberg'), findsWidgets);
    expect(find.text('0 works selected'), findsOneWidget);

    final importButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import Verified Sources'),
    );
    expect(importButton.onPressed, isNull);
  });

  testWidgets('shows the source-needed section for clipboard or saved-export import', (tester) async {
    final catalog = _fakeCatalog();

    await tester.pumpWidget(
      MaterialApp(
        home: PioneerTextImportScreen(
          catalogFuture: Future.value(catalog),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Source needed works'),
      200,
    );
    await tester.pumpAndSettle();

    expect(find.text('Source needed works'), findsOneWidget);
    expect(find.textContaining('History of the Sabbath'), findsWidgets);
  });
}
