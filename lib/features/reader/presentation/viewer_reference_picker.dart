import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import 'viewer_book_group_colors.dart';
import 'viewer_book_label.dart';
import 'viewer_inline_number_grid.dart';

class ReferenceSelection {
  const ReferenceSelection({
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.verse,
  });

  final int bookNumber;
  final String bookName;
  final int chapter;
  final int verse;
}

Future<ReferenceSelection?> showViewerReferencePicker(
  BuildContext context, {
  required int initialBookNumber,
  required int initialChapter,
  required int initialVerse,
  bool largerPhoneControls = false,
  double fontScale = 1.3,
  ValueListenable<double>? fontScaleListenable,
}) {
  return showGeneralDialog<ReferenceSelection>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Choose passage',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _ViewerReferencePickerDialog(
          initialBookNumber: initialBookNumber,
          initialChapter: initialChapter,
          initialVerse: initialVerse,
          largerPhoneControls: largerPhoneControls,
          fontScale: fontScale,
          fontScaleListenable: fontScaleListenable,
        ),
  );
}

class _ViewerReferencePickerDialog extends StatefulWidget {
  const _ViewerReferencePickerDialog({
    required this.initialBookNumber,
    required this.initialChapter,
    required this.initialVerse,
    required this.largerPhoneControls,
    required this.fontScale,
    required this.fontScaleListenable,
  });

  final int initialBookNumber;
  final int initialChapter;
  final int initialVerse;
  final bool largerPhoneControls;
  final double fontScale;
  final ValueListenable<double>? fontScaleListenable;

  @override
  State<_ViewerReferencePickerDialog> createState() =>
      _ViewerReferencePickerDialogState();
}

