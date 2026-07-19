import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controls.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';

class _Target implements ReaderAutoScrollTarget {
  @override
  bool get isAttached => true;

  @override
  bool scrollBy(double delta) => true;
}

void main() {
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

  testWidgets('arrow keys still work after clicking the autoscroll button', (
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

    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-button')));
    await tester.pump();
    expect(controller.signedStep, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.signedStep, 2);
  });

  testWidgets('button clicks toggle and long press opens Mac settings', (
    tester,
  ) async {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      driveFrames: false,
    );
    addTearDown(controller.dispose);
    var presses = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MacReaderAutoScrollButton(
              controller: controller,
              onPressed: () {
                presses++;
                controller.toggle();
              },
              onLongPress: () => showMacAutoscrollSettingsDialog(
                context: context,
                initial: const MacAutoscrollPreferences(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-button')));
    await tester.pump();
    expect(presses, 1);
    expect(controller.signedStep, 1);
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-button')));
    expect(controller.signedStep, 0);

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
    expect(find.text('60×'), findsWidgets);
  });

  testWidgets('settings save 20x and cancel preserves the prior maximum', (
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
    await tester.tap(find.text('20×').last);
    await tester.pumpAndSettle();
    expect(find.text('20×'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-save')));
    await tester.pumpAndSettle();
    expect(saved?.maximumStep, 20);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-maximum-step')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20×').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-cancel')));
    await tester.pumpAndSettle();
    expect(saved?.maximumStep, 20);
  });
}
