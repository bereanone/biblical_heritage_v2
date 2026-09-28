import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bible_loop_announcement_settings.dart';
import 'package:studybible2/features/reader/presentation/bible_loop_picker.dart';

void main() {
  test('small status names the captured loop target and off state', () {
    expect(
      bibleLoopTargetLabel(
        BibleLoopUnit.verse,
        bookName: 'Romans',
        chapter: 6,
        verse: 17,
      ),
      'Looping Romans 6:17',
    );
    expect(
      bibleLoopTargetLabel(
        BibleLoopUnit.chapter,
        bookName: 'Romans',
        chapter: 6,
        verse: 17,
      ),
      'Looping Romans 6',
    );
    expect(
      bibleLoopTargetLabel(
        BibleLoopUnit.book,
        bookName: 'Romans',
        chapter: 6,
        verse: 17,
      ),
      'Looping Romans',
    );
    expect(
      bibleLoopTargetLabel(null, bookName: '', chapter: 0, verse: 0),
      'Loop off',
    );
  });

  testWidgets('tap starts or stops a loop; hold opens its choices', (
    tester,
  ) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BibleLoopControl(
            active: false,
            onTap: () => taps++,
            onLongPress: () => holds++,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('bible-audio-loop')));
    await tester.pump();
    expect(taps, 1);
    expect(holds, 0);

    await tester.longPress(find.byKey(const ValueKey('bible-audio-loop')));
    await tester.pump();
    expect(taps, 1);
    expect(holds, 1);
  });

  testWidgets('loop selection and announcements are separate controls', (
    tester,
  ) async {
    BibleLoopUnit? chosen;
    final changed = <BibleLoopUnit, bool>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showModalBottomSheet<BibleLoopUnit>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => BibleLoopPicker(
                    bookName: 'Romans',
                    chapter: 6,
                    verse: 17,
                    selectedLoop: BibleLoopUnit.book,
                    selectedTargetLabel: 'Looping Romans',
                    announcements: const BibleLoopAnnouncementSettings(),
                    onAnnouncementChanged: (unit, enabled) {
                      changed[unit] = enabled;
                    },
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
    expect(find.text('Loop'), findsOneWidget);
    expect(find.text('Announce'), findsOneWidget);
    expect(find.text('Looping Romans'), findsOneWidget);
    final bookRow = tester.widget<ListTile>(
      find.byKey(const ValueKey('bible_loop_select_book')),
    );
    expect(bookRow.selected, isTrue);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('bible_loop_announce_verse')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bible_loop_announce_verse')));
    await tester.pumpAndSettle();
    expect(changed, {BibleLoopUnit.verse: true});
    expect(chosen, isNull);
    expect(find.text('Looping Romans'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const ValueKey('bible_loop_select_book')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('Announce'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('bible_loop_select_chapter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bible_loop_select_chapter')));
    await tester.pumpAndSettle();
    expect(chosen, BibleLoopUnit.chapter);
    expect(changed, {BibleLoopUnit.verse: true});
    expect(find.text('Announce'), findsNothing);
  });
}
