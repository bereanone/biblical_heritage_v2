import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';

LibraryCatalogItem _catalogItem({
  required String id,
  required String title,
  required String fileName,
  required String relativePath,
}) {
  return LibraryCatalogItem(
    id: id,
    title: title,
    author: null,
    fileName: fileName,
    fileHash: null,
    relativePath: relativePath,
    fileFormat: 'epub',
    folderType: 'research',
    libraryRole: 'user_added',
    collectionName: 'EGW_Devotionals',
    sourceSite: null,
    sourceUrl: null,
    sourceType: 'official_download',
    coverPath: null,
    dateAdded: null,
    lastOpened: null,
    indexStatus: 'indexed',
    fileSize: 0,
    mimeType: 'application/epub+zip',
    spineIndex: null,
    anchorId: null,
    epubHref: null,
    paragraphIndex: null,
    navigationCount: 0,
  );
}

void main() {
  test('maps Christ Triumphant to the expected ref abbreviation', () {
    final item = _catalogItem(
      id: 'ct',
      title: 'Christ Triumphant',
      fileName: 'en_CTr.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_CTr.epub',
    );

    expect(libraryReaderBookAbbreviation(item), 'CTr');
  });

  test('maps Conflict and Courage to the expected ref abbreviation', () {
    final item = _catalogItem(
      id: 'cc',
      title: 'Conflict and Courage',
      fileName: 'en_CC.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_CC.epub',
    );

    expect(libraryReaderBookAbbreviation(item), 'CC');
    expect(
      libraryReaderDevotionalFallbackRefCode(
        item: item,
        sectionTitle: 'A Clear View of God, May 13',
        paragraphIndex: 1,
      ),
      'CC May 13.1',
    );
  });

  test('keeps Christ’s Object Lessons mapped to COL', () {
    final item = _catalogItem(
      id: 'col',
      title: 'Christ’s Object Lessons',
      fileName: 'en_COL.epub',
      relativePath: 'ePubs/Research/EGW_Books/en_COL.epub',
    );

    expect(libraryReaderBookAbbreviation(item), 'COL');
  });

  test('maps Maranatha to Mar for devotional fallbacks', () {
    final item = _catalogItem(
      id: 'mar',
      title: 'Maranatha',
      fileName: 'en_Mar.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_Mar.epub',
    );

    expect(libraryReaderBookAbbreviation(item), 'Mar');
    expect(
      libraryReaderDevotionalFallbackRefCode(
        item: item,
        sectionTitle: 'Turmoil in the Cities, May 13',
        paragraphIndex: 1,
      ),
      'Mar May 13.1',
    );
  });

  test('does not apply devotional fallback to non-devotional books', () {
    final item = _catalogItem(
      id: 'col',
      title: 'Christ’s Object Lessons',
      fileName: 'en_COL.epub',
      relativePath: 'ePubs/Research/EGW_Books/en_COL.epub',
    ).copyWith(collectionName: 'EGW_Books', libraryRole: 'user_added');

    expect(
      libraryReaderDevotionalFallbackRefCode(
        item: item,
        sectionTitle: 'Teaching in Parables, May 13',
        paragraphIndex: 1,
      ),
      isNull,
    );
  });

  test('generates Acts-style ref codes from DB text blocks', () {
    final codes = generateLibraryTextBlockReferenceCodes(
      itemAbbreviation: 'AA',
      plainTexts: const <String>[
        'The church is God’s appointed agency for the salvation of men.',
        'Many and wonderful are the promises recorded in the Scriptures [10] regarding the church.',
        '“Ye are My witnesses, saith the Lord...”',
      ],
    );

    expect(codes, const <String?>['AA 9.1', 'AA 9.2', 'AA 10.1']);

    final block = LibraryBookBlock(
      html:
          '<p>The church is God’s appointed agency for the salvation of men.</p>',
      text: 'The church is God’s appointed agency for the salvation of men.',
      kind: 'paragraph',
      referenceCode: codes.first,
    );
    expect(block.referenceCode, 'AA 9.1');
  });

  test('skips devotional scripture subtitles for fallback numbering', () {
    final item = _catalogItem(
      id: 'ct',
      title: 'Christ Triumphant',
      fileName: 'en_CTr.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_CTr.epub',
    );

    final scriptureSubtitle = LibraryBookBlock(
      html:
          '<p class="bibletext center">Choose you this day whom ye will serve; ... Joshua 24:15.</p>',
      text: 'Choose you this day whom ye will serve; ... Joshua 24:15.',
      kind: 'paragraph',
      className: 'bibletext center',
      bodyOrder: 2,
    );
    final firstBodyParagraph = LibraryBookBlock(
      html: '<p>If those who are still on the stage of action...</p>',
      text: 'If those who are still on the stage of action...',
      kind: 'paragraph',
      bodyOrder: 3,
    );

    expect(
      libraryReaderShouldCountDevotionalFallbackParagraph(
        item: item,
        sectionTitle: 'Never Forget God’s Leading In The Past, May 13',
        block: scriptureSubtitle,
        fallbackParagraphCount: 0,
      ),
      isFalse,
    );
    expect(
      libraryReaderShouldCountDevotionalFallbackParagraph(
        item: item,
        sectionTitle: 'Never Forget God’s Leading In The Past, May 13',
        block: firstBodyParagraph,
        fallbackParagraphCount: 0,
      ),
      isTrue,
    );
    expect(
      libraryReaderDevotionalFallbackRefCode(
        item: item,
        sectionTitle: 'Never Forget God’s Leading In The Past, May 13',
        paragraphIndex: 1,
      ),
      'CTr May 13.1',
    );
  });

  test('skips Homeward Bound bible subtitles with a trailing dash citation', () {
    final item = _catalogItem(
      id: 'hb',
      title: 'Homeward Bound',
      fileName: 'en_HB.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_HB.epub',
    );

    const subtitle =
        'Nor did their own arm save them; but it was Your right hand, Your arm, and the light of Your countenance, because You favored them.—Psalm 44:3.';
    final subtitleBlock = LibraryBookBlock(
      html: '<p class="bibletext center">$subtitle</p>',
      text: subtitle,
      kind: 'paragraph',
      className: 'bibletext center',
      bodyOrder: 2,
    );
    final bodyBlock = LibraryBookBlock(
      html: '<p>Prayer moves the arm of omnipotence.</p>',
      text: 'Prayer moves the arm of omnipotence.',
      kind: 'paragraph',
      bodyOrder: 3,
    );

    expect(
      libraryReaderShouldCountDevotionalFallbackParagraphText(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        paragraphText: subtitle,
        className: subtitleBlock.className,
        fallbackParagraphCount: 0,
      ),
      isFalse,
    );
    expect(
      libraryReaderShouldCountDevotionalFallbackParagraphText(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        paragraphText: bodyBlock.text,
        className: bodyBlock.className,
        fallbackParagraphCount: 0,
      ),
      isTrue,
    );
    expect(
      libraryReaderDevotionalFallbackRefCodeForBlock(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        block: subtitleBlock,
        fallbackParagraphCount: 0,
      ),
      isNull,
    );
    expect(
      libraryReaderDevotionalFallbackRefCodeForBlock(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        block: bodyBlock,
        fallbackParagraphCount: 0,
      ),
      'HB May 13.1',
    );
    expect(
      libraryReaderDevotionalFallbackRefCodeForBlock(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        block: LibraryBookBlock(
          html: '<p>While the world is progressing...</p>',
          text: 'While the world is progressing...',
          kind: 'paragraph',
        ),
        fallbackParagraphCount: 1,
      ),
      'HB May 13.2',
    );
  });

  test('hides obvious devotional front matter entries from contents', () {
    expect(
      libraryReaderShouldHideDevotionalContentsEntry(
        label: 'Information about this Book',
        href: 'oebps/aboutbook.xhtml',
      ),
      isTrue,
    );
    expect(
      libraryReaderShouldHideDevotionalContentsEntry(
        label: 'A Word to the Reader',
        href: 'oebps/content00.xhtml',
      ),
      isTrue,
    );
    expect(
      libraryReaderShouldHideDevotionalContentsEntry(
        label: 'Like Parent, Like Child, May 13',
        href: 'oebps/content139.xhtml',
      ),
      isFalse,
    );
  });
}
