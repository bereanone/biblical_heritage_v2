import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/app/study_bible_app.dart';

void main() {
  testWidgets('shows the entry screen first', (tester) async {
    await tester.pumpWidget(const StudyBibleApp());

    expect(find.text('Biblical Heritage'), findsOneWidget);
    expect(find.text('#StudyBible'), findsOneWidget);
    expect(find.text('Bible Explorer'), findsOneWidget);
  });

  testWidgets('can switch to night theme from the theme button', (tester) async {
    await tester.pumpWidget(const StudyBibleApp());

    await tester.tap(find.text('aA'));
    await tester.pumpAndSettle();

    expect(find.text('Night'), findsWidgets);

    await tester.tap(find.text('Night').last);
    await tester.pumpAndSettle();

    expect(find.text('Night'), findsNothing);
  });

  testWidgets('bible explorer button opens the new small explorer screen', (
    tester,
  ) async {
    await tester.pumpWidget(const StudyBibleApp());

    await tester.scrollUntilVisible(
      find.text('Bible Explorer'),
      200,
    );
    await tester.tap(find.text('Bible Explorer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Small by design'), findsOneWidget);
    expect(find.text('Genesis 1:1'), findsOneWidget);
    expect(find.text('Reader Tools'), findsOneWidget);
  });
}
