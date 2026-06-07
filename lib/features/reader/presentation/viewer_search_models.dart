import '../../../core/database/study_bible_database.dart';

class BibleSearchSession {
  const BibleSearchSession({
    required this.query,
    required this.section,
    required this.bookNumber,
    required this.lookupByHighlight,
    required this.highlightGroupId,
    required this.results,
    required this.currentIndex,
    required this.totalResultCount,
  });

  final String query;
  final String section;
  final int? bookNumber;
  final bool lookupByHighlight;
  final int? highlightGroupId;
  final List<PassageSearchResult> results;
  final int currentIndex;
  final int totalResultCount;

  PassageSearchResult get currentResult => results[currentIndex];

  String get counterLabel => '${currentIndex + 1} / $totalResultCount';

  bool get hasPrevious => currentIndex > 0;

  bool get hasNext => currentIndex < results.length - 1;

  BibleSearchSession copyWithIndex(int index) {
    if (results.isEmpty) return this;
    return BibleSearchSession(
      query: query,
      section: section,
      bookNumber: bookNumber,
      lookupByHighlight: lookupByHighlight,
      highlightGroupId: highlightGroupId,
      results: results,
      currentIndex: index.clamp(0, results.length - 1),
      totalResultCount: totalResultCount,
    );
  }
}

class ViewerSearchSelection {
  const ViewerSearchSelection({
    required this.blockId,
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.lastSearchTerm,
    this.bibleSearchSession,
  });

  final int blockId;
  final int bookNumber;
  final int chapter;
  final int verse;
  final String lastSearchTerm;
  final BibleSearchSession? bibleSearchSession;
}
