import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:studybible2/features/library/data/library_document_import_validator.dart';

Map<String, Object?> _section({required String id, int displayOrder = 0}) =>
    <String, Object?>{
      'id': id,
      'library_item_id': 'ITEM',
      'display_order': displayOrder,
      'title': 'Section',
      'source_href': 'ch1.xhtml',
      'content_hash': 'hash',
    };

Map<String, Object?> _block({
  required int displayOrder,
  String blockType = 'paragraph',
  String plainText = 'Some readable text.',
  String? formattedContent,
}) => <String, Object?>{
  'id': 'b$displayOrder',
  'library_item_id': 'ITEM',
  'section_id': 's1',
  'display_order': displayOrder,
  'block_type': blockType,
  'plain_text': plainText,
  'formatted_content':
      formattedContent ??
      '{"version":1,"nodes":[{"type":"text","text":"$plainText"}]}',
  'content_hash': 'hash$displayOrder',
};

void main() {
  const validator = LibraryDocumentImportValidator();

  test('passes for a minimal well-formed generation', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[_block(displayOrder: 0)],
    );
    expect(result.passed, isTrue);
    expect(result.reasons, isEmpty);
  });

  test('fails when no sections were produced', () {
    final result = validator.validate(
      sections: const <Map<String, Object?>>[],
      blocks: <Map<String, Object?>>[_block(displayOrder: 0)],
    );
    expect(result.passed, isFalse);
    expect(result.summary, contains('No sections'));
  });

  test('fails when no blocks were produced', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: const <Map<String, Object?>>[],
    );
    expect(result.passed, isFalse);
    expect(result.summary, contains('No content blocks'));
  });

  test('fails when display_order has a gap', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[
        _block(displayOrder: 0),
        _block(displayOrder: 2),
      ],
    );
    expect(result.passed, isFalse);
    expect(result.summary, contains('not contiguous'));
  });

  test('fails when every block is empty text (no readable content)', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[
        _block(displayOrder: 0, blockType: 'horizontalRule', plainText: ''),
      ],
    );
    expect(result.passed, isFalse);
    expect(result.summary, contains('No readable main content'));
  });

  test('fails when all readable content is classified as front matter', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[
        _block(
          displayOrder: 0,
          blockType: 'heading',
          plainText: 'Preface',
          formattedContent:
              '{"version":1,"nodes":[{"type":"text","text":"Preface"}],'
              '"metadata":{"heading_role":"front_matter"}}',
        ),
      ],
    );
    expect(result.passed, isFalse);
    expect(result.summary, contains('dead end'));
  });

  test('passes when main content follows classified front matter', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[
        _block(
          displayOrder: 0,
          blockType: 'heading',
          plainText: 'Preface',
          formattedContent:
              '{"version":1,"nodes":[{"type":"text","text":"Preface"}],'
              '"metadata":{"heading_role":"front_matter"}}',
        ),
        _block(displayOrder: 1, plainText: 'Chapter body text.'),
      ],
    );
    expect(result.passed, isTrue);
  });

  test('fails closed when formatted nodes fuse source word boundaries', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[
        _block(
          displayOrder: 0,
          plainText: 'consequences of which [163] it is difficult',
          formattedContent:
              '{"version":1,"nodes":['
              '{"type":"text","text":"consequences of which"},'
              '{"type":"text","text":"[163]"},'
              '{"type":"text","text":"it is difficult"}]}',
        ),
      ],
    );

    expect(result.passed, isFalse);
    expect(
      result.summary,
      contains('does not preserve the source word boundaries'),
    );
  });

  test('accepts intentional zero-space styling and punctuation cleanup', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[
        _block(
          displayOrder: 0,
          plainText: 'unreasonable Greek, τὰ ἅγια , the holy places',
          formattedContent:
              '{"version":1,"nodes":['
              '{"type":"text","text":"un"},'
              '{"type":"text","text":"reasonable Greek, τὰ ἅγια"},'
              '{"type":"text","text":", the holy places"}]}',
        ),
      ],
    );

    expect(result.passed, isTrue);
  });

  test('fails closed when an authored Contents destination is unresolved', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[_block(displayOrder: 0)],
      navigation: const <Map<String, Object?>>[
        <String, Object?>{
          'label': 'Chapter 1',
          'source_href': 'ch1.xhtml',
          'target_block_id': null,
        },
      ],
    );
    expect(result.passed, isFalse);
    expect(result.summary, contains('Chapter 1'));
  });

  test('passes when every authored Contents destination resolves', () {
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[_block(displayOrder: 0)],
      navigation: const <Map<String, Object?>>[
        <String, Object?>{
          'label': 'Chapter 1',
          'source_href': 'ch1.xhtml',
          'target_block_id': 'b0',
        },
      ],
    );
    expect(result.passed, isTrue);
  });

  test('fails when a referenced image asset is missing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'validator_images_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[
        _block(
          displayOrder: 0,
          blockType: 'image',
          plainText: '',
          formattedContent:
              '{"version":1,"nodes":[{"type":"image","source":"missing.png"}]}',
        ),
      ],
      imageAssetRoot: directory,
    );
    expect(result.passed, isFalse);
    expect(result.summary, contains('missing.png'));
  });

  test('passes when a referenced image asset exists', () async {
    final directory = await Directory.systemTemp.createTemp(
      'validator_images_',
    );
    addTearDown(() => directory.delete(recursive: true));
    await File(
      p.join(directory.path, 'present.png'),
    ).writeAsBytes(const <int>[1, 2, 3]);
    final result = validator.validate(
      sections: <Map<String, Object?>>[_section(id: 's1')],
      blocks: <Map<String, Object?>>[
        _block(
          displayOrder: 0,
          blockType: 'image',
          plainText: '',
          formattedContent:
              '{"version":1,"nodes":[{"type":"image","source":"present.png"}]}',
        ),
        _block(displayOrder: 1, plainText: 'Caption paragraph.'),
      ],
      imageAssetRoot: directory,
    );
    expect(result.passed, isTrue);
  });
}
