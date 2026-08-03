import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const openBibleDatasetName = 'OpenBible.info Bible Cross References';
const openBibleSourceUrl = 'https://www.openbible.info/labs/cross-references/';
const openBibleLicense = 'Creative Commons Attribution 4.0 International';
const openBibleLicenseUrl = 'https://creativecommons.org/licenses/by/4.0/';
const openBibleAttribution =
    'Cross-reference data derived from the OpenBible.info Bible Cross References dataset, licensed under Creative Commons Attribution.';

class CanonicalVerse {
  const CanonicalVerse({
    required this.id,
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.verse,
  });

  final int id;
  final int bookNumber;
  final String bookName;
  final int chapter;
  final int verse;

  String get reference => '$bookName $chapter:$verse';
}

class ParsedReference {
  const ParsedReference(this.start, this.end);

  final CanonicalVerse start;
  final CanonicalVerse end;
}

class ImportSummary {
  const ImportSummary({
    required this.rawRows,
    required this.importedRows,
    required this.rejectedRows,
    required this.duplicatesRemoved,
    required this.expandedRelationships,
  });

  final int rawRows;
  final int importedRows;
  final int rejectedRows;
  final int duplicatesRemoved;
  final int expandedRelationships;
}

class CrossReferenceImporter {
  CrossReferenceImporter._(this._versesById, this._versesByKey);

  final Map<int, CanonicalVerse> _versesById;
  final Map<String, CanonicalVerse> _versesByKey;

  static const Map<String, int> _osisBookNumbers = {
    'Gen': 1,
    'Exod': 2,
    'Lev': 3,
    'Num': 4,
    'Deut': 5,
    'Josh': 6,
    'Judg': 7,
    'Ruth': 8,
    '1Sam': 9,
    '2Sam': 10,
    '1Kgs': 11,
    '2Kgs': 12,
    '1Chr': 13,
    '2Chr': 14,
    'Ezra': 15,
    'Neh': 16,
    'Esth': 17,
    'Job': 18,
    'Ps': 19,
    'Prov': 20,
    'Eccl': 21,
    'Song': 22,
    'Isa': 23,
    'Jer': 24,
    'Lam': 25,
    'Ezek': 26,
    'Dan': 27,
    'Hos': 28,
    'Joel': 29,
    'Amos': 30,
    'Obad': 31,
    'Jonah': 32,
    'Mic': 33,
    'Nah': 34,
    'Hab': 35,
    'Zeph': 36,
    'Hag': 37,
    'Zech': 38,
    'Mal': 39,
    'Matt': 40,
    'Mark': 41,
    'Luke': 42,
    'John': 43,
    'Acts': 44,
    'Rom': 45,
    '1Cor': 46,
    '2Cor': 47,
    'Gal': 48,
    'Eph': 49,
    'Phil': 50,
    'Col': 51,
    '1Thess': 52,
    '2Thess': 53,
    '1Tim': 54,
    '2Tim': 55,
    'Titus': 56,
    'Phlm': 57,
    'Heb': 58,
    'Jas': 59,
    '1Pet': 60,
    '2Pet': 61,
    '1John': 62,
    '2John': 63,
    '3John': 64,
    'Jude': 65,
    'Rev': 66,
  };

  static final Map<String, int> _bookAliases = _buildAliases();

  static Map<String, int> _buildAliases() {
    final aliases = <String, int>{};
    void add(String value, int number) {
      aliases[_normalizeBook(value)] = number;
    }

    for (final entry in _osisBookNumbers.entries) {
      add(entry.key, entry.value);
    }
    const names = [
      'Genesis',
      'Exodus',
      'Leviticus',
      'Numbers',
      'Deuteronomy',
      'Joshua',
      'Judges',
      'Ruth',
      '1 Samuel',
      '2 Samuel',
      '1 Kings',
      '2 Kings',
      '1 Chronicles',
      '2 Chronicles',
      'Ezra',
      'Nehemiah',
      'Esther',
      'Job',
      'Psalms',
      'Proverbs',
      'Ecclesiastes',
      'Song of Solomon',
      'Isaiah',
      'Jeremiah',
      'Lamentations',
      'Ezekiel',
      'Daniel',
      'Hosea',
      'Joel',
      'Amos',
      'Obadiah',
      'Jonah',
      'Micah',
      'Nahum',
      'Habakkuk',
      'Zephaniah',
      'Haggai',
      'Zechariah',
      'Malachi',
      'Matthew',
      'Mark',
      'Luke',
      'John',
      'Acts',
      'Romans',
      '1 Corinthians',
      '2 Corinthians',
      'Galatians',
      'Ephesians',
      'Philippians',
      'Colossians',
      '1 Thessalonians',
      '2 Thessalonians',
      '1 Timothy',
      '2 Timothy',
      'Titus',
      'Philemon',
      'Hebrews',
      'James',
      '1 Peter',
      '2 Peter',
      '1 John',
      '2 John',
      '3 John',
      'Jude',
      'Revelation',
    ];
    for (var index = 0; index < names.length; index++) {
      add(names[index], index + 1);
    }
    add('Psalm', 19);
    add('Psa', 19);
    add('Canticles', 22);
    add('Song of Songs', 22);
    add('Jn', 43);
    add('Mk', 41);
    add('Lk', 42);
    add('Ro', 45);
    add('Re', 66);
    return aliases;
  }

