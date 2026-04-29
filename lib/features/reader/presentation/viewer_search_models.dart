class ViewerSearchSelection {
  const ViewerSearchSelection({
    required this.blockId,
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.lastSearchTerm,
  });

  final int blockId;
  final int bookNumber;
  final int chapter;
  final int verse;
  final String lastSearchTerm;
}
