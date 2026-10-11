import 'dart:convert';

import '../../../core/database/study_bible_database.dart';
import 'viewer_strongs_models.dart';

class ViewerStrongsRepository {
  const ViewerStrongsRepository();

  Future<ViewerAbbottSmithEntry?> loadAbbottSmithEntry(String strongsId) async {
    final canonical = normalizeStrongsCanonical(strongsId);
    if (canonical == null || !canonical.startsWith('G')) return null;
    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.query(
      'lexicon_entries',
      columns: ['payload'],
      where: 'source_code = ? AND strongs_canonical = ?',
      whereArgs: ['abbott_smith', canonical],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final data =
        jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
    List<ViewerLexiconPart> parts(Object? raw) => [
      for (final item in raw as List<dynamic>)
        ViewerLexiconPart(
          (item as Map<String, dynamic>)['text'] as String,
          blockId: item['block_id'] as int?,
        ),
    ];
    return ViewerAbbottSmithEntry(
      senses: [
        for (final item in data['senses'] as List<dynamic>)
          ViewerLexiconSense(
            number: (item as Map<String, dynamic>)['number'] as String,
            parts: parts(item['parts']),
          ),
      ],
      related: [
        for (final item in data['related'] as List<dynamic>) parts(item),
      ],
    );
  }

  Future<ViewerBdbEntry?> loadBdbEntry(String strongsId) async {
    final canonical = normalizeStrongsCanonical(strongsId);
    if (canonical == null || !canonical.startsWith('H')) return null;
    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.query(
      'lexicon_entries',
      columns: ['article_id', 'payload'],
      where: 'source_code = ? AND strongs_canonical = ?',
      whereArgs: ['bdb', canonical],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload =
        jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
    return ViewerBdbEntry(
      text: payload['text']?.toString() ?? '',
      articleId: rows.first['article_id']?.toString() ?? '',
    );
  }

  Future<String?> loadMorphologyTag({
    required int blockId,
    required int mappedTokenIndex,
  }) async {
    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.query(
      'bible_tokens',
      columns: ['morphology_tag'],
      where: 'block_id = ? AND verse_index = ?',
      whereArgs: [blockId, mappedTokenIndex - 1],
      limit: 1,
    );
    final tag = rows.isEmpty
        ? ''
        : rows.first['morphology_tag']?.toString().trim() ?? '';
    return tag.isEmpty ? null : tag;
  }

  Future<ViewerStrongsEntry?> loadEntry(String strongsId) async {
    final canonical = normalizeStrongsCanonical(strongsId);
    if (canonical == null) return null;

    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.query(
      'strongs_dictionary',
      columns: [
        'strongs_canonical',
        'language',
        'lemma',
        'transliteration',
        'pronunciation',
        'part_of_speech',
        'short_definition',
      ],
      where: 'strongs_canonical = ? OR strongs_number = ?',
      whereArgs: [canonical, canonical],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    return ViewerStrongsEntry(
      strongsId: row['strongs_canonical']?.toString().trim().isNotEmpty == true
          ? row['strongs_canonical']!.toString().trim()
          : canonical,
      language: row['language']?.toString().trim() ?? '',
      lemma: row['lemma']?.toString().trim() ?? '',
      transliteration: row['transliteration']?.toString().trim() ?? '',
      pronunciation: row['pronunciation']?.toString().trim() ?? '',
      partOfSpeech: row['part_of_speech']?.toString().trim() ?? '',
      shortDefinition: row['short_definition']?.toString().trim() ?? '',
    );
  }

  Future<List<ViewerStrongsOccurrence>> loadOccurrences(
    String strongsId,
  ) async {
    final canonical = normalizeStrongsCanonical(strongsId);
    if (canonical == null) return const <ViewerStrongsOccurrence>[];

    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.rawQuery(
      '''
      SELECT
        bb.id AS block_id,
        bb.book_number AS book_number,
        COALESCE(b.book_name, 'Book ' || bb.book_number) AS book_name,
        bb.chapter AS chapter,
        bb.block_index AS verse,
        COALESCE(bb.html, '') AS html,
        COALESCE(bb.plain_text, '') AS plain_text
      FROM bible_tokens bt
      JOIN bible_blocks bb ON bb.id = bt.block_id
      LEFT JOIN books b ON b.book_number = bb.book_number
      WHERE COALESCE(bt.strongs_canonical, bt.strongs_number, '') = ?
      GROUP BY bb.id, b.book_name, bb.chapter, bb.block_index, bb.html, bb.plain_text
      ORDER BY bb.book_number, bb.chapter, bb.block_index
      ''',
      [canonical],
    );

    return rows
        .map(
          (row) => ViewerStrongsOccurrence(
            blockId: (row['block_id'] as num?)?.toInt() ?? 0,
            bookNumber: (row['book_number'] as num?)?.toInt() ?? 0,
            bookName: row['book_name']?.toString() ?? 'Bible',
            chapter: (row['chapter'] as num?)?.toInt() ?? 1,
            verse: (row['verse'] as num?)?.toInt() ?? 1,
            html: row['html']?.toString() ?? '',
            text: row['plain_text']?.toString() ?? '',
          ),
        )
        .where((row) => row.blockId > 0)
        .toList(growable: false);
  }

  Future<int> loadOccurrenceCount(String strongsId) async {
    final canonical = normalizeStrongsCanonical(strongsId);
    if (canonical == null) return 0;
    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT block_id) AS verse_count
      FROM bible_tokens
      WHERE COALESCE(strongs_canonical, strongs_number, '') = ?
      ''',
      [canonical],
    );
    return (rows.firstOrNull?['verse_count'] as num?)?.toInt() ?? 0;
  }
}

String? normalizeStrongsCanonical(String? raw) {
  final value = raw?.trim().toUpperCase() ?? '';
  if (value.isEmpty) return null;

  final match = RegExp(r'^([GH])\s*0*(\d+)$').firstMatch(value);
  if (match == null) return null;

  final prefix = match.group(1)!;
  final digits = match.group(2)!;
  return '$prefix${digits.padLeft(4, '0')}';
}
