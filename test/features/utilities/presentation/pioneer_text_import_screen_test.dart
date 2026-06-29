import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/data/pioneer_html_capture_folder_scanner.dart';
import 'package:studybible2/features/utilities/data/pioneer_install_status_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';
import 'package:studybible2/features/utilities/presentation/pioneer_text_import_screen.dart';

PioneerSourceCatalog _textCaptureCatalog() {
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
            'source_type': 'egwReadPage',
            'collection_url': 'https://egwwritings.org/allCollection/en/160',
            'capture_url': 'https://egwwritings.org/read?panels=p1297.2',
            'reader_url': 'https://egwwritings.org/read?panels=p1297.2',
            'source_url': 'https://egwwritings.org/read?panels=p1297.2',
            'source_label': 'EGW Writings',
            'thumbnail_url': 'https://egwwritings.org/covers/dar.jpg',
            'verified': true,
          },
          {
            'work_id': 'the_united_states_in_the_light_of_prophecy',
            'title': 'The United States in the Light of Prophecy',
            'abbreviation': 'USLP',
            'group': 'Pioneer Authors',
            'subgroup': 'Prophecy',
            'availability_status': 'available',
            'source_type': 'capturedHtml',
            'source_url': 'asset://test/uriah-smith/uslp.html',
            'source_label': 'EGW Writings',
            'verified': true,
            'importable': true,
            'source_candidates': [
              {
                'provider': 'egwWritings',
                'source_type': 'capturedHtml',
                'url': 'asset://test/uriah-smith/uslp.html',
                'priority': 1,
                'quality_tier': 'capturedhtml',
                'availability': 'available',
              },
            ],
          },
        ],
      },
      {
        'author_id': 'a_t_jones',
        'author_name': 'A. T. Jones',
        'source_family': 'Pioneer',
        'sort_key': 'a t jones',
        'works': [
          {
            'work_id': 'lessons_on_faith',
            'title': 'Lessons on Faith',
            'abbreviation': 'LOF',
            'group': 'Pioneer Authors',
            'subgroup': 'Righteousness by Faith',
            'availability_status': 'available',
            'source_type': 'capturedHtml',
            'source_url': 'assets/scans/LOF_ATJ/capture.html',
            'source_label': 'Local HTML Capture',
            'verified': true,
            'importable': true,
          },
          {
            'work_id': 'the_american_papacy',
            'title': 'The American Papacy',
            'abbreviation': 'TAP',
            'group': 'Pioneer Authors',
            'subgroup': 'Religious Liberty',
            'availability_status': 'source_needed',
            'source_type': 'egwReadPage',
            'collection_url': 'https://egwwritings.org/allCollection/en/161',
            'capture_url': 'https://egwwritings.org/read?panels=p1200.2',
            'reader_url': 'https://egwwritings.org/read?panels=p1200.2',
            'source_url': 'https://egwwritings.org/read?panels=p1200.2',
            'source_label': 'EGW Writings',
            'verified': true,
          },
        ],
      },
    ],
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required PioneerSourceCatalog catalog,
  Map<String, PioneerWorkInstallStatus> installStatuses = const {},
  PioneerHtmlCaptureFolderScanner? htmlCaptureFolderScanner,
  PioneerExistingCapturedImportInspector? existingCapturedImportInspector,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PioneerTextImportScreen(
        catalogFuture: Future.value(catalog),
        installStatusFuture: Future.value(installStatuses),
        htmlCaptureFolderScanner: htmlCaptureFolderScanner,
        existingCapturedImportInspector: existingCapturedImportInspector,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAuthor(WidgetTester tester, String authorId) async {
  final authorKey = find.byKey(ValueKey<String>('pioneer_author_$authorId'));
  await tester.scrollUntilVisible(
    authorKey,
    300,
    scrollable: find.byType(Scrollable),
  );
  await tester.tap(authorKey);
  await tester.pumpAndSettle();
}

void _expectNoForbiddenStatusText() {
  expect(find.text('EPUB needs review'), findsNothing);
  expect(find.text('Legacy EPUB fallback'), findsNothing);
  expect(find.text('EPUB ready'), findsNothing);
  expect(find.text('EPUB status'), findsNothing);
  expect(find.textContaining('EllenWhiteAudio'), findsNothing);
  expect(find.textContaining('ellenwhiteaudio'), findsNothing);
  expect(find.textContaining('APLIB'), findsNothing);
  expect(find.textContaining('APLib'), findsNothing);
  expect(find.textContaining('PDF'), findsNothing);
  expect(find.textContaining('OCR'), findsNothing);
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

double _compositedContrastRatio(
  Color foreground,
  Color background,
  Color base,
) {
  final resolvedBackground = Color.alphaBlend(background, base);
  final resolvedForeground = Color.alphaBlend(foreground, resolvedBackground);
  return _contrastRatio(resolvedForeground, resolvedBackground);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows an author list before work rows', (tester) async {
    final catalog = _textCaptureCatalog();

    await _pumpScreen(tester, catalog: catalog);

    expect(find.text('Pioneer Authors'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pioneer_author_uriah_smith')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('pioneer_author_a_t_jones')),
      findsOneWidget,
    );
    expect(
      find.text('Daniel and the Revelation', skipOffstage: false),
      findsNothing,
    );
    _expectNoForbiddenStatusText();
  });

  testWidgets(
    'opens an author work list with status badges and fallback cover',
    (tester) async {
      final catalog = _textCaptureCatalog();

      await _pumpScreen(tester, catalog: catalog);
      await _openAuthor(tester, 'uriah_smith');

      expect(find.text('Uriah Smith'), findsWidgets);
      expect(find.text('Daniel and the Revelation'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>(
            'pioneer_work_uriah_smith_daniel_and_the_revelation',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Capture needed'), findsOneWidget);
      expect(find.text('DAR'), findsOneWidget);
      _expectNoForbiddenStatusText();
    },
  );

  testWidgets('selects capture-needed and captured-text works for import', (
    tester,
  ) async {
    final catalog = _textCaptureCatalog();

    await _pumpScreen(tester, catalog: catalog);
    await _openAuthor(tester, 'uriah_smith');

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'pioneer_work_checkbox_uriah_smith_daniel_and_the_revelation',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Checkbox>(
            find.byKey(
              const ValueKey<String>(
                'pioneer_work_checkbox_uriah_smith_daniel_and_the_revelation',
              ),
            ),
          )
          .value,
      isTrue,
    );
    expect(
      find.widgetWithText(FilledButton, 'Import Selected'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('pioneer-select-all-available-button')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Selected 2'), findsOneWidget);
  });

  // The 'Import assets/scans' runtime button was removed because it tried to
  // scan the macOS sandbox-restricted filesystem and threw PathAccessException.
  // Assets are now imported at build time via the import_scans_to_asset_db
  // tool. These two tests confirm the fix: the button key is absent and the
  // screen loads without errors.

  testWidgets(
    'pioneer-import-assets-scans-button is absent (macOS crash fix)',
    (tester) async {
      final catalog = _textCaptureCatalog();
      await _pumpScreen(tester, catalog: catalog);

      expect(
        find.byKey(
          const ValueKey<String>('pioneer-import-assets-scans-button'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'screen renders without PathAccessException when no scanner is provided',
    (tester) async {
      final catalog = _textCaptureCatalog();

      // Must not throw — absence of htmlCaptureFolderScanner means no
      // filesystem scan happens and no PathAccessException is raised.
      await _pumpScreen(tester, catalog: catalog);

      expect(find.text('Pioneer Authors'), findsOneWidget);
      _expectNoForbiddenStatusText();
    },
  );

  test('HTML capture dialog colors stay readable in dark mode', () {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: Brightness.dark,
    );
    final colors = pioneerHtmlCaptureDialogColors(scheme);
    final dialogSurface = scheme.surface;

    expect(
      _contrastRatio(
        colors.overwriteSelectedLabel,
        colors.overwriteSelectedBackground,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(
        colors.overwriteCheckmark,
        colors.overwriteSelectedBackground,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _compositedContrastRatio(
        colors.overwriteDisabledLabel,
        colors.overwriteDisabledBackground,
        dialogSurface,
      ),
      greaterThanOrEqualTo(2.0),
    );
    expect(
      _contrastRatio(colors.importForeground, colors.importBackground),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _compositedContrastRatio(
        colors.importDisabledForeground,
        colors.importDisabledBackground,
        dialogSurface,
      ),
      greaterThanOrEqualTo(2.0),
    );
  });

  testWidgets('catalog-only row is available and installed text row is text', (
    tester,
  ) async {
    final catalog = _textCaptureCatalog();
    final installStatuses = <String, PioneerWorkInstallStatus>{
      'the_united_states_in_the_light_of_prophecy':
          const PioneerWorkInstallStatus(
            workId: 'the_united_states_in_the_light_of_prophecy',
            hasLibraryRow: true,
            qualityState: PioneerInstalledQualityState.verified,
            installedSourceSummary: 'EGW browser capture',
            installedSourceType: 'egw_browser_capture',
            installedSourceSite: 'egwwritings.org',
            installedSourceUrl: 'https://egwwritings.org/read?panels=p1297.2',
            textBlockCount: 8,
            navigationRowCount: 2,
            navigationRowsWithTextCount: 2,
            refRowCount: 4,
          ),
    };

    await _pumpScreen(
      tester,
      catalog: catalog,
      installStatuses: installStatuses,
    );
    await _openAuthor(tester, 'uriah_smith');

    expect(find.text('Capture needed'), findsOneWidget);
    expect(find.text('Installed — text'), findsOneWidget);
    _expectNoForbiddenStatusText();
  });

  testWidgets('old broken installed row shows legacy import review wording', (
    tester,
  ) async {
    final catalog = _textCaptureCatalog();
    final installStatuses = <String, PioneerWorkInstallStatus>{
      'daniel_and_the_revelation': const PioneerWorkInstallStatus(
        workId: 'daniel_and_the_revelation',
        hasLibraryRow: true,
        qualityState: PioneerInstalledQualityState.badImport,
        installedSourceSummary: 'Legacy import',
        installedSourceType: 'legacy_file',
        installedSourceSite: 'legacy',
        installedSourceUrl: null,
        textBlockCount: 0,
        navigationRowCount: 0,
        navigationRowsWithTextCount: 0,
        refRowCount: 0,
      ),
    };

    await _pumpScreen(
      tester,
      catalog: catalog,
      installStatuses: installStatuses,
    );
    await _openAuthor(tester, 'uriah_smith');

    expect(find.text('Legacy import needs review'), findsOneWidget);
    _expectNoForbiddenStatusText();
  });
}
