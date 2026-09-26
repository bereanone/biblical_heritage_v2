// Opt-in proof of the exact eLibrary Setup > Import One Book Package EPUB path.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_collection_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_text_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('single-book EPUB import preserves CIS artwork and navigation', () async {
    if (Platform.environment['RUN_CIS_SINGLE_IMPORT_REPRO']!='1') return;
    final output=p.absolute('tool/Verification/cis_1914_restoration/output');
    final root=await Directory(output).createTemp('single_import_repro_');
    final runtime=await Directory(p.join(root.path,'.runtime')).create();
    const channel=MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(_) async=>runtime.path);
    sqfliteFfiInit(); databaseFactory=databaseFactoryFfi;
    LibraryRootService.instance.invalidateCachedSelection();
    await LibraryRootService.instance.setLibraryRoot(path:root.path);
    try {
      final source=p.join(output,'CIS.epub');
      final work=await loadPioneerWorkFromLocalEpubFile(source);
      expect(work,isNotNull);
      final result=await PioneerTextImportService.instance.importLocalEpubFile(work:work!,filePath:source);
      final db=await ELibraryDatabase.instance.database;
      final item=(await db.query('library_items',where:'id=?',whereArgs:[result.libraryItemId])).single;
      Future<int> count(String table,String condition) async => (await db.rawQuery('SELECT count(*) AS n FROM $table WHERE library_item_id=? $condition',[result.libraryItemId])).single['n'] as int;
      final images=await count('library_document_blocks',"AND block_type='image'");
      final navigation=await count('library_document_navigation','');
      final report={'isolated_root':root.path,'item_id':result.libraryItemId,'reported_status':result.status.name,'file_format':item['file_format'],'relative_path':item['relative_path'],'canonical_images':images,'canonical_navigation':navigation,'expected_images':14,'expected_navigation':94,'live_library_modified':false};
      await File(p.join(output,'single_book_import_repro.json')).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      expect(images,14,reason:'Actual selected-file import must retain all illustrated assets');
      expect(navigation,94,reason:'Actual selected-file import must retain source navigation');
    } finally {
      await ELibraryDatabase.instance.close(); await UserDatabase.instance.close();
      LibraryRootService.instance.invalidateCachedSelection();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
    }
  });
}
