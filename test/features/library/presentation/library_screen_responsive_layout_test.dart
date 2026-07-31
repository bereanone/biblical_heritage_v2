import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/library/presentation/library_screen.dart';
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_folder_service.dart';

// NOTE ON COVERAGE: these tests use the same `initialCapturedImportReport`
// shortcut as library_screen_keyboard_layout_test.dart, which makes
// LibraryScreen skip its real `_load()` (DB) call and keep `_items` empty.
// That shortcut is required here: driving `_load()` for real inside a
// `testWidgets` body never completes in this codebase's current
// sqflite_common_ffi test setup (confirmed by direct probing — real DB
// calls complete instantly under `tester.runAsync()`, i.e. on a real Zone,
// but never complete when awaited from a widget's own initState under the
// widget-test fake clock; `download_ellen_white_library_screen_test.dart`
// already documents hitting the same class of issue for a different
// screen). Because of that, behaviors that require real catalog items —
// the alphabet filter's contents, letter selection, and the scroll-driven
// secondary-controls collapse/restore driven by a genuinely scrollable book
// list — cannot be exercised here and must be confirmed by the physical,
// on-device verification pass instead. What *is* covered below is the
// layout/branch-selection logic itself: which control set renders at a
// given window size, that navigation is never fully hidden, and that
// resizing/keyboard/back-navigation don't throw.

const _kTallDesktop = Size(1200, 1000);
const _kShortDesktop = Size(1200, 500);
const _kIphone = Size(390, 844);
const _kIpad = Size(768, 1024);
const _kAndroidPhone = Size(412, 915);
const _kAndroidTablet = Size(800, 1280);

PioneerCapturedHtmlAvailableImportReport _emptyImportReport() {
  return PioneerCapturedHtmlAvailableImportReport(
    rootPath: '/tmp/capture',
    imports: const [],
    completedAt: DateTime.utc(2026, 1, 1),
    message: 'No CaptureClipper imports are currently available.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  Future<void> pumpLibrary(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(initialCapturedImportReport: _emptyImportReport()),
      ),
    );
    await tester.pumpAndSettle();
  }

  final stickyToolbarFinder = find.byKey(
    const ValueKey('library-sticky-toolbar'),
  );
  final secondaryControlsFinder = find.byKey(
    const ValueKey('library-secondary-controls'),
  );
  final standardLayoutFinder = find.byKey(
    const ValueKey('library-standard-layout'),
  );

  testWidgets('1. tall desktop window keeps the full control set fixed and '
      'visible, with no compact sticky toolbar', (tester) async {
    await pumpLibrary(tester, _kTallDesktop);

    expect(find.text('eLibrary'), findsOne);
    expect(find.text('Library'), findsOne);
    expect(find.text('Books'), findsOne);
    expect(find.text('Recent'), findsOne);
    expect(find.text('Shelf'), findsOne);
    expect(find.text('List'), findsOne);
    expect(standardLayoutFinder, findsOne);
    expect(stickyToolbarFinder, findsNothing);
    expect(secondaryControlsFinder, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '2. deep interaction on a tall desktop window never removes navigation',
    (tester) async {
      await pumpLibrary(tester, _kTallDesktop);

      // Repeated rebuilds (simulating deep scroll-driven interaction/state
      // churn) must not disturb the fixed control panel on a large window.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('eLibrary'), findsOne);
      expect(find.text('Library'), findsOne);
      expect(find.text('Books'), findsOne);
      expect(find.text('Shelf'), findsOne);
      expect(find.text('List'), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '3-4. compact layout renders a sticky toolbar with Books/Recent and '
    'Shelf/List always visible, plus the secondary control panel',
    (tester) async {
      await pumpLibrary(tester, _kIphone);

      expect(stickyToolbarFinder, findsOne);
      expect(secondaryControlsFinder, findsOne);
      expect(find.text('Books'), findsOne);
      expect(find.text('Recent'), findsOne);
      expect(find.text('Shelf'), findsOne);
      expect(find.text('List'), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('9. Shelf and List toggle without throwing', (tester) async {
    await pumpLibrary(tester, _kTallDesktop);

    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Shelf'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '10. returning from a pushed route (as the reader does) leaves the '
    'sticky toolbar and tab/view controls usable',
    (tester) async {
      await pumpLibrary(tester, _kIphone);
      expect(stickyToolbarFinder, findsOne);

      // LibraryBookReaderScreen is opened via a plain route push (see
      // _openBookReader), so LibraryScreen's State survives for as long as
      // the pushed route is on top. Exercise that same push/pop mechanism
      // directly rather than the full reader stack, which needs real DB
      // items and is out of scope for this layout fix.
      final navigator = Navigator.of(
        tester.element(find.byType(LibraryScreen)),
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Reader stand-in')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reader stand-in'), findsOne);

      navigator.pop();
      await tester.pumpAndSettle();

      expect(stickyToolbarFinder, findsOne);
      expect(find.text('Books'), findsOne);
      expect(find.text('Shelf'), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '11. resizing tall -> short -> tall switches between the full and '
    'compact layouts without exceptions',
    (tester) async {
      await pumpLibrary(tester, _kTallDesktop);
      expect(stickyToolbarFinder, findsNothing);

      tester.view.physicalSize = _kShortDesktop;
      await tester.pumpAndSettle();
      expect(stickyToolbarFinder, findsOne);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = _kTallDesktop;
      await tester.pumpAndSettle();
      expect(stickyToolbarFinder, findsNothing);
      expect(find.text('Books'), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('13. phone, tablet, and desktop window sizes all render a usable '
      'layout without overflow or exceptions', (tester) async {
    for (final size in [
      _kIphone,
      _kIpad,
      _kAndroidPhone,
      _kAndroidTablet,
      _kTallDesktop,
    ]) {
      await pumpLibrary(tester, size);
      expect(find.text('Books'), findsOne, reason: 'at size $size');
      expect(find.text('Shelf'), findsOne, reason: 'at size $size');
      expect(find.text('List'), findsOne, reason: 'at size $size');
      expect(tester.takeException(), isNull, reason: 'at size $size');
    }
  });
}
