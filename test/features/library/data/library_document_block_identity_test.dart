import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_document_block_identity.dart';

Map<String, Object?> block(
  String id,
  String text,
  int order, {
  String? anchor,
}) => {
  'id': id,
  'library_item_id': 'work-id',
  'source_href': 'chapter.xhtml',
  'source_anchor': anchor,
  'block_type': 'paragraph',
  'plain_text': text,
  'display_order': order,
};

Map<String, String> reconcile(
  List<Map<String, Object?>> old,
  List<Map<String, Object?>> next,
) => reconcileLibraryBlockIds(
  libraryItemId: 'work-id',
  sourceHash: 'source-sha',
  previous: old,
  candidate: next,
);

void main() {
  Map<String, Object?> linked(String id, String href, int order) => {
    ...block(id, 'Appendix', order),
    'formatted_content': jsonEncode({
      'nodes': [
        {
          'type': 'text',
          'text': 'Appendix',
          'link': href,
          'link_kind': 'internal',
        },
      ],
    }),
  };
  test(
    'distinct same-label links retain identity when surrounding blocks move',
    () {
      final old = [
        block('lead', 'Lead', 0),
        linked('part', '#appendix-part', 1),
        linked('chapter', '#appendix-chapter', 2),
        block('summary', 'Summary', 3),
      ];
      final next = [
        block('new-lead', 'Lead', 0),
        block('new-summary', 'Summary', 1),
        linked('new-part', '#appendix-part', 2),
        linked('new-chapter', '#appendix-chapter', 3),
      ];
      expect(reconcile(old, next), {
        'new-lead': 'lead',
        'new-summary': 'summary',
        'new-part': 'part',
        'new-chapter': 'chapter',
      });
    },
  );
  test(
    'duplicate or changed link destinations are not evidence of identity',
    () {
      final old = [linked('a', '#same', 0), linked('b', '#same', 1)];
      expect(reconcile(old, [linked('new', '#same', 0)])['new'], 'new');
      expect(reconcile(old, [linked('new', '#changed', 0)])['new'], 'new');
      final differentFile = {
        ...linked('new', '#same', 0),
        'source_href': 'other.xhtml',
      };
      expect(
        reconcile([linked('a', '#same', 0)], [differentFile])['new'],
        'new',
      );
    },
  );

  test('adding a new unique page anchor retains an unchanged paragraph ID', () {
    final old = [block('old', 'Unique paragraph', 0)];
    final next = [block('new', 'Unique paragraph', 0, anchor: 'page-421')];
    expect(reconcile(old, next), {'new': 'old'});
    expect(
      reconcile([
        {...next.single, 'id': 'old'},
      ], next),
      {'new': 'old'},
    );
  });

  test('new anchors cannot disambiguate duplicate text or changed content', () {
    for (final old in [
      [block('old', 'Repeated', 0), block('other', 'Repeated', 1)],
      [block('old', 'Different wording', 0)],
    ]) {
      expect(
        reconcile(old, [block('new', 'Repeated', 0, anchor: 'page-1')])['new'],
        'new',
      );
    }
    final old = [block('old', 'Repeated', 0)];
    final next = [
      block('new', 'Repeated', 0, anchor: 'page-1'),
      block('other', 'Repeated', 1, anchor: 'page-2'),
    ];
    expect(reconcile(old, next).values, isNot(contains('old')));
  });

  test(
    'a page anchor belonging to another old block cannot migrate identity',
    () {
      for (final landmarkOwner in [
        block('owner', 'Other content', 1, anchor: 'page-1'),
        {
          ...block('owner', 'Other content', 1),
          'formatted_content': jsonEncode({
            'metadata': {
              'source_anchor_aliases': ['page-1'],
            },
          }),
        },
      ]) {
        final old = [block('old', 'Unique text', 0), landmarkOwner];
        final next = [block('new', 'Unique text', 0, anchor: 'page-1')];
        // An existing primary anchor is the established identity. An old alias
        // is not grounds for assigning the formerly unanchored paragraph ID.
        expect(reconcile(old, next)['new'], isNot('old'));
      }
    },
  );

  test(
    'new anchor must be unique across primary and nested candidate anchors',
    () {
      for (final landmarkOwner in [
        block('owner', 'Other content', 1, anchor: 'page-1'),
        {
          ...block('owner', 'Other content', 1),
          'formatted_content': jsonEncode({
            'metadata': {
              'source_anchor_aliases': ['page-1'],
            },
          }),
        },
      ]) {
        expect(
          reconcile(
            [block('old', 'Unique text', 0)],
            [block('new', 'Unique text', 0, anchor: 'page-1'), landmarkOwner],
          )['new'],
          'new',
        );
      }
    },
  );

  test('adding an anchor cannot bridge distinct source files', () {
    expect(
      reconcile(
        [block('old', 'Unique text', 0)],
        [
          {
            ...block('new', 'Unique text', 0, anchor: 'page-1'),
            'source_href': 'different.xhtml',
          },
        ],
      )['new'],
      'new',
    );
  });

  test(
    'inserted content cannot steal an ordinal ID and repeat imports retain the mapping',
    () {
      final old = [block('r0', 'Alpha', 0), block('r1', 'Beta', 1)];
      final next = [
        block('r0', 'Inserted', 0),
        block('r1', 'Alpha', 1),
        block('r2', 'Beta', 2),
      ];
      final ids = reconcile(old, next);
      expect(ids['r1'], 'r0');
      expect(ids['r2'], 'r1');
      expect(ids['r0'], isNot(isIn(['r0', 'r1', 'r2'])));
      final persisted = [
        for (final row in next) {...row, 'id': ids[row['id']]},
      ];
      expect(reconcile(persisted, next), ids);
    },
  );

  test(
    'a unique source anchor preserves identity through corrected wording and reordered blocks',
    () {
      final old = [
        block('a', 'Typo in original', 0, anchor: 'para-a'),
        block('b', 'Beta', 1, anchor: 'para-b'),
      ];
      final next = [
        block('new-b', 'Beta', 0, anchor: 'para-b'),
        block('new-a', 'Corrected wording', 1, anchor: 'para-a'),
      ];
      expect(reconcile(old, next), {'new-b': 'b', 'new-a': 'a'});
    },
  );

  test(
    'unchanged duplicate paragraphs retain order between proven matching boundaries',
    () {
      final old = [
        block('a', 'Alpha', 0),
        block('b', 'Repeated', 1),
        block('c', 'Repeated', 2),
        block('d', 'Delta', 3),
      ];
      final next = [
        block('a', 'Inserted', 0),
        block('b', 'Alpha', 1),
        block('c', 'Repeated', 2),
        block('d', 'Repeated', 3),
        block('e', 'Delta', 4),
      ];
      final ids = reconcile(old, next);
      expect(ids['b'], 'a');
      expect(ids['c'], 'b');
      expect(ids['d'], 'c');
      expect(ids['e'], 'd');
    },
  );

  test(
    'an ambiguous duplicate insertion never reassigns a former identity',
    () {
      final old = [block('a', 'Repeated', 0), block('b', 'Repeated', 1)];
      final next = [
        block('a', 'Repeated', 0),
        block('b', 'Repeated', 1),
        block('c', 'Repeated', 2),
      ];
      expect(
        reconcile(old, next).values.toSet().intersection({'a', 'b'}),
        isEmpty,
      );
    },
  );

  test(
    'a replacement at the same ordinal cannot inherit the old paragraph ID',
    () {
      final ids = reconcile(
        [block('a', 'Original', 0)],
        [block('a', 'Different text', 0)],
      );
      expect(ids['a'], isNot('a'));
    },
  );

  test(
    'identical words with a changed explicit source anchor are not the same location',
    () {
      final ids = reconcile(
        [block('a', 'Text', 0, anchor: 'old')],
        [block('a', 'Text', 0, anchor: 'different')],
      );
      expect(ids['a'], isNot('a'));
    },
  );

  test('source files and work IDs form hard identity boundaries', () {
    final a = block('a', 'Text', 0, anchor: 'p');
    final b = {...a, 'source_href': 'other.xhtml'};
    expect(reconcile([a], [b])['a'], isNot('a'));
    expect(
      () => reconcile(
        [a],
        [
          {...a, 'library_item_id': 'another-work'},
        ],
      ),
      throwsArgumentError,
    );
  });
}
