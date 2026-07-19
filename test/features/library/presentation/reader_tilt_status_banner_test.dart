import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controls.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_preferences.dart';

void main() {
  Future<ReaderTiltAutoScrollController> pumpBanner(
    WidgetTester tester, {
    ReaderTiltStatusBannerMode mode = ReaderTiltStatusBannerMode.autoHide,
    String readerName = 'Reader',
  }) async {
    final controller = ReaderTiltAutoScrollController(
      motionSource: FakeReaderTiltMotionSource(),
      scrollTarget: CallbackReaderAutoScrollTarget(),
      preferences: ReaderTiltPreferences(statusBannerMode: mode),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text(readerName),
              ReaderTiltAutoScrollActiveIndicator(controller: controller),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (controller.isActive) controller.showStatusBanner();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await controller.activate();
    await tester.pump();
    return controller;
  }

  Future<void> shutDownBanner(
    WidgetTester tester,
    ReaderTiltAutoScrollController controller,
  ) async {
    await controller.stop();
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('default banner auto-hides after seven seconds without a gap', (
    tester,
  ) async {
    final controller = await pumpBanner(tester);
    expect(find.textContaining('Tilt Auto-scroll'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Tilt Auto-scroll'), findsNothing);
    expect(
      tester.getSize(find.byType(ReaderTiltAutoScrollActiveIndicator)).height,
      0,
    );
    await shutDownBanner(tester, controller);
  });

  testWidgets('always visible banner never hides', (tester) async {
    final controller = await pumpBanner(
      tester,
      mode: ReaderTiltStatusBannerMode.alwaysVisible,
    );
    await tester.pump(const Duration(seconds: 20));
    expect(find.textContaining('Tilt Auto-scroll'), findsOneWidget);
    await shutDownBanner(tester, controller);
  });

  testWidgets('always hidden banner never appears', (tester) async {
    final controller = await pumpBanner(
      tester,
      mode: ReaderTiltStatusBannerMode.alwaysHidden,
    );
    controller.showStatusBanner();
    await tester.pump();
    expect(find.textContaining('Tilt Auto-scroll'), findsNothing);
    await shutDownBanner(tester, controller);
  });

  testWidgets('reader tap redisplays an auto-hidden active banner', (
    tester,
  ) async {
    final controller = await pumpBanner(tester);
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Tilt Auto-scroll'), findsNothing);

    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(find.textContaining('Tilt Auto-scroll'), findsOneWidget);
    await shutDownBanner(tester, controller);
  });

  testWidgets('disabling and enabling redisplay status', (tester) async {
    final controller = await pumpBanner(tester);
    await tester.pump(const Duration(seconds: 8));
    await controller.stop();
    await tester.pump();
    expect(find.text('Tilt Auto-scroll • Off'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
    await controller.activate();
    await tester.pump();
    expect(find.textContaining('Calibrating'), findsOneWidget);
    await shutDownBanner(tester, controller);
  });

  testWidgets('Bible and eLibrary instances use the same banner behavior', (
    tester,
  ) async {
    final bibleController = await pumpBanner(tester, readerName: 'Bible');
    expect(find.text('Bible'), findsOneWidget);
    expect(find.textContaining('Tilt Auto-scroll'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Tilt Auto-scroll'), findsNothing);
    await bibleController.stop();

    final libraryController = await pumpBanner(tester, readerName: 'eLibrary');
    expect(find.text('eLibrary'), findsOneWidget);
    expect(find.textContaining('Tilt Auto-scroll'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Tilt Auto-scroll'), findsNothing);
    await shutDownBanner(tester, libraryController);
  });
}
