import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/library/presentation/library_screen.dart';
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_folder_service.dart';

PioneerCapturedHtmlAvailableImportReport _emptyImportReport() {
  return PioneerCapturedHtmlAvailableImportReport(
    rootPath: '/tmp/capture',
    imports: const [],
    completedAt: DateTime.utc(2026, 1, 1),
    message: 'No CaptureClipper imports are currently available.',
  );
}

Future<void> _pumpLibrary(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: LibraryScreen(initialCapturedImportReport: _emptyImportReport()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
    binding.platformDispatcher.views.first.resetViewInsets();
  });

  testWidgets('phone uses its normal fixed-controls layout without keyboard', (
    tester,
  ) async {
    await _pumpLibrary(tester, const Size(390, 844));

    expect(find.byKey(const ValueKey('library-standard-layout')), findsOne);
    expect(find.byKey(const ValueKey('library-keyboard-scroll')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone library scrolls safely while keyboard is open', (
    tester,
  ) async {
    await _pumpLibrary(tester, const Size(390, 844));
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await tester.pumpAndSettle();

    // The outer container must stay the same widget (same key/type)
    // whether or not the keyboard is open, so a focused text field inside
    // it is never torn down and recreated when the keyboard appears.
    expect(find.byKey(const ValueKey('library-standard-layout')), findsOne);
    expect(find.text('Books'), findsOne);
    expect(find.text('Recent'), findsOne);
    expect(find.text('Shelf'), findsOne);
    expect(find.text('List'), findsOne);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const ValueKey('library-standard-layout')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-standard-layout')), findsOne);
  });

  testWidgets(
    'search field keeps its input connection alive when the keyboard opens',
    (tester) async {
      await _pumpLibrary(tester, const Size(390, 844));

      final fieldFinder = find.byType(TextField).first;
      await tester.tap(fieldFinder);
      await tester.pump();
      final editableTextFinder = find.descendant(
        of: fieldFinder,
        matching: find.byType(EditableText),
      );
      final stateBeforeKeyboard = tester.state<EditableTextState>(
        editableTextFinder,
      );

      // Simulate the keyboard opening on a narrow (phone-width) screen,
      // which previously swapped the search field's ancestor container
      // to a differently-keyed/typed widget and tore down its
      // EditableText mid-focus, closing the platform text input
      // connection out from under the user.
      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      await tester.pumpAndSettle();

      final stateAfterKeyboard = tester.state<EditableTextState>(
        editableTextFinder,
      );
      expect(
        identical(stateBeforeKeyboard, stateAfterKeyboard),
        isTrue,
        reason:
            'The search field\'s EditableText must not be disposed and '
            'recreated when the keyboard opens, or its platform text '
            'input connection (and the on-screen keyboard) gets closed.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long and empty searches do not overflow with keyboard open', (
    tester,
  ) async {
    await _pumpLibrary(tester, const Size(390, 844));
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    await tester.enterText(
      field,
      'A very long title search that must remain on one safe editable line',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(field, 'No title should match this unique query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layout remains unchanged with a keyboard inset', (
    tester,
  ) async {
    await _pumpLibrary(tester, const Size(1024, 768));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('library-standard-layout')), findsOne);
    expect(find.byKey(const ValueKey('library-keyboard-scroll')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
