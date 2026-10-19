import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/library/presentation/library_speech_controls.dart';

class DelayedOpeningRepository extends LibraryDocumentRepository {
  DelayedOpeningRepository(super.db, this.ready);
  final Future<void> ready;
  @override
  Future<int?> openingDisplayOrder(String id, {String? bookTitle}) async {
    await ready;
    return super.openingDisplayOrder(id, bookTitle: bookTitle);
  }
}

void main() {
  testWidgets('audio indexing waits for delayed canonical book initialization', (
    tester,
  ) async {
    final setup = await tester.runAsync(() async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('audio_ready_');
      final db = await databaseFactoryFfi.openDatabase(
        '${dir.path}/library.db',
      );
      await ELibrarySchema.ensure(db);
      final source = File('${dir.path}/source.html');
      await source.writeAsString(
        '<h1>Chapter 1</h1><p>Nature and revelation alike testify of love.</p><h1>Chapter 12</h1><p>Many especially those who are young have questions.</p>',
      );
      await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: 'audio-ready-book',
        source: source,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      return (dir: dir, db: db);
    });
    final gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalLibraryReaderScreen(
          item: LibraryCatalogItem.fromRow({
            'id': 'audio-ready-book',
            'title': 'Test Book',
            'relative_path': 'source.html',
            'file_format': 'html',
          }),
          repository: DelayedOpeningRepository(setup!.db, gate.future),
          macosAutoscroll: true,
        ),
      ),
    );
    final controls = tester.widget<LibrarySpeechControls>(
      find.byType(LibrarySpeechControls),
    );
    var finished = false;
    final pending = controls.load('3').then((value) {
      finished = true;
      return value;
    });
    await tester.pump();
    expect(
      finished,
      isFalse,
      reason: 'Not-yet-loaded text must not be indexed as an empty book.',
    );
    gate.complete();
    for (var i = 0; i < 60 && !finished; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finished, isTrue);
    final item = await pending;
    expect(item?.sourceCursor, '3');
    expect(item?.text, startsWith('Many especially'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await UserDatabase.instance.close();
      await ELibraryDatabase.instance.close();
      await setup.db.close();
      await setup.dir.delete(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });
}
