import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';
import 'package:studybible2/features/reader/presentation/viewer_bottom_bar.dart';

void main() {
  for (final width in [300.0, 800.0]) {
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
      expect(increase, findsOneWidget);
      expect(tilt, findsOneWidget);
      expect(
        tester.getCenter(tilt).dx,
        greaterThan(tester.getCenter(increase).dx),
      );
      await tester.tap(tilt);
      expect(controller.state, ReaderTiltAutoScrollState.calibrating);
      await tester.tap(tilt);
      expect(controller.state, ReaderTiltAutoScrollState.paused);
      await tester.longPress(tilt);
      expect(settingsOpenCount, 1);
    });
  }
}
