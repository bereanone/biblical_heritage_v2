import '../../../core/database/user_database.dart';

class MemoryVerse {
  const MemoryVerse({
    required this.id,
    required this.verseRef,
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.endChapter,
    required this.endVerse,
    required this.verseText,
    required this.reviewStep,
    required this.nextDueAt,
    required this.totalReviews,
    required this.totalMisses,
    this.groupName,
    this.lastResult,
  });

  final int id;
  final String verseRef;
  final int bookNumber;
  final String bookName;
  final int chapter;
  final int verse;
  final int endChapter;
  final int endVerse;
  final String verseText;
  final int reviewStep;
  final int nextDueAt;
  final int totalReviews;
  final int totalMisses;
  final String? groupName;
  final String? lastResult;

  String get reference =>
      verseRef.trim().isNotEmpty ? verseRef : '$bookName $chapter:$verse';

  bool get isRange => chapter != endChapter || verse != endVerse;

  String get rangeBadge {
    if (!isRange) return '$chapter:$verse';
    if (chapter == endChapter) return '$chapter:+';
    return '$chapter-$endChapter';
  }

  factory MemoryVerse.fromMap(Map<String, Object?> map) {
    int readInt(String key, {int fallback = 0}) {
      final value = map[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    final chapter = readInt('chapter', fallback: 1);
    final verse = readInt('verse', fallback: 1);
    return MemoryVerse(
      id: readInt('id'),
      verseRef: map['verse_ref']?.toString() ?? '',
      bookNumber: readInt('book_number', fallback: 1),
      bookName: map['book_name']?.toString() ?? '',
      chapter: chapter,
      verse: verse,
      endChapter: readInt('end_chapter', fallback: chapter),
      endVerse: readInt('end_verse', fallback: verse),
      verseText: map['verse_text']?.toString() ?? '',
      reviewStep: readInt('review_step'),
      nextDueAt: readInt('next_due_at'),
      totalReviews: readInt('total_reviews'),
      totalMisses: readInt('total_misses'),
      groupName: map['group_name']?.toString(),
      lastResult: map['last_result']?.toString(),
    );
  }
}

class BibleMemoryRepository {
  static const List<int> _cadenceDays = <int>[1, 7, 30, 90, 180, 365];
  static const List<String> _cadenceLabels = <String>[
    'Learning',
    'Daily',
    'Weekly',
    'Monthly',
    'Quarterly',
    'Every 6 months',
    'Yearly',
  ];

  Future<List<MemoryVerse>> loadAll() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'memory_verses',
      orderBy: 'next_due_at ASC, book_number ASC, chapter ASC, verse ASC',
    );
    return rows.map(MemoryVerse.fromMap).toList(growable: false);
  }

  Future<MemoryVerse> upsertVerse({
    required int bookNumber,
    required String bookName,
    required int chapter,
    required int verse,
    required String verseText,
    String? groupName,
  }) async {
    return upsertPassage(
      bookNumber: bookNumber,
      bookName: bookName,
      chapter: chapter,
      verse: verse,
      endChapter: chapter,
      endVerse: verse,
      verseText: verseText,
      groupName: groupName,
    );
  }

  String _formatPassageRef({
    required String bookName,
    required int chapter,
    required int verse,
    required int endChapter,
    required int endVerse,
  }) {
    if (chapter == endChapter && verse == endVerse) {
      return '$bookName $chapter:$verse';
    }
    if (chapter == endChapter) {
      return '$bookName $chapter:$verse-$endVerse';
    }
    return '$bookName $chapter:$verse-$endChapter:$endVerse';
  }

  Future<MemoryVerse> upsertPassage({
    required int bookNumber,
    required String bookName,
    required int chapter,
    required int verse,
    required int endChapter,
    required int endVerse,
    required String verseText,
    String? groupName,
  }) async {
    final db = await UserDatabase.instance.database;
    final verseRef = _formatPassageRef(
      bookName: bookName,
      chapter: chapter,
      verse: verse,
      endChapter: endChapter,
      endVerse: endVerse,
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await db.query(
      'memory_verses',
      where: 'verse_ref = ?',
      whereArgs: [verseRef],
      limit: 1,
    );

    if (existing.isEmpty) {
      final id = await db.insert('memory_verses', {
        'verse_ref': verseRef,
        'book_number': bookNumber,
        'book_name': bookName,
        'chapter': chapter,
        'verse': verse,
        'end_chapter': endChapter,
        'end_verse': endVerse,
        'verse_text': verseText,
        'group_name': groupName,
        'review_step': 0,
        'next_due_at': now,
        'last_result': null,
        'total_reviews': 0,
        'total_misses': 0,
        'created_at': now,
        'updated_at': now,
      });
      final inserted = await db.query(
        'memory_verses',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return MemoryVerse.fromMap(inserted.first);
    }

    final current = MemoryVerse.fromMap(existing.first);
    await db.update(
      'memory_verses',
      {
        'book_number': bookNumber,
        'book_name': bookName,
        'chapter': chapter,
        'verse': verse,
        'end_chapter': endChapter,
        'end_verse': endVerse,
        'verse_text': verseText,
        'group_name': groupName,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [current.id],
    );
    final updated = await db.query(
      'memory_verses',
      where: 'id = ?',
      whereArgs: [current.id],
      limit: 1,
    );
    return MemoryVerse.fromMap(updated.first);
  }

  Future<void> deleteVerse(int id) async {
    final db = await UserDatabase.instance.database;
    await db.delete('memory_verses', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markReviewCompleted({
    required MemoryVerse verse,
    required bool passed,
    required int totalStrikes,
  }) async {
    final db = await UserDatabase.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextStep = passed
        ? (verse.reviewStep + 1).clamp(1, _cadenceDays.length).toInt()
        : verse.reviewStep;
    final days = passed
        ? _cadenceDays[(nextStep - 1).clamp(0, _cadenceDays.length - 1)]
        : 1;
    final nextDue = DateTime.now().add(Duration(days: days));

    await db.update(
      'memory_verses',
      {
        'review_step': nextStep,
        'next_due_at': nextDue.millisecondsSinceEpoch,
        'last_result': passed ? 'pass' : 'retry',
        'total_reviews': verse.totalReviews + 1,
        'total_misses': verse.totalMisses + totalStrikes,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [verse.id],
    );
  }

  String cadenceLabelForStep(int step) {
    if (step < 0) return _cadenceLabels.first;
    if (step >= _cadenceLabels.length) return _cadenceLabels.last;
    return _cadenceLabels[step];
  }
}
