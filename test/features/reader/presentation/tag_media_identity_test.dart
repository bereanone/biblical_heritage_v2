import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/reader/data/tags/tag_media_identity.dart';

void main() {
  test('imported images survive reload without colliding with legacy row numbers', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE tag_items(id TEXT PRIMARY KEY)');
    await db.execute('CREATE TABLE tag_item_media(tag_item_id TEXT, relative_path TEXT)');
    await db.insert('tag_items', {'rowid':26, 'id':'imported-scripture'});
    final legacy = await tagMediaEntryId(db, 26, normalized:false);
    final imported = await tagMediaEntryId(db, 26, normalized:true);
    await db.insert('tag_item_media', {'tag_item_id':legacy, 'relative_path':'old.png'});
    await db.insert('tag_item_media', {'tag_item_id':imported, 'relative_path':'today.png'});
    expect(imported, 'imported-scripture');
    final reloaded = await db.query('tag_item_media', where:'tag_item_id = ?', whereArgs:['imported-scripture']);
    expect(reloaded.single['relative_path'], 'today.png');
    await db.delete('tag_item_media', where:'tag_item_id = ?', whereArgs:[imported]);
    expect((await db.query('tag_item_media')).single['relative_path'], 'old.png');
    await expectLater(tagMediaEntryId(db, 27, normalized:true), throwsStateError);
  });
}
