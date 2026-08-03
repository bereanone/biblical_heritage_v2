import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/features/utilities/data/elibrary_file_management_service.dart';
import 'package:studybible2/features/utilities/presentation/elibrary_setup_screen.dart';
import 'package:studybible2/features/utilities/presentation/library_indexing_prompt_dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('usable legacy or implicit roots map to ready storage text', () {
    final selection = LibraryRootSelection(
      path:
          '/var/mobile/Containers/Data/Application/ABC/Documents/BiblicalHeritage/v2',
      exists: true,
      needsReconnect: false,
      source: LibraryRootSource.legacyImplicit,
    );

    expect(isUsableLibraryRootSelection(selection), isTrue);
    expect(libraryStorageStatusText(selection), '✓ Library is ready');
    expect(
      libraryStorageHelperText(selection),
      'Downloaded and imported books are stored in the app\'s library.',
    );
    expect(
      libraryStorageStatusText(selection),
      isNot('Library storage needs attention'),
    );
  });

  test('missing library roots still map to attention text', () {
    final selection = LibraryRootSelection(
      path:
          '/var/mobile/Containers/Data/Application/ABC/Documents/BiblicalHeritage/v2',
      exists: false,
      needsReconnect: true,
      source: LibraryRootSource.legacyImplicit,
    );

    expect(isUsableLibraryRootSelection(selection), isFalse);
    expect(
      libraryStorageStatusText(selection),
      'Library storage needs attention',
    );
    expect(
      libraryStorageHelperText(selection),
      'Open Manage Storage to choose or repair the library location.',
    );
  });

  testWidgets('library storage section shows a friendly ready state', (
    tester,
  ) async {
    var manageCount = 0;
    var indexCount = 0;
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ELibraryStorageSection(
            statusLabel: '✓ Library is ready',
            helperText:
                'Downloaded and imported books are stored in the app\'s library.',
            disableActions: false,
            onManageStorage: () => manageCount += 1,
            onIndexNewChangedBooks: () => indexCount += 1,
            onRefreshStatus: () => refreshCount += 1,
            manualIndexing: false,
            manualIndexStatus: null,
            manualIndexCompleted: 0,
            manualIndexTotal: 0,
            manualIndexCurrentTitle: null,
          ),
        ),
      ),
    );

    expect(find.text('✓ Library is ready'), findsOneWidget);
    expect(
      find.text(
        'Downloaded and imported books are stored in the app\'s library.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('/var/mobile/Containers'), findsNothing);
    expect(find.text('Manage Storage'), findsOneWidget);
    expect(find.text('Index New/Changed Books'), findsOneWidget);
    expect(find.text('Refresh Status'), findsOneWidget);

    await tester.tap(find.text('Manage Storage'));
    await tester.tap(find.text('Index New/Changed Books'));
    await tester.tap(find.text('Refresh Status'));
    await tester.pump();

    expect(manageCount, 1);
    expect(indexCount, 1);
    expect(refreshCount, 1);
  });

  testWidgets('capture imports section shows a friendly ready state', (
    tester,
  ) async {
    var packageCount = 0;
    var capturedCount = 0;
    var locationCount = 0;
    var downloadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptureClipperImportsSection(
            isIOS: false,
            statusLabel: '✓ Import location is ready',
            helperText:
                'Import CaptureClipper book packages or captured books into the Pioneer library.',
            disableActions: false,
            onCheckForNewBooks: () => packageCount += 1,
            onDownloadPioneerBooks: () => downloadCount += 1,
            onImportBookPackage: () => capturedCount += 1,
            onImportCapturedBooks: _noop,
            onChangeImportLocation: () => locationCount += 1,
            lastCheckedLabel: 'Last checked:\nPioneers\nToday',
          ),
        ),
      ),
    );

    expect(find.text('✓ Import location is ready'), findsOneWidget);
    expect(
      find.text(
        'Import the Pioneer Library from a folder you already have, or choose Pioneers.studycollection from the Collections folder in your cloud storage. StudyBible2 shows what will change before importing.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('/private/var'), findsNothing);
    expect(find.text('Last checked:\nPioneers\nToday'), findsOneWidget);
    expect(find.text('Check for New Books'), findsOneWidget);
    expect(find.text('Import Pioneer Library'), findsOneWidget);
    expect(find.text('Import One Book Package'), findsOneWidget);
    expect(find.text('Choose CloudFiles Folder'), findsOneWidget);

    await tester.tap(find.text('Check for New Books'));
    await tester.tap(find.text('Import Pioneer Library'));
    await tester.tap(find.text('Import One Book Package'));
    await tester.pump();

    expect(packageCount, 1);
    expect(downloadCount, 1);
    expect(capturedCount, 1);
    expect(locationCount, 0);
  });

  testWidgets('iOS uses copied package and file imports without folder roots', (
    tester,
  ) async {
    var downloadCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaptureClipperImportsSection(
            isIOS: true,
            statusLabel: 'Ready to import',
            helperText: 'Local copied imports',
            disableActions: false,
            onCheckForNewBooks: _noop,
            onDownloadPioneerBooks: () => downloadCount += 1,
            onImportBookPackage: _noop,
            onImportCapturedBooks: _noop,
            onChangeImportLocation: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Import Pioneer Library'), findsOneWidget);
    expect(find.text('Import StudyBible Book'), findsOneWidget);
    expect(find.text('Import CaptureClipper Files'), findsOneWidget);
    expect(find.text('Choose CloudFiles Folder'), findsNothing);
    expect(find.textContaining('persistent'), findsNothing);
    expect(
      find.text(
        'Import the Pioneer Library from a folder you already have, or choose a book package from OneDrive, iCloud Drive, or another Files location. StudyBible copies it locally so it remains available offline.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Import Pioneer Library'));
    expect(downloadCount, 1);
  });

  testWidgets(
    'Android offers online Pioneer books and separate copy-based package imports',
    (tester) async {
      var downloadCount = 0;
      var collectionCount = 0;
      var bookCount = 0;
      var locationCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CaptureClipperImportsSection(
              isIOS: false,
              isAndroid: true,
              statusLabel: 'Ready',
              helperText: 'Android Pioneer books',
              disableActions: false,
              onCheckForNewBooks: () => collectionCount += 1,
              onDownloadPioneerBooks: () => downloadCount += 1,
              onImportBookPackage: () => bookCount += 1,
              onImportCapturedBooks: _noop,
              onChangeImportLocation: () => locationCount += 1,
            ),
          ),
        ),
      );

      expect(find.text('Import Pioneer Library'), findsOneWidget);
      expect(find.text('Import Pioneer Collection'), findsOneWidget);
      expect(find.text('Import One Pioneer Book'), findsOneWidget);
      expect(find.text('Choose CloudFiles Folder'), findsNothing);
      expect(find.textContaining('Pioneers.studycollection'), findsOneWidget);
      expect(find.textContaining('.studybook'), findsOneWidget);

      await tester.tap(find.text('Import Pioneer Library'));
      await tester.tap(find.text('Import Pioneer Collection'));
      await tester.tap(find.text('Import One Pioneer Book'));

      expect(downloadCount, 1);
      expect(collectionCount, 1);
      expect(bookCount, 1);
      expect(locationCount, 0);
    },
  );

  testWidgets(
    'install collections section hides empty estimates and uses compact labels',
    (tester) async {
      var selectAllCount = 0;
      var clearAllCount = 0;
      var epubOnlyCount = 0;
      var pdfOnlyCount = 0;
      var bothCount = 0;
      var startCount = 0;
      bool? booksValue;
      bool? epubValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ELibraryInstallCollectionsSection(
                  running: false,
                  selectionWarning: null,
                  installBooks: false,
                  installDevotionals: false,
                  installCommentaries: false,
                  installMiscCollections: false,
                  installPamphlets: false,
                  installPeriodicals: false,
                  installManuscriptReleases: false,
                  installEpub: false,
                  installPdf: false,
                  collectionEstimateLines: List<String>.filled(
                    7,
                    '0 files found • size unknown',
                  ),
                  selectedDownloadSummary:
                      'Selected download: 0 files found • size unknown',
                  onSelectAllCollectionsAndFormats: () => selectAllCount += 1,
                  onClearAllSelections: () => clearAllCount += 1,
                  onSetPresetEpubOnly: () => epubOnlyCount += 1,
                  onSetPresetPdfOnly: () => pdfOnlyCount += 1,
                  onSetPresetBoth: () => bothCount += 1,
                  onStartSetup: () => startCount += 1,
                  onCancel: _noop,
                  onBooksChanged: (value) => booksValue = value,
                  onDevotionalsChanged: _noopBool,
                  onCommentariesChanged: _noopBool,
                  onMiscCollectionsChanged: _noopBool,
                  onPamphletsChanged: _noopBool,
                  onPeriodicalsChanged: _noopBool,
                  onManuscriptReleasesChanged: _noopBool,
                  onEpubChanged: (value) => epubValue = value,
                  onPdfChanged: _noopBool,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Install eLibrary Collections'), findsOneWidget);
      expect(
        find.text(
          'Books are downloaded directly from the official EGW Writings website into your eLibrary. Please follow the source website\'s terms and do not redistribute downloaded files.',
        ),
        findsOneWidget,
      );
      expect(find.text('Install Selected'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('EGW Books'), findsOneWidget);
      expect(find.text('EGW Devotionals'), findsOneWidget);
      expect(find.text('EGW Commentaries'), findsOneWidget);
      expect(find.text('EGW Miscellaneous'), findsOneWidget);
      expect(find.text('EGW Pamphlets'), findsOneWidget);
      expect(find.text('EGW Periodicals'), findsOneWidget);
      expect(find.text('EGW Manuscript Releases'), findsOneWidget);
      expect(find.text('0 files found • size unknown'), findsNothing);
      expect(
        find.text('Selected download: 0 files found • size unknown'),
        findsNothing,
      );
      expect(find.text('No collections selected'), findsOneWidget);

      final selectAllChip = tester.widget<ActionChip>(
        find.widgetWithText(
          ActionChip,
          'Select All Collections + All File Types',
        ),
      );
      final clearAllChip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, 'Clear All'),
      );
      final epubOnlyChip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, 'EPUB Only'),
      );
      final pdfOnlyChip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, 'PDF Only'),
      );
      final bothChip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, 'EPUB + PDF'),
      );
      final installSelectedButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Install Selected'),
      );
      final booksTile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'EGW Books'),
      );
      final epubTile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'EPUB'),
      );

      expect(selectAllChip.onPressed, isNotNull);
      expect(clearAllChip.onPressed, isNotNull);
      expect(epubOnlyChip.onPressed, isNotNull);
      expect(pdfOnlyChip.onPressed, isNotNull);
      expect(bothChip.onPressed, isNotNull);
      expect(installSelectedButton.onPressed, isNotNull);
      expect(booksTile.onChanged, isNotNull);
      expect(epubTile.onChanged, isNotNull);

      selectAllChip.onPressed!();
      clearAllChip.onPressed!();
      epubOnlyChip.onPressed!();
      pdfOnlyChip.onPressed!();
      bothChip.onPressed!();
      installSelectedButton.onPressed!();
      booksTile.onChanged!(true);
      epubTile.onChanged!(true);
      await tester.pump();

      expect(selectAllCount, 1);
      expect(clearAllCount, 1);
      expect(epubOnlyCount, 1);
      expect(pdfOnlyCount, 1);
      expect(bothCount, 1);
      expect(startCount, 1);
      expect(booksValue, isTrue);
      expect(epubValue, isTrue);
    },
  );

  testWidgets(
    'install collections section shows useful estimates when available',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ELibraryInstallCollectionsSection(
                  running: false,
                  selectionWarning: null,
                  installBooks: false,
                  installDevotionals: false,
                  installCommentaries: false,
                  installMiscCollections: false,
                  installPamphlets: false,
                  installPeriodicals: false,
                  installManuscriptReleases: false,
                  installEpub: false,
                  installPdf: false,
                  collectionEstimateLines: const [
                    '124 files • 82 MB',
                    '82 files • 44 MB',
                    '21 files • 9 MB',
                    '18 files • 6 MB',
                    '12 files • 5 MB',
                    '8 files • 3 MB',
                    '4 files • 2 MB',
                  ],
                  selectedDownloadSummary:
                      'Selected download: 124 files • 82 MB',
                  onSelectAllCollectionsAndFormats: _noop,
                  onClearAllSelections: _noop,
                  onSetPresetEpubOnly: _noop,
                  onSetPresetPdfOnly: _noop,
                  onSetPresetBoth: _noop,
                  onStartSetup: _noop,
                  onCancel: _noop,
                  onBooksChanged: _noopBool,
                  onDevotionalsChanged: _noopBool,
                  onCommentariesChanged: _noopBool,
                  onMiscCollectionsChanged: _noopBool,
                  onPamphletsChanged: _noopBool,
                  onPeriodicalsChanged: _noopBool,
                  onManuscriptReleasesChanged: _noopBool,
                  onEpubChanged: _noopBool,
                  onPdfChanged: _noopBool,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('EGW Books'), findsOneWidget);
      expect(find.text('124 files • 82 MB'), findsOneWidget);
      expect(find.text('82 files • 44 MB'), findsOneWidget);
      expect(find.text('Selected download: 124 files • 82 MB'), findsOneWidget);
    },
  );

  testWidgets('install collections cancel remains wired while running', (
    tester,
  ) async {
    var cancelCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ELibraryInstallCollectionsSection(
                running: true,
                selectionWarning: null,
                installBooks: false,
                installDevotionals: false,
                installCommentaries: false,
                installMiscCollections: false,
                installPamphlets: false,
                installPeriodicals: false,
                installManuscriptReleases: false,
                installEpub: false,
                installPdf: false,
                collectionEstimateLines: List<String>.filled(
                  7,
                  '0 files found • size unknown',
                ),
                selectedDownloadSummary:
                    'Selected download: 0 files found • size unknown',
                onSelectAllCollectionsAndFormats: _noop,
                onClearAllSelections: _noop,
                onSetPresetEpubOnly: _noop,
                onSetPresetPdfOnly: _noop,
                onSetPresetBoth: _noop,
                onStartSetup: _noop,
                onCancel: () => cancelCount += 1,
                onBooksChanged: _noopBool,
                onDevotionalsChanged: _noopBool,
                onCommentariesChanged: _noopBool,
                onMiscCollectionsChanged: _noopBool,
                onPamphletsChanged: _noopBool,
                onPeriodicalsChanged: _noopBool,
                onManuscriptReleasesChanged: _noopBool,
                onEpubChanged: _noopBool,
                onPdfChanged: _noopBool,
              ),
            ],
          ),
        ),
      ),
    );

    final cancelButtonFinder = find.widgetWithText(OutlinedButton, 'Cancel');
    final cancelButton = tester.widget<OutlinedButton>(cancelButtonFinder);
    expect(cancelButton.onPressed, isNotNull);

    cancelButton.onPressed!();
    await tester.pump();

    expect(cancelCount, 1);
  });

  testWidgets('advanced section stays collapsed until expanded', (
    tester,
  ) async {
    var removeSelectedCount = 0;
    var removeEpubsCount = 0;
    var removePdfsCount = 0;
    var removeAllCount = 0;
    final selection = LibraryRootSelection(
      path:
          '/var/mobile/Containers/Data/Application/ABC/Documents/BiblicalHeritage/v2',
      exists: true,
      needsReconnect: false,
      source: LibraryRootSource.legacyImplicit,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ELibrarySetupAdvancedSection(
                isIOS: false,
                selection: selection,
                captureFolderPath:
                    '/private/var/mobile/Containers/Data/Application/DEF/Documents/ImportedCaptureClipper',
                captureFolderAccess: 'Saved',
                captureFolderStatus:
                    'CloudFiles folder ready: ImportedCaptureClipper',
                captureImportReport: null,
                loadingCaptureFolder: false,
                loadingCaptureImportAvailability: false,
                storagePolicyLabel: 'Save space',
                onImportConfiguredFolder: _noop,
                onResetImportLocation: _noop,
                onRepairBrokenItems: _noop,
                onReviewImports: _noop,
                onClearImportLocation: _noop,
                onTestBroadAnyFilePicker: _noop,
                onPickScannedHtmlFile: _noop,
                setupReportPath: '/tmp/setup-report.json',
                indexReportPath: '/tmp/index-report.json',
                storageMaintenanceWidget: DownloadedFileMaintenanceSection(
                  loadingStorageSummary: false,
                  storageSummary: const ELibraryStorageSummary(
                    epubCount: 3,
                    epubSizeBytes: 1_024,
                    pdfCount: 2,
                    pdfSizeBytes: 2_048,
                  ),
                  running: false,
                  removingFiles: false,
                  canRemoveFiles: true,
                  onRemoveSelected: () => removeSelectedCount += 1,
                  onRemoveEpubs: () => removeEpubsCount += 1,
                  onRemovePdfs: () => removePdfsCount += 1,
                  onRemoveAll: () => removeAllCount += 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Legacy implicit'), findsNothing);
    expect(find.textContaining('/var/mobile/Containers'), findsNothing);
    expect(find.text('Library Diagnostics'), findsNothing);
    expect(find.text('CaptureClipper Diagnostics'), findsNothing);
    expect(find.text('Maintenance'), findsNothing);
    expect(find.text('Developer Tools'), findsNothing);
    expect(find.text('Downloaded File Maintenance'), findsNothing);
    expect(find.text('Folder Layout'), findsNothing);
    expect(find.text('Clear Saved Import Location'), findsNothing);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(find.text('Library Diagnostics'), findsOneWidget);
    expect(find.text('Library path'), findsOneWidget);
    expect(
      find.text(
        '/var/mobile/Containers/Data/Application/ABC/Documents/BiblicalHeritage/v2',
      ),
      findsOneWidget,
    );
    expect(find.text('Root source'), findsOneWidget);
    expect(find.text('Legacy implicit'), findsOneWidget);
    expect(find.text('Root state'), findsOneWidget);
    expect(find.text('Legacy Library Root detected.'), findsOneWidget);
    expect(find.text('Access status'), findsOneWidget);
    expect(find.text('No bookmark saved'), findsOneWidget);
    expect(find.text('Cleanup policy'), findsOneWidget);
    expect(find.text('Save space'), findsOneWidget);
    expect(find.text('CaptureClipper Diagnostics'), findsOneWidget);
    expect(find.text('Import path'), findsOneWidget);
    expect(
      find.text(
        '/private/var/mobile/Containers/Data/Application/DEF/Documents/ImportedCaptureClipper',
      ),
      findsOneWidget,
    );
    expect(find.text('Folder access'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Import folder status'), findsOneWidget);
    expect(
      find.text('CloudFiles folder ready: ImportedCaptureClipper'),
      findsOneWidget,
    );
    expect(find.text('Available imports'), findsOneWidget);
    expect(find.text('No availability report'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Import Ready Books'), findsNothing);
    expect(find.text('Reset Import Location'), findsOneWidget);
    expect(find.text('Repair Broken CaptureClipper Items'), findsOneWidget);
    expect(find.text('Clear Saved Import Location'), findsOneWidget);
    expect(
      find.text(
        'Forgets the saved import location. It does not delete source files.',
      ),
      findsOneWidget,
    );
    expect(find.text('Review Imports'), findsOneWidget);
    expect(find.text('Developer Tools'), findsOneWidget);
    expect(find.text('Test Broad Any File Picker'), findsOneWidget);
    expect(find.text('Pick Scanned HTML File'), findsOneWidget);
    expect(find.text('Diagnostic Reports'), findsOneWidget);
    expect(find.text('/tmp/setup-report.json'), findsOneWidget);
    expect(find.text('/tmp/index-report.json'), findsOneWidget);
    expect(find.text('Downloaded File Maintenance'), findsOneWidget);
    expect(
      find.text(
        'Review or remove downloaded eLibrary files. Your tags, notes, highlights, bookmarks, and saved presentations are not removed.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Downloaded library files: 3 EPUB (1.00 KB), 2 PDF (2.00 KB), total 5 files (3.00 KB).',
      ),
      findsOneWidget,
    );
    expect(find.text('Remove Selected'), findsOneWidget);
    expect(find.text('Remove EPUBs'), findsOneWidget);
    expect(find.text('Remove PDFs'), findsOneWidget);
    expect(find.text('Remove All Downloaded Library Files'), findsOneWidget);
    expect(find.text('Folder Layout'), findsOneWidget);
    expect(find.text('EGW EPUBs'), findsOneWidget);
    expect(find.text('LibraryRoot/ePubs/EGW/'), findsOneWidget);
    expect(find.text('EGW PDFs'), findsOneWidget);
    expect(find.text('LibraryRoot/PDFs/EGW/'), findsOneWidget);
    expect(
      find.text('The setup screen uses the simplified EGW folder layout.'),
      findsOneWidget,
    );

    final removeSelectedButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Remove Selected'),
    );
    final removeEpubsButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Remove EPUBs'),
    );
    final removePdfsButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Remove PDFs'),
    );
    final removeAllButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Remove All Downloaded Library Files'),
    );

    expect(removeSelectedButton.onPressed, isNotNull);
    expect(removeEpubsButton.onPressed, isNotNull);
    expect(removePdfsButton.onPressed, isNotNull);
    expect(removeAllButton.onPressed, isNotNull);

    removeSelectedButton.onPressed!();
    removeEpubsButton.onPressed!();
    removePdfsButton.onPressed!();
    removeAllButton.onPressed!();
    await tester.pump();

    expect(removeSelectedCount, 1);
    expect(removeEpubsCount, 1);
    expect(removePdfsCount, 1);
    expect(removeAllCount, 1);
  });

  testWidgets(
    'set-aside books render as a compact notice with dialog details',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryNeedsAttentionCard(
              items: const [
                LibraryNeedsAttentionEntry(
                  title: 'Broken book',
                  fileName: 'broken-book.epub',
                  reason: 'No readable text content found',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('1 unreadable book set aside'), findsOneWidget);
      expect(
        find.text('Hidden from the library; original files were preserved.'),
        findsOneWidget,
      );
      expect(find.text('Broken book'), findsNothing);
      expect(find.text('No readable book content was found.'), findsNothing);
      expect(find.text('Review'), findsOneWidget);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('Broken book'), findsOneWidget);
      expect(
        find.text('Reason: No readable book content was found.'),
        findsOneWidget,
      );
    },
  );
}

void _noop() {}

void _noopBool(bool? value) {}
