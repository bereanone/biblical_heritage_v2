import 'dart:convert';

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

  bool get hasPrevious => results.isNotEmpty && currentIndex > 0;

  bool get hasNext =>
      results.isNotEmpty && currentIndex < results.length - 1;

  BibleSearchSession copyWithIndex(int index) {
    if (results.isEmpty || index < 0 || index >= results.length) {
      return this;
    }
    return BibleSearchSession(
      query: query,
      section: section,
      bookNumber: bookNumber,
      lookupByHighlight: lookupByHighlight,
      highlightGroupId: highlightGroupId,
      results: results,
      currentIndex: index,
      totalResultCount: totalResultCount,
    );
  }
}

class BibleSearchSessionSnapshot {
  const BibleSearchSessionSnapshot({
    required this.query,
    required this.section,
    required this.lookupByHighlight,
    required this.totalResultCount,
    this.bookNumber,
    this.highlightGroupId,
    this.currentIndex,
  });

  final String query;
  final String section;
  final int? bookNumber;
  final bool lookupByHighlight;
  final int? highlightGroupId;
  final int? currentIndex;
  final int totalResultCount;

  bool get hasCurrentIndex => currentIndex != null && totalResultCount > 0;

  String get counterLabel {
    if (!hasCurrentIndex) {
      return totalResultCount > 0 ? '$totalResultCount' : '0';
    }
    return '${currentIndex! + 1} / $totalResultCount';
  }

  bool get hasPrevious => hasCurrentIndex && currentIndex! > 0;

  bool get hasNext => hasCurrentIndex && currentIndex! < totalResultCount - 1;

  BibleSearchSessionSnapshot copyWithIndex(int index) {
    final clamped = totalResultCount <= 0
        ? null
        : index.clamp(0, totalResultCount - 1).toInt();
    return BibleSearchSessionSnapshot(
      query: query,
      section: section,
      bookNumber: bookNumber,
      lookupByHighlight: lookupByHighlight,
      highlightGroupId: highlightGroupId,
      currentIndex: clamped,
      totalResultCount: totalResultCount,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'query': query,
      'section': section,
      if (bookNumber != null) 'bookNumber': bookNumber,
      'lookupByHighlight': lookupByHighlight,
      if (highlightGroupId != null) 'highlightGroupId': highlightGroupId,
      if (currentIndex != null) 'currentIndex': currentIndex,
      'totalResultCount': totalResultCount,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static BibleSearchSessionSnapshot? fromJsonString(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final query = decoded['query']?.toString().trim() ?? '';
      final section = decoded['section']?.toString().trim() ?? 'All';
      final bookNumber = (decoded['bookNumber'] as num?)?.toInt();
      final lookupByHighlight =
          decoded['lookupByHighlight'] == true ||
          decoded['lookupByHighlight']?.toString() == 'true';
      final highlightGroupId = (decoded['highlightGroupId'] as num?)?.toInt();
      final currentIndex = (decoded['currentIndex'] as num?)?.toInt();
      final totalResultCount = (decoded['totalResultCount'] as num?)?.toInt() ?? 0;
      if (query.isEmpty &&
          section.isEmpty &&
          bookNumber == null &&
          !lookupByHighlight &&
          highlightGroupId == null &&
          currentIndex == null &&
          totalResultCount <= 0) {
        return null;
      }
      return BibleSearchSessionSnapshot(
        query: query,
        section: section.isEmpty ? 'All' : section,
        bookNumber: bookNumber,
        lookupByHighlight: lookupByHighlight,
        highlightGroupId: highlightGroupId,
        currentIndex: currentIndex,
        totalResultCount: totalResultCount,
      );
    } catch (_) {
      return null;
    }
  }

  static BibleSearchSessionSnapshot fromSession(BibleSearchSession session) {
    return BibleSearchSessionSnapshot(
      query: session.query,
      section: session.section,
      bookNumber: session.bookNumber,
      lookupByHighlight: session.lookupByHighlight,
      highlightGroupId: session.highlightGroupId,
      currentIndex: session.currentIndex,
      totalResultCount: session.totalResultCount,
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
