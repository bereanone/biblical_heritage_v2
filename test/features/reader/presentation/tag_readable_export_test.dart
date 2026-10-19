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

  test('range display uses actual starting verse and preserves raw text', () {
    const text = 'First verse.\nSecond verse.\nThird verse.';
    const entry = HashTagEntry(
      id: 1,
      bookNumber: 66,
      chapter: 14,
      verse: 6,
      verseEnd: 8,
      verseRef: 'Revelation 14:6-8',
      verseText: text,
      createdAt: 0,
      sortOrder: 0,
    );
    expect(
      entry.numberedVerseText,
      '6 First verse.\n7 Second verse.\n8 Third verse.',
    );
    expect(entry.verseText, text);
    expect(
      formatBibleRangeForDisplay('Single.', verseStart: 6, verseEnd: 6),
      'Single.',
    );
    expect(
      formatBibleRangeForDisplay('Incomplete.', verseStart: 6, verseEnd: 8),
      'Incomplete.',
    );
  });

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

  test(
    'twelve-verse import displays every verse and round trips labels',
    () async {
      await repository.importSharedListFromText(
        '#Numbered (1 item)\n\nRevelation 14:1-12\n',
      );
      final entries = await repository.loadEntries('#Numbered');
      expect(entries, hasLength(1));
      final entry = entries.single;
      final lines = entry.numberedVerseText.split('\n');
      expect(lines, hasLength(12));
      for (var i = 0; i < 12; i++) {
        expect(lines[i], startsWith('${i + 1} '));
      }
      expect(lines.first, contains('a Lamb stood'));
      expect(lines.last, contains('patience of the saints'));
      await repository.importSharedListFromText(
        '#NumberedCopy (1 item)\n\nRevelation 14:1-12\n${entry.numberedVerseText}\n',
      );
      final copy = (await repository.loadEntries('#NumberedCopy')).single;
      expect(copy.verseEnd, 12);
      expect(copy.verseText, entry.verseText);
      expect(copy.numberedVerseText, entry.numberedVerseText);
    },
  );

  testWidgets(
    'readable clipboard export contains full range and no technical metadata',
    (tester) async {
      const tag =
          '#A-very-long-tag-name-that-must-truncate-without-moving-actions';
      await tester.runAsync(() async {
        await repository.importSharedListFromText(
          '$tag (1 item)\n\nRevelation 12:1-3\n',
        );
      });
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        _screen(size: const Size(430, 932), repository: repository),
      );
      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Export list'));
        for (var attempt = 0; attempt < 30 && copied == null; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await tester.pumpAndSettle();
      expect(copied, contains('Revelation 12:1-3'));
      expect(copied, contains('1 And there appeared'));
      expect(copied, contains('\n2 And she being'));
      expect(copied, contains('\n3 And there appeared'));
      expect(copied, contains('great red dragon'));
      expect(copied, isNot(contains('metadata:')));
      expect(copied, isNot(contains('share_id')));
    },
  );
}
