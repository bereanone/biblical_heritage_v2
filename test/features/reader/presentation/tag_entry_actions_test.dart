import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/tag_entry_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await fonts.load();
  });
  for (final scenario in [
    for (final width in [290.0, 180.0, 479.0, 480.0, 700.0])
      (width: width, screen: const Size(800, 1100)),
    (width: 760.0, screen: const Size(844, 390)),
    (width: 326.0, screen: const Size(390, 844)),
  ]) {
    final width = scenario.width;
    final wide = scenario.screen.shortestSide >= 600 && width >= 480;
    testWidgets(
      'all actions remain visible at width $width on ${scenario.screen}',
      (tester) async {
        final calls = <String>[];
        final moveUp = wide ? 'Move up' : 'Move\nup';
        final moveDown = wide ? 'Move down' : 'Move\ndown';
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            home: MediaQuery(
              data: MediaQueryData(
                size: scenario.screen,
                textScaler: const TextScaler.linear(3),
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Reading text'),
                        TagEntryActions(
                          onEdit: () => calls.add('edit'),
                          onMoveUp: null,
                          onMoveDown: () => calls.add('down'),
                          onTrash: () => calls.add('trash'),
                          foregroundColor: Colors.brown,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
        expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
        expect(find.byType(Scrollbar), findsNothing);
        expect(find.byType(SingleChildScrollView), findsNothing);
        for (final label in ['Edit', moveUp, moveDown, 'Trash']) {
          final target = find.widgetWithText(TextButton, label);
          final rect = tester.getRect(target);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(target.hitTestable(), findsOneWidget);
          expect(
            MediaQuery.textScalerOf(tester.element(find.text(label))).scale(14),
            closeTo(16.8, .01),
          );
        }
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.text('Reading text')),
          ).scale(14),
          42,
        );
        final edit = tester.getRect(find.widgetWithText(TextButton, 'Edit'));
        final trash = tester.getRect(find.widgetWithText(TextButton, 'Trash'));
        if (width >= 290) {
          expect(trash.center.dy, closeTo(edit.center.dy, 1));
        } else {
          expect(trash.top, greaterThan(edit.top));
        }
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, moveUp))
              .onPressed,
          isNull,
        );
        await tester.tap(find.text(moveDown));
        await tester.tap(find.text('Edit'));
        await tester.tap(find.text('Trash'));
        expect(calls, ['down', 'edit', 'trash']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
