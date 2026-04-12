import 'package:flutter/material.dart';

import '../../../core/database/user_database.dart';
import 'highlight_groups_repository.dart';

class VerseHighlightRecord {
  const VerseHighlightRecord({
    required this.id,
    required this.groupId,
    required this.verseRef,
    required this.colorHex,
  });

  final int id;
  final int groupId;
  final String verseRef;
  final String colorHex;

  Color get color {
    final normalized = colorHex.replaceFirst('#', '');
    return Color(0xFF000000 | int.parse(normalized, radix: 16));
  }
}

class HighlightsRepository {
  Future<List<HighlightGroupRecord>> loadGroups() async {
    return HighlightGroupsRepository().loadGroups();
  }

  Future<void> applyHighlight({
    required int groupId,
    required String verseRef,
  }) async {
    await applyHighlightToVerseRefs(
      groupId: groupId,
      verseRefs: [verseRef],
    );
  }

  Future<void> applyHighlightToVerseRefs({
    required int groupId,
    required List<String> verseRefs,
  }) async {
    if (verseRefs.isEmpty) return;
    final db = await UserDatabase.instance.database;
    final batch = db.batch();
    for (final verseRef in verseRefs) {
      batch.delete('highlights', where: 'verse_ref = ?', whereArgs: [verseRef]);
      batch.insert('highlights', {
        'group_id': groupId,
        'verse_ref': verseRef,
        'start_token': null,
        'end_token': null,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeHighlight(String verseRef) async {
    await removeHighlightsForVerseRefs([verseRef]);
  }

  Future<void> removeHighlightsForVerseRefs(List<String> verseRefs) async {
    if (verseRefs.isEmpty) return;
    final db = await UserDatabase.instance.database;
    final batch = db.batch();
    for (final verseRef in verseRefs) {
      batch.delete('highlights', where: 'verse_ref = ?', whereArgs: [verseRef]);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, VerseHighlightRecord>> loadHighlightsForVerseRefs(
    List<String> verseRefs,
  ) async {
    if (verseRefs.isEmpty) return const <String, VerseHighlightRecord>{};
    final db = await UserDatabase.instance.database;
    final placeholders = List.filled(verseRefs.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT h.id, h.group_id, h.verse_ref, g.color_hex
      FROM highlights h
      JOIN highlight_groups g ON g.id = h.group_id
      WHERE h.verse_ref IN ($placeholders)
      ORDER BY h.id ASC
      ''',
      verseRefs,
    );
    final result = <String, VerseHighlightRecord>{};
    for (final row in rows) {
      final verseRef = row['verse_ref']?.toString() ?? '';
      if (verseRef.isEmpty || result.containsKey(verseRef)) continue;
      final groupIdValue = row['group_id'];
      final idValue = row['id'];
      if (groupIdValue == null || idValue == null) continue;
      result[verseRef] = VerseHighlightRecord(
        id: (idValue as num).toInt(),
        groupId: (groupIdValue as num).toInt(),
        verseRef: verseRef,
        colorHex: row['color_hex']?.toString() ?? '#E8DCC8',
      );
    }
    return result;
  }
}
