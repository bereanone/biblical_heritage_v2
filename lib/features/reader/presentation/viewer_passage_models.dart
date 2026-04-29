class PassageData {
  const PassageData({
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.lines,
  });

  final int? bookNumber;
  final String bookName;
  final int chapter;
  final List<VerseLine> lines;
}

class VerseLine {
  const VerseLine({
    required this.blockId,
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.html,
    required this.text,
  });

  final int? blockId;
  final int bookNumber;
  final int chapter;
  final int verse;
  final String html;
  final String text;
}
