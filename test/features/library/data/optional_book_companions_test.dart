import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/optional_book_companions.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';

class _Assets extends CachingAssetBundle {
  int reads = 0;
  @override Future<ByteData> load(String key) async {
    reads++;
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
  test('mismatch returns before loading companions or touching the database', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance:false);
    final assets = _Assets();
    try {
      expect(await OptionalBookCompanions.apply(db:db,itemId:'unknown',sourceHash:'wrong',assets:assets),false);
      expect(assets.reads,0);
      expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE name LIKE 'library_%'"),isEmpty);
    } finally {await db.close();}
  });
  test('matching source reuses prepared contents and reference positions without book text', () async {
    final db = await openDatabase(inMemoryDatabasePath, singleInstance:false);
    try {
      await ELibrarySchema.ensure(db);
      await db.insert('library_items',{'id':'own-copy','title':'Own book','file_name':'own.epub',
        'relative_path':'own.epub','created_at':'before','updated_at':'before','device_id':'test'});
      final assets = _Assets();
      for(var i=0;i<2;i++) {
        expect(await OptionalBookCompanions.apply(db:db,itemId:'own-copy',sourceHash:OptionalBookCompanions.worSource,assets:assets),true);
      }
      expect((await db.query('library_navigation_items')).length,57);
      expect((await db.query('library_source_reference_map')).length,1370);
      expect(await db.query('library_document_blocks'),isEmpty);
      expect(await db.query('library_text_blocks'),isEmpty);
      expect((await db.query('library_items')).single['cover_path'],'assets/library_covers/thumbs/WOR.png');
      expect((await db.query('library_items')).single['relative_path'],'own.epub');
    } finally {await db.close();}
  });
  test('WOR title alone cannot select optional or manually copied audio', () async {
    final root=await Directory.systemTemp.createTemp('optional-audio-');
    try {
      final dir=await Directory('${root.path}/old-copy').create();
      await File('${dir.path}/one.mp3').writeAsBytes([1,2,3]);
      await File('${dir.path}/audio-manifest.json').writeAsString(jsonEncode({
        'title':'Waggoner on Romans','total_chapters':1,
        'tracks':[{'chapter':1,'title':'Chapter one','file':'one.mp3','cues':[
          {'start_ms':0,'text_sha256':sha256.convert(utf8.encode('example paragraph')).toString()}
        ]}]
      }));
      expect(await RecordedLibraryAudioPackage.findIn(root,'Waggoner on Romans'),isNull);
      expect(await RecordedLibraryAudioPackage.findIn(root,'Waggoner on Romans',sourceHash:'wrong'),isNull);
      final found=await RecordedLibraryAudioPackage.findIn(root,'My imported title',sourceHash:OptionalBookCompanions.worSource);
      expect(found,isNotNull);
      final cue=found!.tracks.single.cues.single;
      expect(cue.text,isEmpty);
      expect(recordedCueItemIndex(cue,[const LibrarySpeechItem(cursor:'0',nextCursor:'1',text:'Example paragraph.')]),0);
      expect(recordedCueItemIndex(cue,[const LibrarySpeechItem(cursor:'0',nextCursor:'1',text:'Different paragraph.')]),-1);
    } finally {await root.delete(recursive:true);}
  });
  test('managed installer excludes the optional book text and EPUB', () async {
    final manifest=jsonDecode(await File('assets/bundled_library/manifest.json').readAsString()) as Map;
    expect((manifest['books'] as List).length,6);
    expect((manifest['books'] as List).any((b)=>b['title']=='Waggoner on Romans'),false);
    expect((manifest['resources'] as List).any((b)=>b['sha256']==OptionalBookCompanions.worSource),false);
    expect(await File('assets/bundled_library/files/${OptionalBookCompanions.worSource}').exists(),false);
    final db=await openReadOnlyDatabase(File('assets/bundled_library/catalog.db').absolute.path,singleInstance:false);
    try {expect(await db.query('library_items',where:'title=?',whereArgs:['Waggoner on Romans']),isEmpty);} finally {await db.close();}
  });
}