class _ViewerReferencePickerDialogState
    extends State<_ViewerReferencePickerDialog> {
  final _db = StudyBibleDatabase.instance;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};

  List<BookRecord> _books = const [];
  List<int> _chapters = const [];
  List<int> _verses = const [];

  late int _bookNumber;
  late int _chapter;
  late int _verse;
  int? _expandedBookNumber;
  int? _expandedChapter;
  String _headerText = '';
  bool _loading = true;
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    _bookNumber = widget.initialBookNumber;
    _chapter = widget.initialChapter;
    _verse = widget.initialVerse;
    widget.fontScaleListenable?.addListener(_onFontScaleChanged);
    _load();
  }

  void _onFontScaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final books = await _db.loadBooks();
    final chapters = await _db.loadChapters(_bookNumber);
    final safeChapter = chapters.contains(_chapter)
        ? _chapter
        : (chapters.isEmpty ? 1 : chapters.first);
    final verses = await _db.loadVerses(
      bookNumber: _bookNumber,
      chapter: safeChapter,
    );
    final safeVerse = verses.contains(_verse)
        ? _verse
        : (verses.isEmpty ? 1 : verses.first);

    if (!mounted) return;
    setState(() {
      _books = books;
      _chapters = chapters;
      _verses = verses;
      _chapter = safeChapter;
      _verse = safeVerse;
      _loading = false;
    });
  }

  Future<void> _changeBook(int? value) async {
    if (value == null) return;
    setState(() {
      _loading = true;
      _bookNumber = value;
    });
    final chapters = await _db.loadChapters(value);
    final nextChapter = chapters.isEmpty ? 1 : chapters.first;
    final verses = await _db.loadVerses(
      bookNumber: value,
      chapter: nextChapter,
    );
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _chapter = nextChapter;
      _verses = verses;
      _verse = verses.isEmpty ? 1 : verses.first;
      _loading = false;
    });
  }

  Future<void> _changeChapter(int? value) async {
    if (value == null) return;
    setState(() {
      _loading = true;
      _chapter = value;
    });
    final verses = await _db.loadVerses(
      bookNumber: _bookNumber,
      chapter: value,
    );
    if (!mounted) return;
    setState(() {
      _verses = verses;
      _verse = verses.contains(_verse)
          ? _verse
          : (verses.isEmpty ? 1 : verses.first);
      _loading = false;
    });
  }

  void _submit() {
    final book = _books.firstWhere(
      (item) => item.bookNumber == _bookNumber,
      orElse: () => BookRecord(
        bookNumber: _bookNumber,
        bookName: 'Book $_bookNumber',
        bookIndex: _bookNumber,
      ),
    );
    Navigator.of(context).pop(
      ReferenceSelection(
        bookNumber: _bookNumber,
        bookName: book.bookName,
        chapter: _chapter,
        verse: _verse,
      ),
    );
  }

  List<BookRecord> get _oldTestamentBooks =>
      _books.where((book) => book.bookNumber <= 39).toList();

  @override
  void dispose() {
    widget.fontScaleListenable?.removeListener(_onFontScaleChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final fontScale = widget.fontScaleListenable?.value ?? widget.fontScale;
    // At the usual 1.3 reader scale the labels are 22.5 points. Changes to
    // the reader font setting remain visible across its full 0.8–2.4 range.
    final pickerFontSize = widget.largerPhoneControls
        ? 19 + (fontScale.clamp(0.8, 2.4) - 0.8) * 7
        : 14.0;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width < 700 ? size.width * 0.92 : 620,
                maxHeight: size.height * 0.8,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 14, 10),
                      child: Row(
                        children: [
                          const SizedBox(width: 40),
                          Expanded(
                            child: Text(
                              _headerText.isEmpty
                                  ? 'Select Book / Chapter / Verse'
                                  : _headerText,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                    Flexible(
                      child: _loading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _BookList(
                              scrollController: _scrollController,
                              books: _books,
                              rowKeys: _rowKeys,
                              expandedBookNumber: _expandedBookNumber,
                              expandedChapter: _expandedChapter,
                              currentVerse: _verse,
                              chapters: _chapters,
                              verses: _verses,
                              onInitialScroll: _scrollToCurrentBook,
                              onToggleBook: _selectBook,
                              onSelectChapter: _selectChapter,
                              onSelectVerse: _selectVerse,
                              largerPhoneControls: widget.largerPhoneControls,
                              pickerFontSize: pickerFontSize,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToCurrentBook() {
    if (_didInitialScroll) return;

    final targetIndex = _oldTestamentBooks.indexWhere(
      (book) => book.bookNumber == _bookNumber,
    );
    if (targetIndex < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowKey = _rowKeys[targetIndex];
      final rowContext = rowKey?.currentContext;
      if (rowContext == null) return;
      Scrollable.ensureVisible(
        rowContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0.0,
      );
      _didInitialScroll = true;
    });
  }

  void _selectBook(BookRecord book) {
    if (_expandedBookNumber == book.bookNumber) {
      setState(() {
        _expandedBookNumber = null;
        _expandedChapter = null;
        _headerText = '';
      });
      return;
    }

    setState(() {
      _expandedBookNumber = book.bookNumber;
      _expandedChapter = null;
      _headerText = book.bookName;
    });
    _changeBook(book.bookNumber);
  }

  void _selectChapter(int chapter) {
    setState(() {
      _expandedChapter = chapter;
      _headerText = '${_bookLabel(_bookNumber)} -> Chapter $chapter';
    });
    _changeChapter(chapter);
  }

  void _selectVerse(int verse) {
    setState(() {
      _verse = verse;
    });
    _submit();
  }

  String _bookLabel(int bookNumber) {
    final match = _books.where((book) => book.bookNumber == bookNumber);
    return match.isEmpty ? 'Book $bookNumber' : match.first.bookName;
  }
}

class _BookList extends StatelessWidget {
  const _BookList({
    required this.scrollController,
    required this.books,
    required this.rowKeys,
    required this.expandedBookNumber,
    required this.expandedChapter,
    required this.currentVerse,
    required this.chapters,
    required this.verses,
    required this.onInitialScroll,
    required this.onToggleBook,
    required this.onSelectChapter,
    required this.onSelectVerse,
    required this.largerPhoneControls,
    required this.pickerFontSize,
  });

  final ScrollController scrollController;
  final List<BookRecord> books;
  final Map<int, GlobalKey> rowKeys;
  final int? expandedBookNumber;
  final int? expandedChapter;
  final int currentVerse;
  final List<int> chapters;
  final List<int> verses;
  final VoidCallback onInitialScroll;
  final ValueChanged<BookRecord> onToggleBook;
  final ValueChanged<int> onSelectChapter;
  final ValueChanged<int> onSelectVerse;
  final bool largerPhoneControls;
  final double pickerFontSize;

  @override
  Widget build(BuildContext context) {
    final oldTestamentBooks = books
        .where((book) => book.bookNumber <= 39)
        .toList();
    final newTestamentBooks = books
        .where((book) => book.bookNumber > 39)
        .toList();

    onInitialScroll();

    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(overscroll: false),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          children: List.generate(oldTestamentBooks.length, (index) {
            final rowKey = rowKeys.putIfAbsent(index, () => GlobalKey());
            final leftBook = oldTestamentBooks[index];
            final rightBook = index < newTestamentBooks.length
                ? newTestamentBooks[index]
                : null;
            final leftExpanded = expandedBookNumber == leftBook.bookNumber;
            final rightExpanded =
                rightBook != null && expandedBookNumber == rightBook.bookNumber;

            return Column(
              key: rowKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ViewerBookLabel(
                          label: leftBook.bookName,
                          color: viewerBookGroupColor(leftBook.bookNumber),
                          selected: leftExpanded,
                          onTap: () => onToggleBook(leftBook),
                          fontSize: pickerFontSize,
                          minimumTapHeight: largerPhoneControls ? 48 : 0,
                          expandWidth: false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: rightBook == null
                          ? const SizedBox.shrink()
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: ViewerBookLabel(
                                label: rightBook.bookName,
                                color: viewerBookGroupColor(
                                  rightBook.bookNumber,
                                ),
                                selected: rightExpanded,
                                onTap: () => onToggleBook(rightBook),
                                fontSize: pickerFontSize,
                                minimumTapHeight: largerPhoneControls ? 48 : 0,
                                expandWidth: false,
                              ),
                            ),
                    ),
                  ],
                ),
                if (leftExpanded)
                  _ChapterAndVerseSelector(
                    key: ValueKey('left-${leftBook.bookNumber}'),
                    color: viewerBookGroupColor(leftBook.bookNumber),
                    chapters: chapters,
                    verses: verses,
                    expandedChapter: expandedChapter,
                    currentVerse: currentVerse,
                    onSelectChapter: onSelectChapter,
                    onSelectVerse: onSelectVerse,
                    largerPhoneControls: largerPhoneControls,
                    pickerFontSize: pickerFontSize,
                  ),
                if (rightExpanded)
                  _ChapterAndVerseSelector(
                    key: ValueKey('right-${rightBook.bookNumber}'),
                    color: viewerBookGroupColor(rightBook.bookNumber),
                    chapters: chapters,
                    verses: verses,
                    expandedChapter: expandedChapter,
                    currentVerse: currentVerse,
                    onSelectChapter: onSelectChapter,
                    onSelectVerse: onSelectVerse,
                    largerPhoneControls: largerPhoneControls,
                    pickerFontSize: pickerFontSize,
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _ChapterAndVerseSelector extends StatelessWidget {
  const _ChapterAndVerseSelector({
    super.key,
    required this.color,
    required this.chapters,
    required this.verses,
    required this.expandedChapter,
    required this.currentVerse,
    required this.onSelectChapter,
    required this.onSelectVerse,
    required this.largerPhoneControls,
    required this.pickerFontSize,
  });

  final Color color;
  final List<int> chapters;
  final List<int> verses;
  final int? expandedChapter;
  final int currentVerse;
  final ValueChanged<int> onSelectChapter;
  final ValueChanged<int> onSelectVerse;
  final bool largerPhoneControls;
  final double pickerFontSize;

  @override
  Widget build(BuildContext context) {
    if (expandedChapter == null) {
      return ViewerInlineNumberGrid(
        values: chapters,
        color: color,
        onSelect: onSelectChapter,
        fontSize: pickerFontSize,
        minimumItemExtent: largerPhoneControls ? 48 : 44,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ViewerInlineNumberGrid(
        values: verses,
        color: color,
        selectedValue: currentVerse,
        scrollToSelected: true,
        onSelect: onSelectVerse,
        fontSize: pickerFontSize,
        minimumItemExtent: largerPhoneControls ? 48 : 44,
      ),
    );
  }
}
