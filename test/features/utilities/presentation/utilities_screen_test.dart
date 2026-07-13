import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/utilities/presentation/utilities_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfi;

  testWidgets('utilities screen uses the iPad two-column dashboard', (
    tester,
  ) async {
    await _pumpUtilitiesScreen(tester, const Size(1366, 1024));

    expect(find.text('Utilities'), findsOneWidget);
    expect(find.text('App Tools'), findsOneWidget);
    expect(
      find.text('Manage common app settings and protect your personal data.'),
      findsOneWidget,
    );
    expect(find.text('eLibrary'), findsOneWidget);
    expect(
      find.text('Manage book storage, downloads, imports, and indexing.'),
      findsOneWidget,
    );
    expect(find.text('Commentary & Sharing'), findsOneWidget);
    expect(
      find.text('Learn how commentary blocks work and share them with others.'),
      findsOneWidget,
    );
    expect(find.text('Support & More'), findsOneWidget);
    expect(
      find.text('Support the project and open additional study tools.'),
      findsOneWidget,
    );

    expect(find.text('Church AutoMute'), findsOneWidget);
    expect(find.text('Backup User Data'), findsOneWidget);
    expect(find.text('Restore Backup'), findsOneWidget);
    expect(find.text('eLibrary Setup'), findsOneWidget);
    expect(find.text('Download Books'), findsOneWidget);
    expect(find.text('Import Pioneer Books'), findsOneWidget);
    expect(find.text('Library Storage'), findsOneWidget);
    expect(find.text('Storage & Index Report'), findsOneWidget);
    expect(find.text('Commentary Instructions'), findsOneWidget);
    expect(find.text('Commentary Block Sharing'), findsOneWidget);
    expect(find.text('Community Links'), findsOneWidget);
    expect(find.text('Support Biblical Heritage'), findsOneWidget);
    expect(find.text('Open Bible Explorer'), findsOneWidget);

    expect(find.text('Library Root Setup'), findsNothing);
    expect(find.text('eLibrary Downloads'), findsNothing);
    expect(find.text('Pioneer Library Import'), findsNothing);
    expect(find.text('Storage and Index Report'), findsNothing);

    final appToolsCard = tester.getTopLeft(
      find.byKey(const Key('utilities-section-app-tools')),
    );
    final eLibraryCard = tester.getTopLeft(
      find.byKey(const Key('utilities-section-elibrary')),
    );
    final commentaryCard = tester.getTopLeft(
      find.byKey(const Key('utilities-section-commentary-sharing')),
    );
    final supportCard = tester.getTopLeft(
      find.byKey(const Key('utilities-section-support')),
    );

    expect((eLibraryCard.dx - appToolsCard.dx).abs(), lessThan(1));
    expect(commentaryCard.dx, greaterThan(appToolsCard.dx));
    expect((supportCard.dx - commentaryCard.dx).abs(), lessThan(1));

    final eLibrarySetupButton = tester.getTopLeft(
      find.widgetWithText(FilledButton, 'eLibrary Setup'),
    );
    final downloadBooksButton = tester.getTopLeft(
      find.widgetWithText(OutlinedButton, 'Download Books'),
    );
    expect(
      (downloadBooksButton.dy - eLibrarySetupButton.dy).abs(),
      lessThan(8),
    );
    expect(downloadBooksButton.dx, greaterThan(eLibrarySetupButton.dx));
  });

  testWidgets('utilities screen collapses to one column on narrow widths', (
    tester,
  ) async {
    await _pumpUtilitiesScreen(tester, const Size(430, 932));

    final appToolsCard = tester.getTopLeft(
      find.byKey(const Key('utilities-section-app-tools')),
    );
    final eLibraryCard = tester.getTopLeft(
      find.byKey(const Key('utilities-section-elibrary')),
    );
    final commentaryCard = tester.getTopLeft(
      find.byKey(const Key('utilities-section-commentary-sharing')),
    );

    expect((eLibraryCard.dx - appToolsCard.dx).abs(), lessThan(1));
    expect((commentaryCard.dx - appToolsCard.dx).abs(), lessThan(1));
  });

  testWidgets('utilities screen keeps the button callbacks and routes wired', (
    tester,
  ) async {
    final observer = _TestNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: UtilitiesScreen(
          themeMode: AppThemeMode.sepia,
          onThemeChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Church AutoMute'));
    await tester.pumpAndSettle();
    expect(find.text('Church AutoMute'), findsWidgets);
    expect(
      find.textContaining('planned for a future version.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final bibleExplorerButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Open Bible Explorer'),
    );
    expect(bibleExplorerButton.onPressed, isNotNull);
    final pushedCount = observer.pushedRoutes.length;
    bibleExplorerButton.onPressed!();
    await tester.pump();
    expect(observer.pushedRoutes.length, pushedCount + 1);
    expect(observer.pushedRoutes.last, isA<MaterialPageRoute<void>>());
  });
}

Future<void> _pumpUtilitiesScreen(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: UtilitiesScreen(
        themeMode: AppThemeMode.sepia,
        onThemeChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _TestNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}
