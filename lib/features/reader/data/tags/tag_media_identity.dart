import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Imported entries expose rowid to the editor, but attachments reference the
/// stable text primary key. Legacy entries retain their numeric identifier.
Future<String> tagMediaEntryId(
  DatabaseExecutor db,
  int editorId, {
  required bool normalized,
}) async {
  if (!normalized) return editorId.toString();
  final rows = await db.query(
    'tag_items',
    columns: ['id'],
    where: 'rowid = ?',
    whereArgs: [editorId],
    limit: 1,
  );
  final id = rows.firstOrNull?['id']?.toString();
  if (id == null || id.isEmpty)
    throw StateError('Imported entry no longer exists');
  return id;
}
