import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/presentation/elibrary_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the CaptureClipper import button when labeled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureClipperImportButton(
            label: 'Import 1 Book',
            busy: false,
            onPressed: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Import 1 Book'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('hides the CaptureClipper import button when unlabeled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureClipperImportButton(
            label: null,
            busy: false,
            onPressed: _noop,
          ),
        ),
      ),
    );

    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Import 1 Book'), findsNothing);
  });
}

void _noop() {}
