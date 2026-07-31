import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/database/user_database.dart';
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

  testWidgets('phone header wraps every action below the fixed title row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(size: const Size(430, 932), repository: repository),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('#A-very-long-tag-name'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-tag-item-count')), findsOneWidget);
    expect(find.text('· 0'), findsOneWidget);
    expect(find.byTooltip('Tag actions'), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('phone-tag-toolbar-wrap')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('phone-tag-toolbar-wrap')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Show instructions'), findsOneWidget);
    expect(find.byTooltip('Add Content Item'), findsOneWidget);
    expect(find.byTooltip('Rename'), findsOneWidget);
    expect(find.byTooltip('Move to category'), findsOneWidget);
    expect(find.byTooltip('Delete entire tag'), findsOneWidget);
    expect(find.byTooltip('Presentation Mode').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Delete entire tag').hitTestable(), findsOneWidget);

    final actionTooltips = <String>[
      'Set as default tag',
      'Show instructions',
      'Add Content Item',
      'Presentation Mode',
      'Export to clipboard',
      'Rename',
      'Move to category',
      'Delete entire tag',
    ];
    for (final tooltip in actionTooltips) {
      expect(
        tester.getSize(find.byTooltip(tooltip)).height,
        greaterThanOrEqualTo(44),
      );
    }
    expect(
      tester.getSize(find.byTooltip('Close')).height,
      greaterThanOrEqualTo(44),
    );
    final titleCenter = tester
        .getCenter(find.textContaining('#A-very-long-tag-name'))
        .dy;
    final closeTop = tester.getTopLeft(find.byTooltip('Close')).dy;
    final closeCenter = tester.getCenter(find.byTooltip('Close')).dy;
    final actionsTop = actionTooltips
        .map((tooltip) => tester.getTopLeft(find.byTooltip(tooltip)).dy)
        .toSet();
    expect((titleCenter - closeCenter).abs(), lessThan(2));
    expect(actionsTop.length, greaterThanOrEqualTo(2));
    expect(actionsTop.every((top) => top > closeTop), isTrue);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byTooltip('Rename'));
    await tester.tap(find.byTooltip('Rename'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Rename tag'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Delete entire tag').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Delete entire tag'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Delete entire tag?'), findsOneWidget);
    expect(find.textContaining('This cannot be undone.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPad header retains expanded toolbar without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(size: const Size(1024, 1366), repository: repository),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Tag actions'), findsNothing);
    expect(find.byTooltip('Show instructions'), findsOneWidget);
    expect(find.byTooltip('Move to category'), findsOneWidget);
    expect(find.byTooltip('Delete entire tag'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
