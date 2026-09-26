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
    'trash-can long press soft-deletes only the verse entry and Undo restores it',
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
      await tester.pumpAndSettle();
      expect(find.text('Move to Trash?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect((await repository.loadEntries('#gesture-proof')).length, 1);
      });
      // The row keeps its existing gesture behavior; only the trash control
      // has the new immediate, recoverable long-press action.
      await tester.runAsync(() async {
        final gesture = await tester.startGesture(tester.getCenter(trash));
        await Future<void>.delayed(const Duration(milliseconds: 650));
        await gesture.up();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('Move to Trash?'), findsNothing);
      expect(find.text('Verse moved to Trash.'), findsOneWidget);
      await tester.runAsync(() async {
        expect(await repository.loadEntries('#gesture-proof'), isEmpty);
        final deleted = await repository.loadTrashedEntries('#gesture-proof');
        expect(deleted.length, 1);
      });
      await tester.runAsync(() async {
        await tester.tap(find.text('Undo'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final restored = await repository.loadEntries('#gesture-proof');
        expect(restored.length, 1);
        expect(restored.single.verse, 3);
        expect(await repository.loadTrashedEntries('#gesture-proof'), isEmpty);
      });
      expect(find.byTooltip('Move to Trash'), findsOneWidget);
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
