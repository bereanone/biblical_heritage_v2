import 'package:flutter/material.dart';

import '../../../core/database/user_database.dart';

class HighlightGroupRecord {
  const HighlightGroupRecord({
    required this.id,
    required this.userId,
    required this.name,
    required this.colorHex,
  });

  final int id;
  final int userId;
  final String name;
  final String colorHex;

  Color get color => _colorFromHex(colorHex);

  static Color _colorFromHex(String hex) {
    final normalized = hex.replaceFirst('#', '');
    final value = int.tryParse(normalized, radix: 16) ?? 0xFFE8DCC8;
    final argb = normalized.length == 8 ? value : (0xFF000000 | value);
    return Color(argb);
  }

  factory HighlightGroupRecord.fromMap(Map<String, Object?> map) {
    int readInt(String key, {int fallback = 0}) {
      final value = map[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    return HighlightGroupRecord(
      id: readInt('id'),
      userId: readInt('user_id', fallback: 1),
      name: map['name']?.toString() ?? '',
      colorHex: map['color_hex']?.toString() ?? '#E8DCC8',
    );
  }
}

class HighlightGroupsRepository {
  Future<int> ensureUserId() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query('users', columns: ['id'], orderBy: 'id ASC', limit: 1);
    if (rows.isNotEmpty) {
      final value = rows.first['id'];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 1;
    }
    return 1;
  }

  Future<List<HighlightGroupRecord>> loadGroups() async {
    final db = await UserDatabase.instance.database;
    final userId = await ensureUserId();
    final rows = await db.query(
      'highlight_groups',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
    );
    return rows.map(HighlightGroupRecord.fromMap).toList(growable: false);
  }

  Future<int> countHighlightsForGroup(int groupId) async {
    final db = await UserDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM highlights WHERE group_id = ?',
      [groupId],
    );
    final value = rows.first['cnt'];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<List<String>> loadVerseRefsForGroup(int groupId) async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'highlights',
      columns: ['verse_ref'],
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'verse_ref COLLATE NOCASE ASC',
    );
    return rows
        .map((row) => row['verse_ref']?.toString() ?? '')
        .where((ref) => ref.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<HighlightGroupRecord> createGroup({
    required String name,
    required String colorHex,
  }) async {
    final db = await UserDatabase.instance.database;
    final userId = await ensureUserId();
    final id = await db.insert('highlight_groups', {
      'user_id': userId,
      'name': name,
      'color_hex': colorHex,
    });
    final rows = await db.query(
      'highlight_groups',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return HighlightGroupRecord.fromMap(rows.first);
  }

  Future<void> deleteGroup(int id) async {
    final usedCount = await countHighlightsForGroup(id);
    if (usedCount > 0) {
      throw StateError('This group is currently in use and cannot be deleted.');
    }
    final db = await UserDatabase.instance.database;
    await db.delete('highlight_groups', where: 'id = ?', whereArgs: [id]);
  }
}
