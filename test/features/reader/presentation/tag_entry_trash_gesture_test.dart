import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/reader/presentation/tag_detail_screen.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

void main() {
  testWidgets(
    'trash-can tap immediately soft-deletes only the selected verse entry',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('tag_trash_gesture_'),
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
        await StudyBibleDatabase.instance.loadBooks();
        await repository.addBibleRangeToTag(
          tag: '#gesture-proof',
          bookNumber: 43,
          chapter: 3,
          verseStart: 3,
          verseEnd: 3,
        );
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HashTagDetailScreen(
                repository: repository,
                tag: '#gesture-proof',
                fontScale: 1,
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      final trash = find.byTooltip('Move to Trash');
      expect(trash, findsOneWidget);
      await tester.tap(trash);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Move to Trash?'), findsNothing);
      await tester.runAsync(() async {
        expect(await repository.loadEntries('#gesture-proof'), isEmpty);
        final deleted = await repository.loadTrashedEntries('#gesture-proof');
        expect(deleted.length, 1);
      });
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => UserDatabase.instance.close());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      LibraryRootService.instance.invalidateCachedSelection();
    },
  );
}