  static String _normalizeBook(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .replaceFirst(RegExp(r'^iii(?=[a-z])'), '3')
      .replaceFirst(RegExp(r'^ii(?=[a-z])'), '2')
      .replaceFirst(RegExp(r'^i(?=[a-z])'), '1');

  static Future<CrossReferenceImporter> fromBibleDatabase(
    String bibleDatabasePath,
  ) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      p.absolute(bibleDatabasePath),
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final rows = await db.rawQuery('''
        SELECT b.id, b.book_number, k.book_name, b.chapter,
               b.block_index AS verse
        FROM bible_blocks b
        JOIN books k ON k.book_number = b.book_number
        ORDER BY b.id
      ''');
      final byId = <int, CanonicalVerse>{};
      final byKey = <String, CanonicalVerse>{};
      for (final row in rows) {
        final value = CanonicalVerse(
          id: row['id'] as int,
          bookNumber: row['book_number'] as int,
          bookName: row['book_name'] as String,
          chapter: row['chapter'] as int,
          verse: row['verse'] as int,
        );
        byId[value.id] = value;
        byKey[_key(value.bookNumber, value.chapter, value.verse)] = value;
      }
      if (byId.isEmpty) throw StateError('Bible database contains no verses.');
      return CrossReferenceImporter._(byId, byKey);
    } finally {
      await db.close();
    }
  }

  ParsedReference parseReference(String input) {
    final parts = input.trim().split('-');
    if (parts.isEmpty || parts.length > 2) {
      throw FormatException('Invalid reference range', input);
    }
    final start = _parseEndpoint(parts.first);
    final end = parts.length == 2 ? _parseEndpoint(parts.last) : start;
    if (end.id < start.id) throw FormatException('Reversed range', input);
    return ParsedReference(start, end);
  }

  CanonicalVerse _parseEndpoint(String input) {
    final osis = RegExp(r'^([1-3]?[A-Za-z]+)\.(\d+)\.(\d+)$').firstMatch(input);
    final human = RegExp(r'^(.+?)\s+(\d+):(\d+)$').firstMatch(input);
    final match = osis ?? human;
    if (match == null) throw FormatException('Invalid verse reference', input);
    final number = _bookAliases[_normalizeBook(match.group(1)!)];
    final chapter = int.tryParse(match.group(2)!);
    final verse = int.tryParse(match.group(3)!);
    if (number == null || chapter == null || verse == null) {
      throw FormatException('Unknown verse reference', input);
    }
    final canonical = _versesByKey[_key(number, chapter, verse)];
    if (canonical == null) throw FormatException('Verse does not exist', input);
    return canonical;
  }

  List<CanonicalVerse> expand(ParsedReference reference) {
    final result = <CanonicalVerse>[];
    for (var id = reference.start.id; id <= reference.end.id; id++) {
      final verse = _versesById[id];
      if (verse == null) {
        throw StateError('Non-contiguous canonical IDs at $id');
      }
      result.add(verse);
    }
    return result;
  }

  Future<ImportSummary> build({
    required String sourcePath,
    required String outputPath,
    required Map<String, String> metadata,
  }) async {
    final pairs = <(int, int), _Relationship>{};
    var rawRows = 0;
    var rejectedRows = 0;
    var expandedRelationships = 0;
    var duplicateRows = 0;
    final lines = File(
      p.absolute(sourcePath),
    ).openRead().transform(utf8.decoder).transform(const LineSplitter());
    var lineNumber = 0;
    await for (final line in lines) {
      lineNumber++;
      if (lineNumber == 1) {
        if (!line.startsWith('From Verse\tTo Verse\tVotes\t#')) {
          throw FormatException('Unexpected OpenBible header', line);
        }
        continue;
      }
      if (line.trim().isEmpty) continue;
      rawRows++;
      final columns = line.split('\t');
      if (columns.length != 3) {
        rejectedRows++;
        continue;
      }
      try {
        final source = parseReference(columns[0]);
        if (source.start.id != source.end.id) {
          throw const FormatException('Source must be a single verse');
        }
        final target = parseReference(columns[1]);
        final score = int.parse(columns[2]);
        final targets = expand(target);
        expandedRelationships += targets.length;
        for (final targetVerse in targets) {
          final key = (source.start.id, targetVerse.id);
          final candidate = _Relationship(
            sourceId: source.start.id,
            targetId: targetVerse.id,
            score: score,
            sourceReference: source.start.reference,
            targetReference: targetVerse.reference,
          );
          final existing = pairs[key];
          if (existing != null) {
            duplicateRows++;
            if (score > existing.score) pairs[key] = candidate;
          } else {
            pairs[key] = candidate;
          }
        }
      } on FormatException {
        rejectedRows++;
      }
    }

    final sorted = pairs.values.toList()
      ..sort((a, b) {
        final source = a.sourceId.compareTo(b.sourceId);
        return source != 0 ? source : a.targetId.compareTo(b.targetId);
      });
    outputPath = p.absolute(outputPath);
    final temporaryPath = '$outputPath.tmp';
    final temporary = File(temporaryPath);
    if (temporary.existsSync()) temporary.deleteSync();
    Directory(p.dirname(outputPath)).createSync(recursive: true);
    final db = await databaseFactoryFfi.openDatabase(
      temporaryPath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await db.execute('PRAGMA journal_mode = DELETE');
      await db.execute('PRAGMA synchronous = FULL');
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          ) WITHOUT ROWID
        ''');
        await txn.execute('''
          CREATE TABLE cross_references (
            source_verse_id INTEGER NOT NULL,
            target_verse_id INTEGER NOT NULL,
            score INTEGER NOT NULL DEFAULT 0,
            source_reference TEXT,
            target_reference TEXT,
            PRIMARY KEY (source_verse_id, target_verse_id)
          ) WITHOUT ROWID
        ''');
        await txn.execute('''
          CREATE INDEX idx_cross_references_source_score
          ON cross_references(source_verse_id, score DESC, target_verse_id)
        ''');
        final allMetadata = <String, String>{
          ...metadata,
          'dataset_name': openBibleDatasetName,
          'source_url': openBibleSourceUrl,
          'license': openBibleLicense,
          'license_url': openBibleLicenseUrl,
          'attribution': openBibleAttribution,
          'raw_row_count': '$rawRows',
          'imported_row_count': '${sorted.length}',
          'rejected_row_count': '$rejectedRows',
          'duplicate_relationship_count': '$duplicateRows',
          'database_schema_version': '1',
        };
        final metadataBatch = txn.batch();
        for (final entry
            in allMetadata.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))) {
          metadataBatch.insert('metadata', {
            'key': entry.key,
            'value': entry.value,
          });
        }
        await metadataBatch.commit(noResult: true);
        const chunkSize = 5000;
        for (var start = 0; start < sorted.length; start += chunkSize) {
          final batch = txn.batch();
          final end = (start + chunkSize).clamp(0, sorted.length);
          for (final row in sorted.sublist(start, end)) {
            batch.insert('cross_references', row.toMap());
          }
          await batch.commit(noResult: true);
        }
      });
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.single.values.single != 'ok') {
        throw StateError('SQLite integrity check failed: $integrity');
      }
      final invalid = await db.rawQuery(
        '''
        SELECT COUNT(*) AS count FROM cross_references
        WHERE source_verse_id NOT BETWEEN ? AND ?
           OR target_verse_id NOT BETWEEN ? AND ?
      ''',
        [
          _versesById.keys.first,
          _versesById.keys.last,
          _versesById.keys.first,
          _versesById.keys.last,
        ],
      );
      if ((invalid.single['count'] as int) != 0) {
        throw StateError('Database contains non-canonical verse IDs.');
      }
    } catch (_) {
      await db.close();
      if (temporary.existsSync()) temporary.deleteSync();
      rethrow;
    }
    await db.close();
    final output = File(outputPath);
    if (output.existsSync()) output.deleteSync();
    temporary.renameSync(outputPath);
    return ImportSummary(
      rawRows: rawRows,
      importedRows: sorted.length,
      rejectedRows: rejectedRows,
      duplicatesRemoved: duplicateRows,
      expandedRelationships: expandedRelationships,
    );
  }

  static String _key(int book, int chapter, int verse) =>
      '$book.$chapter.$verse';
}

class _Relationship {
  const _Relationship({
    required this.sourceId,
    required this.targetId,
    required this.score,
    required this.sourceReference,
    required this.targetReference,
  });

  final int sourceId;
  final int targetId;
  final int score;
  final String sourceReference;
  final String targetReference;

  Map<String, Object?> toMap() => {
    'source_verse_id': sourceId,
    'target_verse_id': targetId,
    'score': score,
    'source_reference': sourceReference,
    'target_reference': targetReference,
  };
}
