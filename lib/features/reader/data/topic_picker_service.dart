import '../../../core/database/study_bible_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TopicSection {
  const TopicSection({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.minBlockId,
    required this.maxBlockId,
  });

  final int id;
  final String name;
  final String colorHex;
  final int minBlockId;
  final int maxBlockId;
}

class TopicEntry {
  const TopicEntry({
    required this.id,
    required this.label,
    required this.blockId,
    required this.bookNumber,
  });

  final int id;
  final String label;
  final int blockId;
  final int bookNumber;
}

class TopicPickerData {
  const TopicPickerData({
    required this.sections,
    required this.books,
    required this.topics,
  });

  final List<TopicSection> sections;
  final List<BookRecord> books;
  final List<TopicEntry> topics;
}

class TopicPickerService {
  TopicPickerService._();

  static final TopicPickerService instance = TopicPickerService._();

  Future<TopicPickerData> load() async {
    final db = await StudyBibleDatabase.instance.bible;
    List<Map<String, Object?>> sectionRows;
    List<Map<String, Object?>> topicRows;
    try {
      sectionRows = await db.rawQuery(
        '''
        SELECT section_id, section_name, color_hex, min_block_id, max_block_id
        FROM bible_sections
        ORDER BY section_id
        ''',
      );
      topicRows = await db.rawQuery(
        '''
        SELECT sh.id, sh.heading AS label, sh.block_id, b.book_number
        FROM section_headings sh
        JOIN bible_blocks b ON b.id = sh.block_id
        WHERE sh.block_id IS NOT NULL
        ORDER BY sh.block_id
        ''',
      );
    } on DatabaseException catch (error) {
      if (error.toString().contains('no such table: bible_sections') ||
          error.toString().contains('no such table: section_headings')) {
        return TopicPickerData(
          sections: const <TopicSection>[],
          books: await StudyBibleDatabase.instance.loadBooks(),
          topics: const <TopicEntry>[],
        );
      }
      rethrow;
    }

    final sections = sectionRows
        .map(
          (row) => TopicSection(
            id: (row['section_id'] as num?)?.toInt() ?? 0,
            name: (row['section_name'] ?? '').toString(),
            colorHex: (row['color_hex'] ?? '').toString(),
            minBlockId: (row['min_block_id'] as num?)?.toInt() ?? 0,
            maxBlockId: (row['max_block_id'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((section) => section.id > 0)
        .toList(growable: false);

    final topics = topicRows
        .map(
          (row) => TopicEntry(
            id: (row['id'] as num?)?.toInt() ?? 0,
            label: (row['label'] ?? '').toString(),
            blockId: (row['block_id'] as num?)?.toInt() ?? 0,
            bookNumber: (row['book_number'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((topic) => topic.id > 0 && topic.blockId > 0)
        .toList(growable: false);

    final books = await StudyBibleDatabase.instance.loadBooks();

    return TopicPickerData(
      sections: sections,
      books: books,
      topics: topics,
    );
  }
}
