/// Recognizes the readable note headings produced by study-list export.
bool isSharedNoteHeading(String line) => RegExp(r'^(?:[#\$@])?[A-Za-z0-9 _-]+ Note \d+$',caseSensitive:false).hasMatch(line.trim());

/// Keep explicitly headed notes together, including blank-separated paragraphs.
/// Preserve blank-line boundaries for unlabelled legacy/eLibrary cards.
List<List<String>> splitSharedListTextBlocks(List<String> lines, {
  required bool Function(String) isWrapper,
  required bool Function(String) isListHeader,
  required bool Function(String) isSlideStart,
}) {
  final blocks=<List<String>>[];
  var current=<String>[];
  var sawHeader=false;
  void flush() {
    while(current.isNotEmpty && current.last.trim().isEmpty) {current.removeLast();}
    if(current.isNotEmpty) blocks.add(current);
    current=<String>[];
  }
  for(final raw in lines) {
    final line=raw.replaceAll('\r','');final value=line.trim();
    if(isListHeader(value)) {flush();sawHeader=true;continue;}
    final approvedInstructions=RegExp(r'^For instructions on using the app, visit BiblicalHeritage\.net\.?$',caseSensitive:false).hasMatch(value);
    if((!sawHeader && current.isEmpty && approvedInstructions) || (current.isEmpty && value.isNotEmpty && isWrapper(value))) continue;
    if(value.isEmpty) {
      if(current.isNotEmpty && isSharedNoteHeading(current.first)) {
        current.add('');
      } else {flush();}
      continue;
    }
    if(current.isNotEmpty && (isSlideStart(value) || isSharedNoteHeading(value))) flush();
    current.add(line);
  }
  flush();return blocks;
}
