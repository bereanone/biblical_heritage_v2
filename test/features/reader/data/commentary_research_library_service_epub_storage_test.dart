import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';

void main() {
  test('preferred commentary volume does not fall back to unrelated rows', () {
    final rows = <Map<String, Object?>>[
      {
        'file_name': 'en_2T.epub',
        'title': 'Testimonies for the Church, vol. 2',
      },
      {
        'file_name': 'en_2TT.epub',
        'title': 'Testimony Treasures, vol. 2',
      },
    ];

    final filtered = filterRowsByPreferredCommentaryVolume(rows, '1BC');

    expect(filtered, isEmpty);
  });

  test('preferred commentary volume keeps matching rows only', () {
    final rows = <Map<String, Object?>>[
      {
        'file_name': 'en_1T.epub',
        'title': 'Testimonies for the Church, vol. 1',
      },
      {
        'file_name': 'en_2T.epub',
        'title': 'Testimonies for the Church, vol. 2',
      },
    ];

    final filtered = filterRowsByPreferredCommentaryVolume(rows, '1BC');

    expect(filtered, hasLength(1));
    expect(filtered.single['file_name'], 'en_1T.epub');
  });
}
