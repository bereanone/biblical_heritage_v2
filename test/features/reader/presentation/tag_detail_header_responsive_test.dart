import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/reader/presentation/tag_detail_screen.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

Future<void> _installPathProviderMocks(Directory root) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => root.path);
}

Future<void> _clearUserDatabase(Directory root) async {
  await UserDatabase.instance.close();
  final dbPath = p.join(root.path, 'BiblicalHeritage', 'v2', 'user.db');
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('$dbPath$suffix');
    if (await file.exists()) await file.delete();
  }
}

Widget _screen({required Size size, required HashTagRepository repository}) {
  return MaterialApp(
    theme: ThemeData(fontFamily: 'Roboto'),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: SizedBox.fromSize(
          size: size,
          child: HashTagDetailScreen(
            repository: repository,
            tag:
                '#A-very-long-tag-name-that-must-truncate-without-moving-actions',
            category: 'Long Category Name',
            fontScale: 1,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await fonts.load();
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;
  late HashTagRepository repository;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('tag_detail_header_');
    await _installPathProviderMocks(root);
  });

  setUp(() async {
    await _clearUserDatabase(root);
    repository = HashTagRepository();
    await repository.ensureSchema();
  });

  tearDownAll(() async {
    await _clearUserDatabase(root);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  for (final size in [const Size(430, 932), const Size(1024, 1366)]) {
    testWidgets('List actions remain accessible at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_screen(size: size, repository: repository));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('#A-very-long-tag-name'), findsOneWidget);
      expect(find.byTooltip('Instructions'), findsOneWidget);
      expect(find.byTooltip('Add entry').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('More list actions'), findsNothing);
      expect(find.byTooltip('Export list').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Delete list').hitTestable(), findsOneWidget);
      expect(find.text('Export list'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('List settings'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('List name'), findsOneWidget);
      expect(find.text('Folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'portrait entries keep wide reading text below scrolling actions',
    (tester) async {
      const size = Size(360, 800);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await StudyBibleDatabase.instance.loadBooks();
        await repository.addBibleRangeToTag(
          tag:
              '#A-very-long-tag-name-that-must-truncate-without-moving-actions',
          category: 'Long Category Name',
          bookNumber: 66,
          chapter: 9,
          verseStart: 19,
          verseEnd: 19,
        );
        await tester.pumpWidget(_screen(size: size, repository: repository));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      final verse = find.textContaining('For their power');
      expect(verse, findsOneWidget);
      final verseRect = tester.getRect(verse);
      expect(verseRect.width, greaterThan(234));
      expect(
        tester.getRect(find.byTooltip('Edit item')).bottom,
        lessThan(verseRect.top),
      );
      expect(find.text('Move\nup'), findsOneWidget);
      expect(find.text('Move\ndown'), findsOneWidget);
      expect(find.text('Trash').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byTooltip('Move to Trash')).right,
        lessThanOrEqualTo(verseRect.right),
      );
      expect(find.byType(Scrollbar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
