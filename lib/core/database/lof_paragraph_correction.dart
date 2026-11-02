import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Printed Review and Herald, February 21, 1899, page 116, right column.
/// Retain both source identities and all later orders. The second fragment is
/// archived in place; its recording still plays at its original timestamp.
class LofParagraphCorrection {
  static const sourceHash =
      "14a067c0b0a6cdf8cdf8fbbcf3205bdf261d69d7288512ffe041c7034a4a1c66";
  static const headId =
      "ldb_b50ee675cf0c61bcb81a491d6a9106ca1765392a99c357176770945c15986097";
  static const tailId =
      "ldb_4a1aeab4e5ce9fdd9c7aa2547cbccab3fcc6932ee7105296e588d6fa5a1578b6";
  static const headBefore =
      "You know also the other scripture, that “by the word of the lord were the heavens made, and all the host of them by the breath of his mouth ... for he spake and it was.” Ps. 33:6-";
  static const tailBefore =
      "9. Upon this I will ask you a question: How long after He spoke, before the things were? How much time passed after He spoke, before the thing was? [Voice: “No time.”] Not a week? No. Not six long periods of time? No. Evolution even that which recognizes a Creator, holds that indefinite countless ages or “six long, indefinite periods of time,” passed in the formation of the things which are seen, after he spoke. But that is evolution, not creation. Evolution is by long processes. Creation is by the word spoken.";
  static const correctionId = 'lof-psalm-paragraph-18990221-v1';

  static Future<int> apply(DatabaseExecutor db, String itemId) async {
    final joined = await _join(db, itemId);
    final punctuation = await _restoreComma(db, itemId);
    return joined > 0 ? joined : punctuation;
  }

