import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';

void main() {
  testWidgets(
    'actual BRHC bundle first opens at Chapter 1 with nested numbered Contents',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final setup = await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final temp = await Directory.systemTemp.createTemp(
          'brhc-reader-proof-',
        );
        final db = await openReadOnlyDatabase(
          p.absolute('assets/bundled_library/catalog.db'),
          singleInstance: false,
        );
        final row = (await db.query(
          'library_items',
          where: 'id=?',
          whereArgs: [
            'library_item_research_pioneer_bible_readings_home_circle_1914',
          ],
        )).single;
        expect(row['last_opened'], isNull);
        expect(row['anchor_id'], isNull);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => temp.path,
            );
        return (temp: temp, db: db, item: LibraryCatalogItem.fromRow(row));
      });
      final ready = setup!;
      await tester.pumpWidget(
        MaterialApp(
          home: CanonicalLibraryReaderScreen(
            item: ready.item,
            repository: LibraryDocumentRepository(ready.db),

            macosAutoscroll: false,
          ),
        ),
      );
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('Chapter 1. The Scriptures').evaluate().isNotEmpty) break;
      }
      expect(find.text('Chapter 1. The Scriptures'), findsOneWidget);
      expect(find.text("Chapter 48. Nebuchadnezzar's Dream"), findsNothing);
      await tester.tap(find.text('Contents'));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('1. The Scriptures').evaluate().isNotEmpty) break;
      }
      final chapter = find.text('1. The Scriptures');
      final section = find.text(
        'Section 1 — The Bible; How to Study and Understand It',
      );
      expect(chapter, findsOneWidget);
      expect(section, findsOneWidget);
      expect(
        tester.getTopLeft(chapter).dx,
        greaterThan(tester.getTopLeft(section).dx),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await UserDatabase.instance.close();
        await ELibraryDatabase.instance.close();
        await ready.db.close();
        await ready.temp.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
