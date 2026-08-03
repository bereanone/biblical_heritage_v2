import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/sandbox_bootstrap.dart';

class CrossReference {
  const CrossReference({
    required this.sourceVerseId,
    required this.targetVerseId,
    required this.score,
    required this.targetReference,
  });

  final int sourceVerseId;
  final int targetVerseId;
  final int score;
  final String targetReference;
}

class CrossReferenceRepository {
  CrossReferenceRepository({Database? database}) : _database = database;

  Database? _database;
  bool _ownsDatabase = false;

  Future<Database> _open() async {
    if (_database != null) return _database!;
    await SandboxBootstrap.ensureCrossReferencesReady();
    final path = await SandboxBootstrap.crossReferencesDatabasePath();
    _database = await openDatabase(path, readOnly: true, singleInstance: false);
    _ownsDatabase = true;
    return _database!;
  }

  Future<List<CrossReference>> forVerse(int sourceVerseId) async {
    final db = await _open();
    final rows = await db.query(
      'cross_references',
      where: 'source_verse_id = ?',
      whereArgs: [sourceVerseId],
      orderBy: 'score DESC, target_verse_id ASC',
    );
    return rows
        .map(
          (row) => CrossReference(
            sourceVerseId: row['source_verse_id'] as int,
            targetVerseId: row['target_verse_id'] as int,
            score: row['score'] as int,
            targetReference: row['target_reference'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<void> close() async {
    if (_ownsDatabase) await _database?.close();
    _database = null;
    _ownsDatabase = false;
  }
}
