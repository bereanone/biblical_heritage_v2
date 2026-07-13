import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/presentation/elibrary_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hides the saved CaptureClipper bookmark token', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureClipperFolderDetails(
            loading: false,
            path:
                '/Users/deanbowen/Library/CloudStorage/OneDrive-Personal/CloudFiles',
            access: 'Saved',
            status: 'CaptureClipper folder ready.',
          ),
        ),
      ),
    );

    expect(find.textContaining('bookmark-token'), findsNothing);
    expect(
      find.text(
        'Folder path: /Users/deanbowen/Library/CloudStorage/OneDrive-Personal/CloudFiles',
      ),
      findsOneWidget,
    );
    expect(find.text('Folder access: Saved'), findsOneWidget);
    expect(find.text('CaptureClipper folder ready.'), findsOneWidget);
  });

  testWidgets(
    'shows import-location change and reset controls when the folder is legacy',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CloudFilesFolderPickerControls(
              busy: false,
              isLegacy: true,
              showHtmlFallback: false,
              onChangeFolder: _noop,
              onResetFolder: _noop,
              onPickScannedHtmlFile: _noop,
            ),
          ),
        ),
      );

      expect(find.text('Change Import Location'), findsOneWidget);
      expect(find.text('Reset Import Location'), findsOneWidget);
      expect(
        find.text(
          'The app Documents folder is a legacy fallback, not the CloudFiles folder. '
          'Choose or reset it to point at OneDrive/CloudFiles.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows the iOS book package import button with guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureClipperPackageImportControls(
            busy: false,
            onImportPackage: _noop,
          ),
        ),
      ),
    );

    expect(find.textContaining('DEV PACKAGE PICKER BUILD'), findsNothing);
    expect(find.textContaining('Package picker mode:'), findsNothing);
    expect(find.text('Import Book Package'), findsOneWidget);
    expect(
      find.text(
        'Select one .studybook or .studycollection file from OneDrive, iCloud Drive, '
        'Google Drive, or On My iPad. StudyBible2 copies and unpacks it '
        'locally. Your cloud file is not changed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('disables the book package import button while busy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureClipperPackageImportControls(
            busy: true,
            onImportPackage: _noop,
          ),
        ),
      ),
    );

    final packageButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import Book Package'),
    );
    expect(packageButton.onPressed, isNull);
  });

  testWidgets('shows the iOS copy-import buttons with OneDrive guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureClipperFileImportControls(
            busy: false,
            onPickHtmlFiles: _noop,
            onPickRelatedFiles: _noop,
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Choose one or more CaptureClipper book packages from OneDrive. '
        'StudyBible2 will import new or updated books and leave the originals unchanged.',
      ),
      findsOneWidget,
    );
    expect(find.text('Import Captured Books'), findsOneWidget);
    expect(find.text('Add Related Book Files'), findsOneWidget);
  });

  testWidgets('disables the iOS copy-import buttons while busy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureClipperFileImportControls(
            busy: true,
            onPickHtmlFiles: _noop,
            onPickRelatedFiles: _noop,
          ),
        ),
      ),
    );

    final importButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import Captured Books'),
    );
    expect(importButton.onPressed, isNull);
    final relatedButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Add Related Book Files'),
    );
    expect(relatedButton.onPressed, isNull);
  });

  testWidgets('shows the OneDrive guidance and HTML fallback when available', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CloudFilesFolderPickerControls(
            busy: false,
            isLegacy: false,
            showHtmlFallback: true,
            onChangeFolder: _noop,
            onResetFolder: _noop,
            onPickScannedHtmlFile: _noop,
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Use "Change Import Location" for iCloud Drive, On My iPad, '
        'and other providers that allow folder access. If OneDrive '
        'appears faded here, use "Import Captured Books" from OneDrive '
        'above instead.',
      ),
      findsOneWidget,
    );
    expect(find.text('Change Import Location'), findsOneWidget);
    expect(find.text('Pick Scanned HTML File'), findsOneWidget);
  });
}

void _noop() {}
