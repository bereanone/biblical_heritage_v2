import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controls.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/reader/presentation/viewer_markup_span_builder.dart';
import 'package:studybible2/features/reader/presentation/viewer_range_actions_sheet.dart';

class _Target implements ReaderAutoScrollTarget {
  @override
  bool get isAttached => true;
  @override
  bool scrollBy(double delta) => true;
}

void main() {
  for (final playing in [true, false]) {
    testWidgets(
      'single word long press opens tools with speech playing=$playing',
      (tester) async {
        final controller = MacReaderAutoScrollController(
          scrollTarget: _Target(),
          driveFrames: false,
          narrationControlsPacing: true,
          preferences: const MacAutoscrollPreferences(audioEnabled: true),
        );
        addTearDown(controller.dispose);
        if (playing) controller.setSignedStep(1);
        int? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Stack(
                  children: [
                    Listener(
                      onPointerDown: (_) =>
                          controller.pauseNarrationForInteraction(),
                      child: Center(
                        child: RichText(
                          key: const ValueKey('word'),
                          text: buildViewerMarkupSpan(
                            html: '<w lemma="strong:H430">God</w>',
                            fallbackText: 'God',
                            blockId: 1,
                            baseStyle: const TextStyle(
                              fontSize: 28,
                              color: Colors.black,
                            ),
                            redLetterColor: Colors.red,
                            onTokenLongPress: (index) => selected = index,
                            onTokenLongPressEnd: () =>
                                showViewerRangeActionsSheet(
                                  context,
                                  payload: const ViewerRangeActionsPayload(
                                    label: 'Genesis 1:1',
                                    previewText: 'God',
                                    startLabel: 'Genesis 1:1',
                                    endLabel: 'Genesis 1:1',
                                  ),
                                  fontScale: 1,
                                  enableStrongs: selected == 1,
                                ),
                          ),
                        ),
                      ),
                    ),
                    ReaderAutoscrollTapShield(
                      listenables: [controller],
                      isScrolling: () => controller.isPixelScrolling,
                      onStop: controller.stopForManualInteraction,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('word'))),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(controller.isScrolling, isFalse);
        expect(selected, 1);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(find.text('Copy No Citation'), findsOneWidget);
        expect(find.text('Highlight'), findsOneWidget);
        expect(find.text("Strong's"), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
