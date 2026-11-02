import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';
import 'package:studybible2/features/utilities/data/pioneer_text_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final work = PioneerSourceWork.fromJson(
    json: {
      'work_id': 'lessons_on_faith',
      'title': 'Lessons on Faith',
      'abbreviation': 'LOF',
      'availability_status': 'available',
    },
    authorId: 'at_jones',
    authorName: 'A. T. Jones',
  );
  Uint8List zip(Map<String, List<int>> files) {
    final archive = Archive();
    for (final e in files.entries) {
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('shared faith word cannot substitute another book', () {
    expect(
      extractPioneerEpubFromZipForTesting(
        work: work,
        zipBytes: zip({
          'Epub/James White/Our Faith and Hope, No. 1.epub': [1],
          'Epub/Waggoner EJ/Living by Faith.epub': [2],
        }),
      ),
      isNull,
    );
  });
  test('a single wrong book is still rejected', () {
    expect(
      extractPioneerEpubFromZipForTesting(
        work: work,
        zipBytes: zip({
          'Our Faith and Hope.epub': [1],
        }),
      ),
      isNull,
    );
  });
  test('exact title selects the intended EPUB', () {
    expect(
      extractPioneerEpubFromZipForTesting(
        work: work,
        zipBytes: zip({
          'Our Faith and Hope.epub': [1],
          'Jones/Lessons on Faith.epub': [2],
        }),
      ),
      [2],
    );
  });
  test('ambiguous same-title editions require explicit selection', () {
    expect(
      extractPioneerEpubFromZipForTesting(
        work: work,
        zipBytes: zip({
          'A/Lessons on Faith.epub': [1],
          'B/Lessons on Faith.epub': [2],
        }),
      ),
      isNull,
    );
  });
  test(
    'online catalog does not promise LOF from an archive that lacks it',
    () async {
      final catalog = await PioneerSourceCatalog.load();
      expect(catalog.workById('lessons_on_faith')!.isImportable, isFalse);
    },
  );
}