  static Future<int> _join(DatabaseExecutor db, String itemId) async {
    final rows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND id IN (?, ?)',
      whereArgs: [itemId, headId, tailId],
      orderBy: 'display_order',
    );
    if (rows.length != 2 ||
        rows[0]['plain_text'] != headBefore ||
        rows[1]['plain_text'] != tailBefore ||
        rows[0]['display_order'] != 345 ||
        rows[1]['display_order'] != 346)
      return 0;
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS library_publisher_text_repairs (
      correction_id TEXT NOT NULL, block_id TEXT NOT NULL,
      previous_row_json TEXT NOT NULL, applied_at TEXT NOT NULL,
      PRIMARY KEY(correction_id, block_id))''',
    );
    for (final row in rows) {
      await db.insert(
        'library_publisher_text_repairs',
        {
          'correction_id': correctionId,
          'block_id': row['id'],
          'previous_row_json': jsonEncode(row),
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    final head = Map<String, dynamic>.from(
      jsonDecode(rows[0]['formatted_content'] as String) as Map,
    );
    final tail = Map<String, dynamic>.from(
      jsonDecode(rows[1]['formatted_content'] as String) as Map,
    );
    head['metadata'] = {
      ...?head['metadata'] as Map?,
      'publisher_original_text': headBefore,
      'publisher_joined_tail_id': tailId,
      'publisher_correction': correctionId,
    };
    head['nodes'] = [...head['nodes'] as List, ...tail['nodes'] as List];
    // This exact witness has two plain text nodes with identical styling.
    // Join those nodes too so the Bible citation resolver sees the whole range.
    final nodes = head['nodes'] as List;
    if (nodes.length == 2 && nodes.every((n) => n['type'] == 'text')) {
      final left = Map<String, dynamic>.from(nodes[0] as Map)..remove('text');
      final right = Map<String, dynamic>.from(nodes[1] as Map)..remove('text');
      if (jsonEncode(left) == jsonEncode(right)) {
        head['nodes'] = [
          {...left, 'text': headBefore + tailBefore},
        ];
      }
    }
    tail['metadata'] = {
      ...?tail['metadata'] as Map?,
      'content_role': 'superseded_source_fragment',
      'publisher_joined_head_order': 345,
      'publisher_joined_head_id': headId,
      'publisher_joined_offset': headBefore.length,
      'publisher_correction': correctionId,
    };
    final combined = headBefore + tailBefore;
    for (var i = 0; i < 2; i++) {
      final text = i == 0 ? combined : tailBefore;
      final formatted = jsonEncode(i == 0 ? head : tail);
      final sep = String.fromCharCode(0);
      await db.update(
        'library_document_blocks',
        {
          'plain_text': text,
          'formatted_content': formatted,
          'content_hash': sha256
              .convert(utf8.encode('paragraph$sep$text$sep$formatted'))
              .toString(),
        },
        where: 'id = ?',
        whereArgs: [rows[i]['id']],
      );
    }
    // Existing canonical notes keep their IDs, selected words, timestamps and
    // note bodies; only their coordinate changes to the restored paragraph.
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='elibrary_markups'",
    );
    if (tables.isNotEmpty) {
      final notes = await db.query(
        'elibrary_markups',
        where: 'library_item_id = ? AND epub_href = ?',
        whereArgs: [itemId, 'canonical:$tailId'],
      );
      final tokenOffset = RegExp(r'\S+').allMatches(headBefore).length - 1;
      for (final note in notes) {
        await db.insert(
          'library_publisher_text_repairs',
          {
            'correction_id': correctionId,
            'block_id': 'markup:${note['id']}',
            'previous_row_json': jsonEncode(note),
            'applied_at': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await db.update(
          'elibrary_markups',
          {
            'epub_href': 'canonical:$headId',
            'start_char_offset':
                (note['start_char_offset'] as int) + headBefore.length,
            'end_char_offset':
                (note['end_char_offset'] as int) + headBefore.length,
            if (note['start_token_index'] != null)
              'start_token_index':
                  (note['start_token_index'] as int) + tokenOffset,
            if (note['end_token_index'] != null)
              'end_token_index': (note['end_token_index'] as int) + tokenOffset,
          },
          where: 'id = ?',
          whereArgs: [note['id']],
        );
      }
    }
    return 2;
  }

  static Future<int> _restoreComma(DatabaseExecutor db, String itemId) async {
    const before = 'Evolution even that which recognizes a Creator, holds';
    const after = 'Evolution, even that which recognizes a Creator, holds';
    const repair = 'lof-parenthetical-comma-18990221-v1';
    final rows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND id IN (?, ?)',
      whereArgs: [itemId, headId, tailId],
    );
    var changed = 0;
    for (final row in rows) {
      final text = row['plain_text'] as String;
      final expected = row['id'] == headId
          ? headBefore + tailBefore
          : tailBefore;
      if (text != expected) continue;
      final formatted = Map<String, dynamic>.from(
        jsonDecode(row['formatted_content'] as String) as Map,
      );
      if ((formatted['metadata'] as Map?)?['publisher_correction'] !=
          correctionId)
        continue;
      final position = text.indexOf(before) + 'Evolution'.length;
      await db.insert(
        'library_publisher_text_repairs',
        {
          'correction_id': repair,
          'block_id': row['id'],
          'previous_row_json': jsonEncode(row),
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      void patch(dynamic value) {
        if (value is List) {
          for (final node in value) {
            patch(node);
          }
        }
        if (value is Map) {
          for (final key in value.keys.toList()) {
            if (key == 'text' && value[key] is String) {
              value[key] = (value[key] as String).replaceFirst(before, after);
            } else {
              patch(value[key]);
            }
          }
        }
      }

      patch(formatted['nodes']);
      final corrected = text.replaceFirst(before, after);
      final encoded = jsonEncode(formatted);
      final sep = String.fromCharCode(0);
      await db.update(
        'library_document_blocks',
        {
          'plain_text': corrected,
          'formatted_content': encoded,
          'content_hash': sha256
              .convert(utf8.encode('paragraph$sep$corrected$sep$encoded'))
              .toString(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='elibrary_markups'",
      );
      if (tables.isNotEmpty) {
        final notes = await db.query(
          'elibrary_markups',
          where: 'library_item_id = ? AND epub_href = ?',
          whereArgs: [itemId, 'canonical:${row['id']}'],
        );
        for (final note in notes) {
          final start = note['start_char_offset'] as int;
          final end = note['end_char_offset'] as int;
          if (start < position && end <= position) continue;
          await db.insert(
            'library_publisher_text_repairs',
            {
              'correction_id': repair,
              'block_id': 'markup:${note['id']}',
              'previous_row_json': jsonEncode(note),
              'applied_at': DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          await db.update(
            'elibrary_markups',
            {
              'start_char_offset': start >= position ? start + 1 : start,
              'end_char_offset': end > position ? end + 1 : end,
            },
            where: 'id = ?',
            whereArgs: [note['id']],
          );
        }
      }
      changed++;
    }
    return changed;
  }
}
