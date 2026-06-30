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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
