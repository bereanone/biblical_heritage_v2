import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controls.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';
import 'package:studybible2/features/reader/presentation/viewer_bottom_bar.dart';

void main() {
  testWidgets(
    'Bible bottom bar exposes one canonical tilt control when steady is also available',
    (tester) async {
      final motion = FakeReaderTiltMotionSource();
      final target = CallbackReaderAutoScrollTarget();
      final tiltController = ReaderTiltAutoScrollController(
        motionSource: motion,
        scrollTarget: target,
      );
      final macController = MacReaderAutoScrollController(
        scrollTarget: target,
        driveFrames: false,
      );
      var toggleCount = 0;
      var settingsCount = 0;
      addTearDown(() async {
        macController.dispose();
        tiltController.dispose();
        await motion.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ViewerBottomBar(
              themeMode: AppThemeMode.sepia,
              onToggleThemeMode: () {},
              bookNumber: 1,
              interlinearEnabled: false,
              onToggleInterlinear: () {},
              onMode: () {},
              onHistory: () {},
              onLibrary: () {},
              onDecreaseFont: () {},
              onIncreaseFont: () {},
              tiltAutoScrollController: tiltController,
              onToggleTiltAutoScroll: () => toggleCount++,
              onOpenTiltAutoScrollSettings: () => settingsCount++,
              macAutoScrollController: macController,
              onToggleMacAutoScroll: macController.toggle,
              onOpenMacAutoScrollSettings: () {},
              onCommentary: () {},
              canDecreaseFont: true,
              canIncreaseFont: true,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      );

      expect(find.byTooltip('Autoscroll'), findsNothing);
      expect(find.byTooltip('Tilt Auto-scroll'), findsOneWidget);
      expect(find.byIcon(Icons.swap_vert_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Tilt Auto-scroll'));
      expect(toggleCount, 1);
      final hold = await tester.startGesture(
        tester.getCenter(find.byTooltip('Tilt Auto-scroll')),
      );
      await tester.pump(ReaderTiltAutoScrollIconButton.longPressDuration);
      await hold.up();
      await tester.pump();
      expect(settingsCount, 1);
    },
  );

  for (final width in [300.0, 390.0, 800.0]) {
    testWidgets('tilt control follows A+ without overflow at $width px', (
      tester,
    ) async {
      final motion = FakeReaderTiltMotionSource();
      final controller = ReaderTiltAutoScrollController(
        motionSource: motion,
        scrollTarget: CallbackReaderAutoScrollTarget(),
      );
      var settingsOpenCount = 0;
      await tester.binding.setSurfaceSize(Size(width, 180));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        controller.dispose();
        await motion.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ViewerBottomBar(
              themeMode: AppThemeMode.sepia,
              onToggleThemeMode: () {},
              bookNumber: 1,
              interlinearEnabled: false,
              onToggleInterlinear: () {},
              onMode: () {},
              onHistory: () {},
              onLibrary: () {},
              onDecreaseFont: () {},
              onIncreaseFont: () {},
              tiltAutoScrollController: controller,
              onToggleTiltAutoScroll: () {
                if (controller.isActive) {
                  controller.stop();
                } else {
                  controller.activate();
                }
              },
              onOpenTiltAutoScrollSettings: () => settingsOpenCount += 1,
              onCommentary: () {},
              canDecreaseFont: true,
              canIncreaseFont: true,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Tilt Auto-scroll'), findsOneWidget);
      final increase = find.text('A+');
      final tilt = find.byIcon(Icons.swap_vert_rounded);
      final tiltTarget = find.byTooltip('Tilt Auto-scroll');
      final commentaryTarget = find.byTooltip('Commentary');
      expect(increase, findsOneWidget);
      expect(tilt, findsOneWidget);
      expect(commentaryTarget, findsOneWidget);
      final tiltRect = tester.getRect(tiltTarget);
      final commentaryRect = tester.getRect(commentaryTarget);
      final screenRect = Offset.zero & Size(width, 180);
      expect(tiltRect.width, greaterThanOrEqualTo(44));
      expect(tiltRect.height, greaterThanOrEqualTo(44));
      expect(screenRect.contains(tiltRect.topLeft), isTrue);
      expect(screenRect.contains(tiltRect.bottomRight), isTrue);
      expect(commentaryRect.width, greaterThanOrEqualTo(44));
      expect(commentaryRect.height, greaterThanOrEqualTo(44));
      expect(tiltRect.overlaps(commentaryRect), isFalse);
      expect(commentaryRect.left - tiltRect.right, greaterThanOrEqualTo(8));
      expect(
        tester.getCenter(tilt).dx,
        greaterThan(tester.getCenter(increase).dx),
      );
      expect(
        tiltRect.left,
        greaterThanOrEqualTo(tester.getRect(increase).right),
      );
      await tester.tap(tilt);
      expect(controller.state, ReaderTiltAutoScrollState.calibrating);
      await tester.tap(tilt);
      expect(controller.state, ReaderTiltAutoScrollState.paused);
      final hold = await tester.startGesture(tester.getCenter(tilt));
      await tester.pump(ReaderTiltAutoScrollIconButton.longPressDuration);
      await hold.up();
      expect(settingsOpenCount, 1);
    });
  }

  testWidgets('phone hit regions dispatch only their own actions', (
    tester,
  ) async {
    final motion = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: motion,
      scrollTarget: CallbackReaderAutoScrollTarget(),
    );
    var tiltCount = 0;
    var commentaryCount = 0;
    var settingsCount = 0;
    var historyCount = 0;
    var libraryCount = 0;
    var modeCount = 0;
    var themeCount = 0;
    var interlinearCount = 0;
    var decreaseCount = 0;
    var increaseCount = 0;
    await tester.binding.setSurfaceSize(const Size(390, 180));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      controller.dispose();
      await motion.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ViewerBottomBar(
            themeMode: AppThemeMode.sepia,
            onToggleThemeMode: () => themeCount += 1,
            bookNumber: 1,
            interlinearEnabled: false,
            onToggleInterlinear: () => interlinearCount += 1,
            onMode: () => modeCount += 1,
            onHistory: () => historyCount += 1,
            onLibrary: () => libraryCount += 1,
            onDecreaseFont: () => decreaseCount += 1,
            onIncreaseFont: () => increaseCount += 1,
            tiltAutoScrollController: controller,
            onToggleTiltAutoScroll: () => tiltCount += 1,
            onOpenTiltAutoScrollSettings: () => settingsCount += 1,
            onCommentary: () => commentaryCount += 1,
            canDecreaseFont: true,
            canIncreaseFont: true,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );

    final tiltRect = tester.getRect(find.byTooltip('Tilt Auto-scroll'));
    for (final point in [
      tiltRect.center,
      Offset(tiltRect.left + 1, tiltRect.center.dy),
      Offset(tiltRect.right - 1, tiltRect.center.dy),
    ]) {
      await tester.tapAt(point);
      await tester.pump();
    }
    expect(tiltCount, 3);
    expect(commentaryCount, 0);

    await tester.tap(find.byTooltip('Commentary'));
    await tester.pump();
    expect(commentaryCount, 1);
    expect(tiltCount, 3);

    final hold = await tester.startGesture(
      tester.getCenter(find.byTooltip('Tilt Auto-scroll')),
    );
    await tester.pump(ReaderTiltAutoScrollIconButton.longPressDuration);
    await hold.up();
    expect(settingsCount, 1);
    expect(tiltCount, 3);
    expect(commentaryCount, 1);
    expect([
      historyCount,
      libraryCount,
      modeCount,
      themeCount,
      interlinearCount,
      decreaseCount,
      increaseCount,
    ], everyElement(0));
  });

  testWidgets(
    'the complete ordered phone toolbar scrolls as one usable strip',
    (tester) async {
      final motion = FakeReaderTiltMotionSource();
      final controller = ReaderTiltAutoScrollController(
        motionSource: motion,
        scrollTarget: CallbackReaderAutoScrollTarget(),
      );
      await tester.binding.setSurfaceSize(const Size(390, 180));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        controller.dispose();
        await motion.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ViewerBottomBar(
              themeMode: AppThemeMode.sepia,
              onToggleThemeMode: () {},
              bookNumber: 1,
              interlinearEnabled: false,
              onToggleInterlinear: () {},
              onMode: () {},
              onHistory: () {},
              onLibrary: () {},
              onDecreaseFont: () {},
              onIncreaseFont: () {},
              tiltAutoScrollController: controller,
              onToggleTiltAutoScroll: () {},
              onOpenTiltAutoScrollSettings: () {},
              onCommentary: () {},
              canDecreaseFont: true,
              canIncreaseFont: true,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final tilt = find.byTooltip('Tilt Auto-scroll');
      final before = tester.getRect(tilt);
      final historyBefore = tester.getRect(find.byTooltip('History'));
      final commentaryBefore = tester.getRect(find.byTooltip('Commentary'));
      final libraryBefore = tester.getRect(find.byTooltip('eLibrary'));
      expect(historyBefore.left, lessThan(libraryBefore.left));
      expect(before.right, lessThanOrEqualTo(390));
      expect(commentaryBefore.right, lessThanOrEqualTo(390));
      expect(libraryBefore.right, lessThanOrEqualTo(390));
      expect(tester.getRect(find.byTooltip('Mode')).right, greaterThan(390));

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(tilt).left, lessThan(before.left));
      expect(
        tester.getRect(find.byTooltip('History')).left,
        lessThan(historyBefore.left),
      );
      expect(
        tester.getRect(find.byTooltip('Commentary')).left,
        lessThan(commentaryBefore.left),
      );
      expect(
        tester.getRect(find.byTooltip('eLibrary')).left,
        lessThan(libraryBefore.left),
      );
      expect(
        tester.getRect(find.byTooltip('Mode')).right,
        lessThanOrEqualTo(390),
      );
      expect(find.byTooltip('Mode'), findsOneWidget);
    },
  );
}
