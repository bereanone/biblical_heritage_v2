import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controls.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_preferences.dart';

void main() {
  testWidgets('long press opens shared settings and tap still toggles', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
    );
    var preferences = ReaderTiltPreferences.defaults;
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ReaderTiltAutoScrollIconButton(
              controller: controller,
              onPressed: controller.activate,
              onLongPress: () => showReaderTiltSettingsSheet(
                context,
                preferences: preferences,
                includeChapterTilt: true,
                onChanged: (value) => preferences = value,
                onRecalibrate: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    expect(controller.state, ReaderTiltAutoScrollState.calibrating);
    await controller.stop();
    await tester.longPress(find.byIcon(Icons.swap_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Tilt Auto-scroll Settings'), findsOneWidget);
    expect(find.text('Tilt Sideways to Change Chapter'), findsOneWidget);
    expect(find.text('Set Current Angle as Neutral'), findsOneWidget);
    expect(find.text('Restore Defaults'), findsOneWidget);
  });

  testWidgets('Bible settings omit chapter tilt and restore defaults', (
    tester,
  ) async {
    var preferences = const ReaderTiltPreferences(
      reverseVerticalDirection: true,
      neutralZoneFraction: 0.10,
      speedMultiplier: 2,
      horizontalChapterTiltEnabled: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showReaderTiltSettingsSheet(
                context,
                preferences: preferences,
                includeChapterTilt: false,
                onChanged: (value) => preferences = value,
                onRecalibrate: () {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Tilt Sideways to Change Chapter'), findsNothing);
    await tester.tap(find.text('Restore Defaults'));
    expect(preferences.reverseVerticalDirection, isFalse);
    expect(preferences.neutralZoneFraction, 0.05);
    expect(preferences.speedMultiplier, 1.0);
    expect(preferences.horizontalChapterTiltEnabled, isTrue);
  });
}
