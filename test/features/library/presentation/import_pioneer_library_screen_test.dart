import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/library/data/canonical_activation.dart';
import 'package:studybible2/features/library/data/library_acquisition_batch_runner.dart';
import 'package:studybible2/features/library/presentation/import_pioneer_library_screen.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_bulk_import_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_folder_inventory_service.dart';

PioneerEpubInventoryEntry _entry({
  required String id,
  required bool unchanged,
  bool valid = true,
}) {
  return PioneerEpubInventoryEntry(
    sourceRelativePath: '$id.epub',
    absolutePath: '/synthetic/$id.epub',
    fileName: '$id.epub',
    fileSizeBytes: 100,
    sha256: id.padRight(64, '0'),
    isStructurallyValid: valid,
    rejectionReason: valid ? null : 'Synthetic unreadable file',
    title: 'Synthetic Book $id',
    author: 'Test Author',
    language: 'en',
    identifier: id,
    hasCover: true,
    hasNavigation: true,
    spineItemCount: 1,
    readableContentCount: 1,
    libraryItemId: id,
    reusesLegacyLibraryItemIdentity: false,
    duplicateGroupKey: id,
    alreadyImported: unchanged,
    isUnchanged: unchanged,
  );
}

PioneerEpubFolderInventory _inventory(
  Directory folder, {
  required List<PioneerEpubInventoryEntry> entries,
}) {
  return PioneerEpubFolderInventory(
    folderPath: folder.path,
    scannedAt: DateTime.utc(2026),
    entries: entries,
    skippedNonEpubCount: 0,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Directory folder,
  required PioneerEpubFolderInventory inventory,
  PioneerImportPreparer? prepare,
  PioneerBatchActivator? activate,
  WidgetBuilder? advancedToolsBuilder,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ImportPioneerLibraryScreen(
        loadSavedFolder: () async => folder.path,
        surveyFolder: (selected, {onProgress}) async => inventory,
        prepareImport: prepare,
        activateBatch: activate,
        advancedToolsBuilder: advancedToolsBuilder,
      ),
    ),
  );
  // Two frames allow the injected async folder load and inventory survey to
  // complete without waiting on the indeterminate "Checking" animation.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'first-time view offers a ZIP action and a folder fallback, no counters',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImportPioneerLibraryScreen(loadSavedFolder: () async => null),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pioneer Library'), findsOneWidget);
      expect(find.byKey(const Key('pioneer-zip-action')), findsOneWidget);
      expect(find.text('Choose Pioneer Library ZIP File'), findsOneWidget);
      expect(find.byKey(const Key('pioneer-primary-action')), findsOneWidget);
      expect(find.text('Add a Book File (EPUB)'), findsOneWidget);
      expect(find.text('Advanced Tools'), findsOneWidget);
      for (final technical in const [
        'Usable',
        'Text capture',
        'Capture needed',
        'Source needed',
        'Selected',
        'Select All',
        'Import Selected',
        'Catalog Details',
      ]) {
        expect(find.textContaining(technical), findsNothing);
      }
    },
  );

  testWidgets('choosing a ZIP file extracts, scans, and imports in one step', (
    tester,
  ) async {
    final extractedFolder = Directory.systemTemp.createTempSync(
      'pioneer_ui_zip_extracted_',
    );
    addTearDown(() => extractedFolder.deleteSync(recursive: true));
    final inventory = _inventory(
      extractedFolder,
      entries: [_entry(id: 'new', unchanged: false)],
    );
    var extractCalls = 0;
    String? extractedFromZipPath;
    var prepareCalls = 0;
    var activateCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ImportPioneerLibraryScreen(
          loadSavedFolder: () async => null,
          pickZipFile: () async => '/synthetic/Pioneer-Library-EPUBs.zip',
          extractZip: (zipPath) async {
            extractCalls++;
            extractedFromZipPath = zipPath;
            return extractedFolder.path;
          },
          surveyFolder: (selected, {onProgress}) async {
            expect(selected.path, extractedFolder.path);
            return inventory;
          },
          saveFolder: (path, bookmark) async {},
          prepareImport:
              ({required inventory, onProgress, shouldContinue}) async {
                prepareCalls++;
                return const PioneerEpubImportPreparation(
                  targets: <LibraryAcquisitionBatchTarget>[],
                  preparationFailures: <LibraryAcquisitionOutcome>[],
                  skippedUnchangedCount: 0,
                  skippedInvalidCount: 0,
                );
              },
          activateBatch: (targets, {onProgress, shouldContinue}) async {
            activateCalls++;
            return const LibraryAcquisitionBatchResult(
              targets: <LibraryAcquisitionBatchTarget>[],
              outcomes: <LibraryAcquisitionOutcome>[],
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('pioneer-zip-action')));
    await tester.pumpAndSettle();

    expect(extractCalls, 1);
    expect(extractedFromZipPath, '/synthetic/Pioneer-Library-EPUBs.zip');
    // No second tap on "Import / Update Pioneer Library" — picking the
    // ZIP file goes straight through to import.
    expect(prepareCalls, 1);
    expect(activateCalls, 1);
    expect(find.text('Pioneer Library Updated'), findsOneWidget);
  });

  testWidgets(
    'returning user sees ready summary and one import/update action',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('pioneer_ui_ready_');
      addTearDown(() => folder.deleteSync(recursive: true));
      final inventory = _inventory(
        folder,
        entries: [_entry(id: 'one', unchanged: true)],
      );

      await _pumpScreen(tester, folder: folder, inventory: inventory);

      expect(find.text('Your Pioneer Library is ready.'), findsOneWidget);
      expect(find.text('1 books available'), findsOneWidget);
      expect(find.text('Import / Update Pioneer Library'), findsOneWidget);
      expect(find.byKey(const Key('pioneer-primary-action')), findsOneWidget);
    },
  );

  testWidgets(
    'primary action uses injected production-service boundaries and skips unchanged',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('pioneer_ui_import_');
      addTearDown(() => folder.deleteSync(recursive: true));
      final inventory = _inventory(
        folder,
        entries: [
          _entry(id: 'current', unchanged: true),
          _entry(id: 'new', unchanged: false),
        ],
      );
      var prepareCalls = 0;
      var activateCalls = 0;

      await _pumpScreen(
        tester,
        folder: folder,
        inventory: inventory,
        prepare: ({required inventory, onProgress, shouldContinue}) async {
          prepareCalls++;
          expect(inventory.needsImport.length, 1);
          return const PioneerEpubImportPreparation(
            targets: <LibraryAcquisitionBatchTarget>[],
            preparationFailures: <LibraryAcquisitionOutcome>[],
            skippedUnchangedCount: 1,
            skippedInvalidCount: 0,
          );
        },
        activate: (targets, {onProgress, shouldContinue}) async {
          activateCalls++;
          return const LibraryAcquisitionBatchResult(
            targets: <LibraryAcquisitionBatchTarget>[],
            outcomes: <LibraryAcquisitionOutcome>[],
          );
        },
      );

      await tester.tap(find.text('Import / Update Pioneer Library'));
      await tester.pumpAndSettle();

      expect(prepareCalls, 1);
      expect(activateCalls, 1);
      expect(find.text('Pioneer Library Updated'), findsOneWidget);
      expect(find.text('1 already up to date'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    },
  );

  testWidgets('partial failure stays friendly and offers details', (
    tester,
  ) async {
    final folder = Directory.systemTemp.createTempSync('pioneer_ui_partial_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final inventory = _inventory(
      folder,
      entries: [_entry(id: 'bad', unchanged: false)],
    );
    final target = const LibraryAcquisitionBatchTarget(
      libraryItemId: 'bad',
      relativePath: 'synthetic/bad.epub',
      title: 'Synthetic Book',
    );

    await _pumpScreen(
      tester,
      folder: folder,
      inventory: inventory,
      prepare: ({required inventory, onProgress, shouldContinue}) async =>
          PioneerEpubImportPreparation(
            targets: [target],
            preparationFailures: const <LibraryAcquisitionOutcome>[],
            skippedUnchangedCount: 0,
            skippedInvalidCount: 0,
          ),
      activate: (targets, {onProgress, shouldContinue}) async =>
          LibraryAcquisitionBatchResult(
            targets: [target],
            outcomes: const [
              LibraryAcquisitionOutcome(
                libraryItemId: 'bad',
                phase: LibraryAcquisitionPhase.failedImport,
                userSummary: 'This source file needs attention.',
                technicalDetail: 'synthetic technical detail',
                retryable: true,
                hasReadableCanonicalGeneration: false,
                sourceFilePresent: true,
              ),
            ],
          ),
    );

    await tester.tap(find.text('Import / Update Pioneer Library'));
    await tester.pumpAndSettle();

    expect(find.text('Pioneer Library Updated'), findsOneWidget);
    expect(find.text('1 file needs attention'), findsOneWidget);
    expect(find.text('View Details'), findsOneWidget);
    expect(find.textContaining('synthetic technical detail'), findsNothing);
  });

  testWidgets('Advanced Tools is reachable and returns to simple screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPioneerLibraryScreen(
          loadSavedFolder: () async => null,
          advancedToolsBuilder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Advanced')),
            body: const Text('Legacy Pioneer Catalog'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Advanced Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Legacy Pioneer Catalog'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Choose Pioneer Library ZIP File'), findsOneWidget);
  });

  for (final layout in <String, Size>{
    'phone': const Size(390, 844),
    'iPad': const Size(1024, 1366),
    'macOS': const Size(1440, 900),
  }.entries) {
    testWidgets('${layout.key} layout remains usable', (tester) async {
      final folder = Directory.systemTemp.createTempSync(
        'pioneer_ui_${layout.key}_',
      );
      addTearDown(() => folder.deleteSync(recursive: true));
      await _pumpScreen(
        tester,
        folder: folder,
        inventory: _inventory(
          folder,
          entries: [_entry(id: layout.key, unchanged: true)],
        ),
        size: layout.value,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('pioneer-primary-action')), findsOneWidget);
      expect(find.text('Advanced Tools'), findsOneWidget);
    });
  }
}
