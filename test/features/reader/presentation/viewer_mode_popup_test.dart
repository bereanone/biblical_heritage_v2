import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/reader/presentation/viewer_mode_popup.dart';
import 'package:studybible2/features/reader/presentation/viewer_presentation_settings.dart';

void main() {
  for (final size in [
    const Size(360, 640),
    const Size(640, 320),
    const Size(320, 480),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('gear options reachable at $size with text scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var audioOpened = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 24, bottom: 24),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    showViewerModePopup(
                      context,
                      themeMode: AppThemeMode.sepia,
                      onThemeChanged: (_) {},
                      onOpenBibleMemory: () {},
                      onOpenAudioSettings: () {
                        audioOpened++;
                      },
                      onOpenInterlinearSettings: () {},
                      onOpenColorSetup: () {},
                      onApplyDefaultMarkup: () {},
                      presentationAspectRatio:
                          PresentationAspectRatioPreset.auto,
                      onPresentationAspectRatioChanged: (_) {},
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
        expect(tester.takeException(), isNull);
        final dialog = tester.getRect(find.byType(Dialog));
        expect(dialog.top, greaterThanOrEqualTo(24));
        expect(dialog.bottom, lessThanOrEqualTo(size.height - 24));
        final scroll = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first;
        final scrollState = tester.state<ScrollableState>(scroll);
        if (scrollState.position.maxScrollExtent > 0) {
          final beforeSwipe = scrollState.position.pixels;
          await tester.drag(scroll, const Offset(0, -120));
          await tester.pumpAndSettle();
          expect(scrollState.position.pixels, greaterThan(beforeSwipe));
          await tester.drag(scroll, const Offset(0, 120));
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(
          find.text('Color Setup'),
          100,
          scrollable: scroll,
        );
        expect(find.text('Color Setup').hitTestable(), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Bible Audio Settings'),
          -100,
          scrollable: scroll,
        );
        await tester.tap(find.text('Bible Audio Settings'));
        await tester.pumpAndSettle();
        expect(audioOpened, 1);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Bible Audio Settings').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
