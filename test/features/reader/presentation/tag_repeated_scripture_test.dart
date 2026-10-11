import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_planner.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

void main() {
  testWidgets(
    'three copies of one verse remain three ordered playlist entries',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('repeated_tag_'),
      ))!;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => p.join(root.path, '.runtime'),
      );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final repository = HashTagRepository();
      await tester.runAsync(() async {
        LibraryRootService.instance.invalidateCachedSelection();
        await LibraryRootService.instance.setLibraryRoot(path: root.path);
        final books = await StudyBibleDatabase.instance.loadBooks();
        expect(books, isNotEmpty);
        for (var i = 0; i < 3; i++) {
          final result = await repository.addBibleRangeToTag(
            tag: '#memory-repeat',
            bookNumber: 58,
            chapter: 12,
            verseStart: 11,
            verseEnd: 11,
          );
          expect(result.inserted, 1);
          expect(result.skipped, 0);
        }
        final entries = await repository.loadEntries('#memory-repeat');
        expect(entries, hasLength(3));
        expect(entries.map((entry) => entry.verseRef).toSet(), hasLength(1));
        expect(entries.map((entry) => entry.shareId).toSet(), hasLength(3));

        final items = await TagPlaybackPlanner(
          bookNames: const {58: 'Hebrews'},
          resolveBlockId: (book, chapter, verse) async => 1,
        ).plan(entries);
        expect(items, hasLength(3));
        expect(items.map((item) => item.entryId).toSet(), hasLength(3));
        expect(items.map((item) => item.label), [
          'Hebrews 12:11',
          'Hebrews 12:11',
          'Hebrews 12:11',
        ]);
        expect(items.every((item) => item.contentClips.isNotEmpty), isTrue);
        await UserDatabase.instance.close();
        LibraryRootService.instance.invalidateCachedSelection();
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );
}
