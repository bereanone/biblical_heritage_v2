import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/partners/data/ministry_enrollment_service.dart';
import 'package:studybible2/features/partners/data/ministry_profile.dart';
import 'package:studybible2/features/partners/presentation/ministry_enrollment_gate.dart';
import 'package:studybible2/features/partners/presentation/ministry_setup_screen.dart';
import 'package:studybible2/features/partners/presentation/ministry_welcome_screen.dart';

void main() {
  String? saved;
  late MinistryEnrollmentService service;
  setUp(() {
    saved = null;
    service = MinistryEnrollmentService(
      read: () async => saved,
      write: (value) async => saved = value,
      seed: (_) async {},
    );
  });
  Widget app() => MaterialApp(
    home: MinistryEnrollmentGate(
      service: service,
      child: ValueListenableBuilder(
        valueListenable: service.state,
        builder: (context, value, child) =>
            value?.displayProfile != null &&
                value?.displayProfile != MinistryProfile.biblicalHeritage
            ? MinistryWelcomeScreen(
                profile: value!.displayProfile,
                onExplore: () {},
                onUtilities: () {},
                onAbout: () {},
              )
            : const Scaffold(body: Text('Biblical Heritage welcome')),
      ),
    ),
  );

  testWidgets(
    'ADL discount enrollment keeps the standard welcome after restart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Promotional code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'adl');
      await tester.tap(find.text('Apply promotional code'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('The Advent Defense League'), findsNothing);
      expect(find.byType(MinistrySetupScreen), findsNothing);
      expect(find.text('Biblical Heritage welcome'), findsOneWidget);
      expect(service.state.value?.ministryId, 'adl');
      expect(service.state.value?.profile?.unlockPriceUsdCents, 999);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('The Advent Defense League'), findsNothing);
      expect(find.byType(MinistrySetupScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final profile in [
    MinistryProfile.adventDefenseLeague,
    MinistryProfile.heritageAndHope,
  ]) {
    testWidgets(
      '${profile.name} full-screen overlays stay usable with large text and dark app theme',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var explored = 0;
        var about = 0;
        var utilities = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: MinistryWelcomeScreen(
                profile: profile,
                onExplore: () => explored++,
                onAbout: () => about++,
                onUtilities: () => utilities++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final artwork = tester.widget<Image>(
          find.byKey(const Key('ministry-artwork-attribution')),
        );
        expect((artwork.image as AssetImage).assetName, profile.artworkAsset);
        final imageSize = tester.getSize(
          find.byKey(const Key('ministry-artwork-attribution')),
        );
        // Attribution is always rendered at the original 1024:1536 ratio.
        expect(imageSize.height / imageSize.width, closeTo(1.5, .001));
        expect(
          tester.getSize(find.bySemanticsLabel(profile.name)),
          const Size(390, 844),
        );
        expect(find.byType(SingleChildScrollView), findsNothing);
        await tester.tapAt(const Offset(100, 610));
        expect(explored, 0);
        expect(about, 0);
        expect(utilities, 0);
        await tester.ensureVisible(find.bySemanticsLabel('Explore the Bible'));
        await tester.tap(find.bySemanticsLabel('Explore the Bible'));
        expect(explored, 1);
        await tester.ensureVisible(find.text('Utilities'));
        await tester.tap(find.text('Utilities'));
        await tester.tap(find.text('About'));
        expect(utilities, 1);
        expect(about, 1);
        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('install without code retains the current welcome', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Install without promotional code'));
    await tester.pumpAndSettle();
    expect(find.text('Biblical Heritage welcome'), findsOneWidget);
    expect(find.byType(MinistrySetupScreen), findsNothing);
  });
  testWidgets('invalid code leaves setup open without changing ministry', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not-a-code');
    await tester.tap(find.text('Apply promotional code'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('That promotional code is not available'),
      findsOneWidget,
    );
    expect(service.state.value!.setupCompleted, isFalse);
    expect(service.state.value!.profile, MinistryProfile.biblicalHeritage);
  });
  testWidgets(
    'large text on landscape phone keeps both setup choices reachable',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await service.initialize(existingInstall: false);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: MinistrySetupScreen(service: service, onCompleted: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Install without promotional code'));
      expect(
        find.text('Install without promotional code').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
