const String libraryMediaFilterAll = 'all';
const Set<String> libraryMediaFilterValues = <String>{'all', 'ePubs', 'PDFs'};

String normalizeLibraryMediaFilter(String? savedValue) {
  final normalized = savedValue?.trim().toLowerCase();
  return switch (normalized) {
    'epubs' => 'ePubs',
    'pdfs' => 'PDFs',
    'all' => libraryMediaFilterAll,
    _ => libraryMediaFilterAll,
  };
}
