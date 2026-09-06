import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/library_navigation_tree.dart';

LibraryCatalogNavigationItem _navItem({
  required String id,
  required String label,
  required int sortOrder,
  required bool isFrontMatter,
  required bool isBodyStart,
}) {
  return LibraryCatalogNavigationItem(
    id: id,
    parentId: null,
    label: label,
    href: 'OPS/$id.xhtml',
    anchorId: null,
    spineIndex: sortOrder,
    sortOrder: sortOrder,
    depth: 0,
    navType: 'toc',
    contentKind: 'chapter',
    isFrontMatter: isFrontMatter,
    isBodyStart: isBodyStart,
    bodyOrder: sortOrder,
  );
}

LibraryCatalogNavigationItem _sameFileSibling({
  required String id,
  required String label,
  required String anchorId,
  required int sortOrder,
}) {
  return LibraryCatalogNavigationItem(
    id: id,
    parentId: null,
    label: label,
    href: 'OEBPS/content.xhtml#$anchorId',
    anchorId: anchorId,
    spineIndex: sortOrder,
    sortOrder: sortOrder,
    depth: 0,
    navType: 'toc',
    contentKind: 'chapter',
    isFrontMatter: false,
    isBodyStart: sortOrder == 1,
    bodyOrder: sortOrder,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'top-level headings that share one physical file via distinct anchors '
    'stay siblings instead of nesting under the first one (SL27 regression: '
    'INTRODUCTION, ARGUMENT, APPENDIX A are all root-level in one content.xhtml)',
    () {
      final introduction = _sameFileSibling(
        id: 'introduction',
        label: 'INTRODUCTION',
        anchorId: 'heading-2-1',
        sortOrder: 1,
      );
      final argument = _sameFileSibling(
        id: 'argument',
        label: 'ARGUMENT',
        anchorId: 'heading-2-3',
        sortOrder: 3,
      );
      final appendixA = _sameFileSibling(
        id: 'appendix-a',
        label: 'APPENDIX A',
        anchorId: 'heading-2-11',
        sortOrder: 11,
      );

      final tree = buildLibraryNavigationTree([
        introduction,
        argument,
        appendixA,
      ]);

      expect(tree.childrenByParent[null]?.map((item) => item.id), <String>[
        'introduction',
        'argument',
        'appendix-a',
      ]);
      expect(tree.childrenByParent[introduction.id], isNull);
    },
  );

  test('top-level headings that share one physical file via distinct href '
      'fragments stay siblings when anchor_id is empty (SL27\'s actual live '
      'shape: anchor_id is always NULL, only href carries the fragment)', () {
    LibraryCatalogNavigationItem sameFileSiblingWithoutAnchorId({
      required String id,
      required String label,
      required String hrefFragment,
      required int sortOrder,
    }) {
      return LibraryCatalogNavigationItem(
        id: id,
        parentId: null,
        label: label,
        href: 'OEBPS/content.xhtml#$hrefFragment',
        anchorId: null,
        spineIndex: sortOrder,
        sortOrder: sortOrder,
        depth: 0,
        navType: 'toc',
        contentKind: 'chapter',
        isFrontMatter: false,
        isBodyStart: sortOrder == 1,
        bodyOrder: sortOrder,
      );
    }

    final introduction = sameFileSiblingWithoutAnchorId(
      id: 'introduction',
      label: 'INTRODUCTION',
      hrefFragment: 'heading-2-1',
      sortOrder: 1,
    );
    final argument = sameFileSiblingWithoutAnchorId(
      id: 'argument',
      label: 'ARGUMENT',
      hrefFragment: 'heading-2-3',
      sortOrder: 3,
    );
    final article = sameFileSiblingWithoutAnchorId(
      id: 'article',
      label: 'ARTICLE',
      hrefFragment: 'heading-2-5',
      sortOrder: 5,
    );
    final appendixA = sameFileSiblingWithoutAnchorId(
      id: 'appendix-a',
      label: 'APPENDIX A',
      hrefFragment: 'heading-2-11',
      sortOrder: 11,
    );
    final appendixB = sameFileSiblingWithoutAnchorId(
      id: 'appendix-b',
      label: 'APPENDIX B',
      hrefFragment: 'heading-2-13',
      sortOrder: 13,
    );

    final tree = buildLibraryNavigationTree([
      introduction,
      argument,
      article,
      appendixA,
      appendixB,
    ]);

    expect(tree.childrenByParent[null]?.map((item) => item.id), <String>[
      'introduction',
      'argument',
      'article',
      'appendix-a',
      'appendix-b',
    ]);
    expect(tree.childrenByParent[introduction.id], isNull);
  });

  test('a genuine repeated TOC row for the same anchor still nests under the '
      'first occurrence instead of becoming a duplicate root', () {
    final first = _sameFileSibling(
      id: 'chapter-first-pass',
      label: 'CHAPTER I',
      anchorId: 'heading-1',
      sortOrder: 1,
    );
    final repeated = _sameFileSibling(
      id: 'chapter-second-pass',
      label: 'CHAPTER I (CONTINUED)',
      anchorId: 'heading-1',
      sortOrder: 2,
    );

    final tree = buildLibraryNavigationTree([first, repeated]);

    expect(tree.childrenByParent[null]?.map((item) => item.id), <String>[
      'chapter-first-pass',
    ]);
    expect(tree.childrenByParent[first.id]?.map((item) => item.id), <String>[
      'chapter-second-pass',
    ]);
  });

  test('places body sections before Pioneer front matter in the TOC tree', () {
    final tree = buildLibraryNavigationTree([
      _navItem(
        id: 'title-page',
        label: 'The Story of the Seer of Patmos',
        sortOrder: 1,
        isFrontMatter: true,
        isBodyStart: false,
      ),
      _navItem(
        id: 'foreword',
        label: 'Foreword',
        sortOrder: 2,
        isFrontMatter: true,
        isBodyStart: false,
      ),
      _navItem(
        id: 'chapter-1',
        label: 'CHAPTER I. THE SEER OF PATMOS',
        sortOrder: 3,
        isFrontMatter: false,
        isBodyStart: true,
      ),
      _navItem(
        id: 'chapter-2',
        label: 'CHAPTER II. THE AUTHOR OF THE REVELATION',
        sortOrder: 4,
        isFrontMatter: false,
        isBodyStart: false,
      ),
    ]);

    expect(tree.items.map((item) => item.id), [
      'chapter-1',
      'chapter-2',
      'title-page',
      'foreword',
    ]);
  });
}
