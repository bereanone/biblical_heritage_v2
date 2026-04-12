import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import 'viewer_search_query.dart';

class ViewerSearchSectionOption {
  const ViewerSearchSectionOption({
    required this.value,
    required this.label,
    this.indentLevel = 0,
    this.color,
    this.bookNumber,
  });

  final String value;
  final String label;
  final int indentLevel;
  final Color? color;
  final int? bookNumber;
}

class ViewerSearchBookOption {
  const ViewerSearchBookOption({
    required this.bookNumber,
    required this.label,
  });

  final int? bookNumber;
  final String label;
}

class ViewerSearchBookFilterResult {
  const ViewerSearchBookFilterResult(this.bookNumber);

  final int? bookNumber;
}

const viewerSearchSectionOptions = <ViewerSearchSectionOption>[
  ViewerSearchSectionOption(value: 'All', label: 'All'),
  ViewerSearchSectionOption(
    value: 'Old Testament',
    label: 'Old Testament',
    color: Color(0xFFE6D7B8),
  ),
  ViewerSearchSectionOption(
    value: 'Pentateuch',
    label: 'Pentateuch',
    indentLevel: 1,
    bookNumber: 1,
  ),
  ViewerSearchSectionOption(
    value: 'History',
    label: 'History',
    indentLevel: 1,
    bookNumber: 6,
  ),
  ViewerSearchSectionOption(
    value: 'Poetry',
    label: 'Poetry',
    indentLevel: 1,
    bookNumber: 18,
  ),
  ViewerSearchSectionOption(
    value: 'Major Prophets',
    label: 'Major Prophets',
    indentLevel: 1,
    bookNumber: 23,
  ),
  ViewerSearchSectionOption(
    value: 'Minor Prophets',
    label: 'Minor Prophets',
    indentLevel: 1,
    bookNumber: 28,
  ),
  ViewerSearchSectionOption(
    value: 'New Testament',
    label: 'New Testament',
    color: Color(0xFFE6D7B8),
  ),
  ViewerSearchSectionOption(
    value: 'Gospels',
    label: 'Gospels',
    indentLevel: 1,
    bookNumber: 40,
  ),
  ViewerSearchSectionOption(
    value: 'Acts',
    label: 'Acts',
    indentLevel: 1,
    bookNumber: 44,
  ),
  ViewerSearchSectionOption(
    value: 'Pauline Epistles',
    label: 'Pauline Epistles',
    indentLevel: 1,
    bookNumber: 45,
  ),
  ViewerSearchSectionOption(
    value: 'General Epistles',
    label: 'General Epistles',
    indentLevel: 1,
    bookNumber: 58,
  ),
  ViewerSearchSectionOption(
    value: 'Revelation',
    label: 'Revelation',
    indentLevel: 1,
    bookNumber: 66,
  ),
];

List<ViewerSearchBookOption> buildViewerSearchBookOptions(
  List<BookRecord> books,
  String selectedSection,
) {
  final range = viewerSectionBookRange(selectedSection);
  final filteredBooks = range == null
      ? books
      : books
          .where(
            (book) =>
                book.bookNumber >= range.$1 && book.bookNumber <= range.$2,
          )
          .toList(growable: false);

  return <ViewerSearchBookOption>[
    const ViewerSearchBookOption(bookNumber: null, label: 'Books'),
    ...filteredBooks.map(
      (book) => ViewerSearchBookOption(
        bookNumber: book.bookNumber,
        label: book.bookName,
      ),
    ),
  ];
}
