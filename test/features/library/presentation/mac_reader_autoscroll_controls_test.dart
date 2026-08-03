import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controls.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_preferences.dart';

class _Target implements ReaderAutoScrollTarget {
  @override
  bool get isAttached => true;

  @override
  bool scrollBy(double delta) => true;
}

void main() {
  testWidgets(
    'first tap stops active autoscroll and the next tap reaches content',
    (tester) async {
      final controller = MacReaderAutoScrollController(
        scrollTarget: _Target(),
        driveFrames: false,
      );
      addTearDown(controller.dispose);
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              TextButton(
                key: const ValueKey('underlying-reader-action'),
                onPressed: () => activations++,
                child: const Text('Verse action'),
              ),
              ReaderAutoscrollTapShield(
                listenables: <Listenable>[controller],
                isScrolling: () => controller.isScrolling,
                onStop: controller.stopForManualInteraction,
              ),
            ],
          ),
        ),
      );
      controller.setSignedStep(5);
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('underlying-reader-action')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(controller.isScrolling, isFalse);
      expect(activations, 0);

      await tester.tap(find.byKey(const ValueKey('underlying-reader-action')));
      await tester.pump();
      expect(activations, 1);
    },
  );

  testWidgets('arrows change speed only while reader has primary focus', (
    tester,
  ) async {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      driveFrames: false,
    );
    final readerFocus = FocusNode();
    final textFocus = FocusNode();
    final buttonFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(readerFocus.dispose);
    addTearDown(textFocus.dispose);
    addTearDown(buttonFocus.dispose);
    var suspended = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: readerFocus,
          autofocus: true,
          onKeyEvent: (node, event) => handleMacReaderAutoscrollKeyEvent(
            event: event,
            readerFocusNode: node,
            controller: controller,
            suspended: suspended,
          ),
          child: Scaffold(
            body: Column(
              children: <Widget>[
                TextField(focusNode: textFocus),
                IconButton(
                  focusNode: buttonFocus,
                  onPressed: () {},
                  icon: const Icon(Icons.menu),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    controller.toggle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.signedStep, 1);

    textFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.signedStep, 1);

    buttonFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.signedStep, 1);

    readerFocus.requestFocus();
    suspended = true;
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    expect(controller.signedStep, 1);
  });

  testWidgets('key repeat is ignored', (tester) async {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      driveFrames: false,
    );
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(focusNode: focus, child: const SizedBox()),
      ),
    );
    focus.requestFocus();
    await tester.pump();

    final result = handleMacReaderAutoscrollKeyEvent(
      event: const KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration.zero,
      ),
      readerFocusNode: focus,
      controller: controller,
    );
    expect(result, KeyEventResult.ignored);
    expect(controller.signedStep, 0);
  });

  testWidgets('one combined button toggles while keyboard controls speed', (
    tester,
  ) async {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      driveFrames: false,
    );
    final readerFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(readerFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: readerFocus,
          autofocus: true,
          onKeyEvent: (node, event) => handleMacReaderAutoscrollKeyEvent(
            event: event,
            readerFocusNode: node,
            controller: controller,
          ),
          child: Scaffold(
            body: MacReaderAutoScrollButton(
              controller: controller,
              onPressed: controller.toggle,
              onLongPress: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('mac-autoscroll-button')), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsOneWidget);
    expect(find.byKey(const ValueKey('mac-autoscroll-up')), findsNothing);
    expect(find.byKey(const ValueKey('mac-autoscroll-down')), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-button')));
    await tester.pump();
    expect(controller.signedStep, 0);
    expect(controller.statusLabel, 'Autoscroll paused');
    var button = tester.widget<IconButton>(
      find.byKey(const ValueKey('mac-autoscroll-button')),
    );
    expect(
      button.style?.backgroundColor?.resolve(const <WidgetState>{}),
      Theme.of(tester.element(find.byType(Scaffold))).colorScheme.primary,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.signedStep, 1);

    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-button')));
    await tester.pump();
    expect(controller.signedStep, 0);
    expect(controller.statusLabel, 'Autoscroll stopped');
    button = tester.widget<IconButton>(
      find.byKey(const ValueKey('mac-autoscroll-button')),
    );
    expect(
      button.style?.backgroundColor?.resolve(const <WidgetState>{}),
      isNull,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.signedStep, 0);
  });

  testWidgets('combined button long press opens Mac settings', (tester) async {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MacReaderAutoScrollButton(
              controller: controller,
              onPressed: controller.toggle,
              onLongPress: () => showMacAutoscrollSettingsDialog(
                context: context,
                initial: const MacAutoscrollPreferences(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byKey(const ValueKey('mac-autoscroll-button')));
    await tester.pumpAndSettle();
    expect(find.text('Mac Autoscroll'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mac-autoscroll-base-speed')),
      findsOneWidget,
    );
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-maximum-step')));
    await tester.pumpAndSettle();
    expect(find.text('50×'), findsWidgets);
  });

  testWidgets('keyboard arrows follow all speed bands and reverse at 1x', (
    tester,
  ) async {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      driveFrames: false,
    );
    final readerFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(readerFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: readerFocus,
          autofocus: true,
          onKeyEvent: (node, event) => handleMacReaderAutoscrollKeyEvent(
            event: event,
            readerFocusNode: node,
            controller: controller,
          ),
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();
    controller.toggle();

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
    }

    final keyboardRevision = controller.keyboardStatusRevision;
    for (final expected in <int>[1, 2, 3, 5, 10, 25, 50, 50]) {
      await press(LogicalKeyboardKey.arrowDown);
      expect(controller.signedStep, expected);
    }
    expect(controller.keyboardStatusRevision, greaterThan(keyboardRevision));
    for (final expected in <int>[25, 10, 5, 3, 2, 1, 0, -1]) {
      await press(LogicalKeyboardKey.arrowUp);
      expect(controller.signedStep, expected);
    }
    for (final expected in <int>[-2, -3, -5, -10, -25, -50, -50]) {
      await press(LogicalKeyboardKey.arrowUp);
      expect(controller.signedStep, expected);
    }
    await press(LogicalKeyboardKey.arrowDown);
    expect(controller.signedStep, -25);
  });

  testWidgets('settings save 25x and cancel preserves the prior maximum', (
    tester,
  ) async {
    MacAutoscrollPreferences? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: <Widget>[
                TextButton(
                  onPressed: () async {
                    final result = await showMacAutoscrollSettingsDialog(
                      context: context,
                      initial: const MacAutoscrollPreferences(maximumStep: 10),
                    );
                    if (result != null) saved = result;
                  },
                  child: const Text('Open settings'),
                ),
                Text('Saved: ${saved?.maximumStep ?? 10}×'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-maximum-step')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25×').last);
    await tester.pumpAndSettle();
    expect(find.text('25×'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-save')));
    await tester.pumpAndSettle();
    expect(saved?.maximumStep, 25);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-maximum-step')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25×').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-cancel')));
    await tester.pumpAndSettle();
    expect(saved?.maximumStep, 25);
  });

  testWidgets('Mac dialog exposes only the shared status banner choices', (
    tester,
  ) async {
    MacAutoscrollPreferences? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showMacAutoscrollSettingsDialog(
                  context: context,
                  initial: const MacAutoscrollPreferences(
                    statusBannerMode: ReaderTiltStatusBannerMode.alwaysHidden,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Status Banner'), findsOneWidget);
    expect(find.text('Always Visible'), findsOneWidget);
    expect(find.text('Auto-hide after 7 seconds'), findsOneWidget);
    expect(find.text('Always Hidden'), findsOneWidget);
    expect(find.textContaining('Neutral'), findsNothing);
    expect(find.textContaining('Sideways'), findsNothing);
    expect(find.textContaining('calibration'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-save')));
    await tester.pumpAndSettle();
    expect(saved?.statusBannerMode, ReaderTiltStatusBannerMode.alwaysHidden);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Always Visible'));
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-save')));
    await tester.pumpAndSettle();
    expect(saved?.statusBannerMode, ReaderTiltStatusBannerMode.alwaysVisible);
  });

  testWidgets('Mac dialog cancel discards a pending banner choice', (
    tester,
  ) async {
    MacAutoscrollPreferences? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showMacAutoscrollSettingsDialog(
                  context: context,
                  initial: const MacAutoscrollPreferences(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Always Hidden'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Always Hidden'));
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-cancel')));
    await tester.pumpAndSettle();
    expect(saved, isNull);
  });

  testWidgets(
    'Mac status overlay honors visible, auto-hide, and hidden modes',
    (tester) async {
      final controller = MacReaderAutoScrollController(
        scrollTarget: _Target(),
        preferences: const MacAutoscrollPreferences(
          statusBannerMode: ReaderTiltStatusBannerMode.alwaysVisible,
        ),
        driveFrames: false,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                MacReaderAutoscrollStatusOverlay(
                  controller: controller,
                  foregroundColor: Colors.black,
                  backgroundColor: Colors.white,
                ),
              ],
            ),
          ),
        ),
      );

      controller.toggle();
      await tester.pump();
      expect(find.text('Autoscroll paused'), findsOneWidget);
      controller.increaseStep();
      await tester.pump();
      expect(find.text('Autoscroll ↓ 1×'), findsOneWidget);

      controller.updatePreferences(
        const MacAutoscrollPreferences(
          statusBannerMode: ReaderTiltStatusBannerMode.autoHide,
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mac-autoscroll-status')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 7));
      expect(find.byKey(const ValueKey('mac-autoscroll-status')), findsNothing);
      controller.increaseStep();
      await tester.pump();
      expect(find.text('Autoscroll ↓ 2×'), findsOneWidget);

      controller.updatePreferences(
        const MacAutoscrollPreferences(
          statusBannerMode: ReaderTiltStatusBannerMode.alwaysHidden,
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('mac-autoscroll-status')), findsNothing);
      controller.increaseStep();
      expect(controller.signedStep, 3);
      controller.showKeyboardStatus();
      await tester.pump();
      expect(find.text('Autoscroll ↓ 3×'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 249));
      expect(
        find.byKey(const ValueKey('mac-autoscroll-status')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const ValueKey('mac-autoscroll-status')), findsNothing);
    },
  );
}
