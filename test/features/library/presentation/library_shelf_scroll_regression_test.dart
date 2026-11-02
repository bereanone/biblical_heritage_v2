import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/navigation/app_route_observer.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:studybible2/features/library/presentation/library_screen.dart';
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_folder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory fixture;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    fixture = await Directory.systemTemp.createTemp('shelf-scroll-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => fixture.path,
        );
    LibraryRootService.instance.invalidateCachedSelection();
    await LibraryRootService.instance.setLibraryRoot(path: fixture.path);
    final db = await ELibraryDatabase.instance.database;
    for (var i = 0; i < 20; i++) {
      await db.insert('library_items', {
        'id': 'book-$i',
        'title': 'Shelf Book $i',
        'author': 'Author',
        'file_name': 'book-$i.epub',
        'relative_path': 'book-$i.epub',
        'file_format': 'epub',
        'cover_path': 'assets/library_covers/LOF_ATJ.png',
        'created_at': '2026-10-27',
        'updated_at': '2026-10-27',
        'device_id': 'fixture',
      });
    }
    await AppSettingsService.instance.saveRawSetting(
      'elibrary_top_shelf_v1',
      jsonEncode(List.generate(7, (i) => 'book-$i')),
    );
  });

  tearDown(() async {
    await ELibraryDatabase.instance.close();
    await UserDatabase.instance.close();
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await fixture.delete(recursive: true);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'short Top Shelf keeps its viewport and lower row reachable after scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: LibraryScreen(
              capturedImportAvailabilityLoader: () async =>
                  PioneerCapturedHtmlAvailableImportReport(
                    rootPath: fixture.path,
                    imports: const [],
                    completedAt: DateTime.utc(2026),
                    message: 'No imports',
                  ),
            ),
          ),
        );
        // Real SQLite I/O must run outside the widget test's fake clock.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      final shelf = find.byKey(const PageStorageKey('library-shelf'));
      expect(shelf, findsOneWidget);
      final sizeBefore = tester.getSize(shelf);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: shelf, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      final gesture = await tester.startGesture(tester.getCenter(shelf));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -100));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getSize(shelf),
          sizeBefore,
          reason:
              'Scrolling must not resize the viewport and clamp its offset back up (frame $frame).',
        );
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.drag(shelf, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      expect(find.text('Shelf Book 6').hitTestable(), findsOneWidget);
      await tester.drag(shelf, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, closeTo(0, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('iPhone cover swipes reach the last Top Shelf row without jumping',
      (tester) async {
    // Theme selects iOS touch physics; keep unrelated mobile downloads disabled.
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await AppSettingsService.instance.saveRawSetting(
        'elibrary_top_shelf_v1',
        jsonEncode(List.generate(20, (i) => 'book-$i')),
      );
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: LibraryScreen(
          capturedImportAvailabilityLoader: () async =>
              PioneerCapturedHtmlAvailableImportReport(
                rootPath: fixture.path,
                imports: const [],
                completedAt: DateTime.utc(2026),
                message: 'No imports',
              ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final shelf = find.byKey(const PageStorageKey('library-shelf'));
    final viewport = tester.getSize(shelf);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: shelf, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(viewport.height));
    // Start on a book cover, where the phone's tap/long-press gestures compete.
    final firstCover = find.bySemanticsLabel('Shelf Book 0\nAuthor');
    final start = firstCover.evaluate().isNotEmpty
        ? tester.getCenter(firstCover.first)
        : tester.getTopLeft(shelf) + const Offset(70, 70);
    final drag = await tester.startGesture(start);
    await drag.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 16));
    final afterFirstMove = scrollable.position.pixels;
    await drag.moveBy(const Offset(0, -120));
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(shelf), viewport);
      expect(scrollable.position.pixels, greaterThan(afterFirstMove));
    }
    await drag.up();
    await tester.pumpAndSettle();
    for (var swipe = 0;
        swipe < 20 && scrollable.position.extentAfter > 1;
        swipe++) {
      final before = scrollable.position.pixels;
      await tester.drag(shelf, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(tester.getSize(shelf), viewport);
      expect(scrollable.position.pixels, greaterThan(before));
    }
    expect(scrollable.position.extentAfter, closeTo(0, 1));
    expect(find.text('Shelf Book 19').hitTestable(), findsOneWidget);
    expect(find.text('Top Shelf').hitTestable(), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('returning from an import reloads new Top Shelf membership', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: LibraryScreen(
            capturedImportAvailabilityLoader: () async =>
                PioneerCapturedHtmlAvailableImportReport(
                  rootPath: fixture.path,
                  imports: const [],
                  completedAt: DateTime.utc(2026),
                  message: 'No imports',
                ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final shelf = find.byKey(const PageStorageKey('library-shelf'));
    expect(
      tester.widget<GridView>(shelf).childrenDelegate.estimatedChildCount,
      7,
    );
    final navigator = Navigator.of(tester.element(find.byType(LibraryScreen)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Import complete')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await AppSettingsService.instance.saveRawSetting(
        'elibrary_top_shelf_v1',
        jsonEncode(List.generate(8, (i) => 'book-$i')),
      );
    });
    await tester.runAsync(() async {
      navigator.pop();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(
      tester.widget<GridView>(shelf).childrenDelegate.estimatedChildCount,
      8,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
