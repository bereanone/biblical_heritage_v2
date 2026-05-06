class ViewerStrongsEntry {
  const ViewerStrongsEntry({
    required this.strongsId,
    required this.language,
    required this.lemma,
    required this.transliteration,
    required this.pronunciation,
    required this.partOfSpeech,
    required this.shortDefinition,
  });

  final String strongsId;
  final String language;
  final String lemma;
  final String transliteration;
  final String pronunciation;
  final String partOfSpeech;
  final String shortDefinition;
}

class ViewerStrongsOccurrence {
  const ViewerStrongsOccurrence({
    required this.blockId,
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.html,
    required this.text,
  });

  final int blockId;
  final int bookNumber;
  final String bookName;
  final int chapter;
  final int verse;
  final String html;
  final String text;

  String get reference => '$bookName $chapter:$verse';
}
