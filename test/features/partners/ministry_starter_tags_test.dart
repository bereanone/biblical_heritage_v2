import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ministry_tags_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    LibraryRootService.instance.invalidateCachedSelection();
    await LibraryRootService.instance.setLibraryRoot(path: root.path);
  });
  tearDown(() async {
    await UserDatabase.instance.close();
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await root.delete(recursive: true);
  });
  test(
    'ministry seeds are idempotent and never move an existing personal list',
    () async {
      final repository = HashTagRepository();
      await repository.ensureMinistryStarterTags(
        folder: 'Personal',
        tags: ['#Faith'],
      );
      await repository.ensureMinistryStarterTags(
        folder: 'Advent Defense League',
        tags: ['#Faith', '#NewStudy'],
      );
      await repository.ensureMinistryStarterTags(
        folder: 'Advent Defense League',
        tags: ['#Faith', '#NewStudy'],
      );
      final summaries = await repository.loadSummaries();
      expect(
        summaries.where((s) => s.tag == '#Faith').single.category,
        'Personal',
      );
      expect(
        summaries.where((s) => s.tag == '#NewStudy').single.category,
        'Advent Defense League',
      );
      expect(summaries.where((s) => s.tag == '#NewStudy').single.count, 0);
      expect(
        (await repository.loadCategoryOptions()),
        contains('Advent Defense League'),
      );
    },
  );
  test('empty approved list creates only its ministry folder', () async {
    final repository = HashTagRepository();
    await repository.ensureMinistryStarterTags(
      folder: 'Advent Defense League',
      tags: [],
    );
    expect(await repository.loadSummaries(), isEmpty);
    expect(
      await repository.loadCategoryOptions(),
      contains('Advent Defense League'),
    );
  });
}
