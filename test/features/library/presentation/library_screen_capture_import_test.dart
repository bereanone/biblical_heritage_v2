import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/library/presentation/library_screen.dart';
import 'package:studybible2/features/utilities/data/pioneer_capture_folder_metadata.dart';
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_folder_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_html_capture_folder_scanner.dart';

PioneerCapturedHtmlAvailableImportReport _readyImportReport() {
  const metadata = PioneerCaptureFolderMetadata(
    title: 'Captured Sermon',
    abbreviation: 'CS',
    workId: 'captured_sermon',
    sourceType: 'pioneer_captured_html',
    sourceSite: 'user_capture',
    sourceUrl: 'https://example.invalid/captured-sermon',
    contributors: <PioneerCaptureFolderContributorData>[
      PioneerCaptureFolderContributorData(
        name: 'E. G. White',
        role: 'author',
        sortOrder: 1,
        isPrimary: true,
      ),
    ],
  );
  const preview = PioneerHtmlCaptureFolderPreview(
    folderPath: '/tmp/capture/captured_sermon',
    folderName: 'captured_sermon',
    metadata: metadata,
    htmlFiles: <String>['capture.html'],
    imageFiles: <String>[],
    availableFileNames: <String>['capture.html'],
    preferredCoverImagePath: null,
    detectedTitle: 'Captured Sermon',
    detectedAuthor: 'E. G. White',
    detectedAbbreviation: 'CS',
    firstRef: '1',
    lastRef: '2',
    refCount: 2,
    duplicateRefCount: 0,
    chapterHeadingCount: 1,
    firstChapterLabel: 'Chapter 1',
    lastChapterLabel: 'Chapter 2',
    isValid: true,
    warnings: <String>[],
    validationReasons: <String>[],
    importStatus: PioneerHtmlCaptureImportStatus.newImport,
  );
  return PioneerCapturedHtmlAvailableImportReport(
    rootPath: '/tmp/capture',
    imports: <PioneerCapturedHtmlAvailableImport>[
      PioneerCapturedHtmlAvailableImport(
        preview: preview,
        existingLibraryItemId: null,
      ),
    ],
    completedAt: DateTime.utc(2026, 1, 1),
    message: '1 CaptureClipper book is ready to import',
  );
}

PioneerCapturedHtmlAvailableImportReport _emptyImportReport() {
  return PioneerCapturedHtmlAvailableImportReport(
    rootPath: '/tmp/capture',
    imports: const <PioneerCapturedHtmlAvailableImport>[],
    completedAt: DateTime.utc(2026, 1, 1),
    message: 'No CaptureClipper imports are currently available.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows the import prompt and keeps the import button visible after Not Now',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            initialCapturedImportReport: _readyImportReport(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('1 CaptureClipper book is ready to import'),
        findsOneWidget,
      );
      expect(find.text('Import Ready'), findsOneWidget);

      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();

      expect(
        find.text('1 CaptureClipper book is ready to import'),
        findsNothing,
      );
      expect(find.text('Import Ready'), findsOneWidget);
    },
  );

  testWidgets('hides the import button when no ready folders exist', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          initialCapturedImportReport: _emptyImportReport(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Import Ready'), findsNothing);
    expect(
      find.textContaining('CaptureClipper book is ready to import'),
      findsNothing,
    );
  });
}
