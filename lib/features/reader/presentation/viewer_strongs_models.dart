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

class ViewerLexiconPart {
  const ViewerLexiconPart(this.text, {this.blockId});

  final String text;
  final int? blockId;
}

class ViewerLexiconSense {
  const ViewerLexiconSense({required this.number, required this.parts});

  final String number;
  final List<ViewerLexiconPart> parts;
}

class ViewerAbbottSmithEntry {
  const ViewerAbbottSmithEntry({required this.senses, required this.related});

  final List<ViewerLexiconSense> senses;
  final List<List<ViewerLexiconPart>> related;
}

class ViewerBdbEntry {
  const ViewerBdbEntry({required this.text, required this.articleId});

  final String text;
  final String articleId;
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
