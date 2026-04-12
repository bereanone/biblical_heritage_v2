import '../../../core/database/user_database.dart';

class HistoryLogEntry {
  const HistoryLogEntry({
    required this.blockId,
    required this.timestamp,
  });

  factory HistoryLogEntry.fromMap(Map<String, Object?> row) {
    return HistoryLogEntry(
      blockId: row['block_id'] as int,
      timestamp: row['ts'] as int,
    );
  }

  final int blockId;
  final int timestamp;
}

class HistoryLogService {
  HistoryLogService._();

  static final HistoryLogService instance = HistoryLogService._();

  Future<void> insertHistory(int blockId) async {
    final db = await UserDatabase.instance.database;
    final latestRows = await db.query(
      'history',
      columns: ['id', 'block_id'],
      orderBy: 'ts DESC',
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    if (latestRows.isNotEmpty && latestRows.first['block_id'] == blockId) {
      await db.update(
        'history',
        {'ts': now},
        where: 'id = ?',
        whereArgs: [latestRows.first['id']],
      );
      return;
    }

    await db.insert(
      'history',
      {
        'block_id': blockId,
        'ts': now,
      },
    );
  }

  Future<List<HistoryLogEntry>> fetchHistory({int limit = 100}) async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'history',
      columns: ['block_id', 'ts'],
      orderBy: 'ts DESC',
      limit: limit,
    );
    return rows.map(HistoryLogEntry.fromMap).toList();
  }
}
