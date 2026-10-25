import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/entry/presentation/entry_screen.dart';
import 'package:studybible2/features/partners/data/ministry_enrollment_service.dart';
import 'package:studybible2/features/partners/data/ministry_profile.dart';
import 'package:studybible2/features/partners/presentation/ministry_welcome_screen.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform entry keeps standard screens with ADL discount', (
      tester,
    ) async {
      final state = MinistryEnrollmentService.instance.state;
      final previous = state.value;
      addTearDown(() => state.value = previous);
      state.value = MinistryEnrollment(
        ministryId: 'adl',
        setupCompleted: true,
        grandfathered: false,
        firstSeenUtc: DateTime.utc(2026, 10, 25),
      );
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: EntryScreen(
            themeMode: AppThemeMode.sepia,
            onThemeChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Biblical Heritage #StudyBible'), findsOneWidget);
      expect(find.byType(MinistryWelcomeScreen), findsNothing);
      expect(find.bySemanticsLabel('The Advent Defense League'), findsNothing);
      expect(
        find
            .byType(Image)
            .evaluate()
            .map((e) => (e.widget as Image).image)
            .whereType<AssetImage>()
            .map((image) => image.assetName),
        isNot(contains('assets/partners/adl_welcome.png')),
      );
      expect(state.value!.ministryId, 'adl');
      expect(state.value!.profile!.unlockPriceUsdCents, 999);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
