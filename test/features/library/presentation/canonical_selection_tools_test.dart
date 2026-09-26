import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/canonical_selection_tools.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_selection_menu.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final item = LibraryCatalogItem.fromRow({
    'id': 'cis',
    'title': 'The Cross and Its Shadow',
    'relative_path': 'CIS.epub',
  });
  final block = LibraryDocumentBlock(
    id: 'paragraph-45',
    libraryItemId: 'cis',
    sectionId: 'chapter',
    displayOrder: 200,
    blockType: LibraryDocumentBlockType.paragraph,
    plainText: 'The ark was central.',
    formattedContent: LibraryFormattedContent.plain(
      'The ark was central.',
    ).toJson(),
    contentHash: 'edition-content-hash',
    sourceRefcode: 'CIS 45.1',
    sourceHref: 'chapter.xhtml',
    sourceAnchor: 'p45',
  );

  test('copy citation preserves selected words and source reference', () {
    expect(
      buildLibrarySelectionClipboardText(
        'ark was',
        referenceLabel: canonicalSelectionReference(item, block),
      ),
      'ark was\n— CIS 45.1',
    );
    expect(buildLibrarySelectionClipboardText('ark was'), 'ark was');
  });

  testWidgets(
    'shared menu exposes citation, tag and markup actions on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      LibrarySelectionRangeAction? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await showLibrarySelectionRangeActionsSheet(
                    context,
                    payload: LibrarySelectionRangeActionsPayload(
                      referenceLabel: 'CIS 45.1',
                      previewText: 'Long selected passage. ' * 100,
                      enableClearMarkup: true,
                    ),
                    fontScale: 1,
                    showRichCopy: false,
                    showUnderline: true,
                  );
                },
                child: const Text('Select'),
              ),
            ),
          ),
        ),
      );
      for (final entry in {
        'Copy With Citation': LibrarySelectionRangeAction.copyWithCitation,
        'Add # Tag': LibrarySelectionRangeAction.addHashTag,
        'Choose # Tag': LibrarySelectionRangeAction.chooseHashTag,
        'Underline': LibrarySelectionRangeAction.underline,
      }.entries) {
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();
        for (final label in [
          'Copy No Citation',
          'Copy With Citation',
          'Highlight',
          'Underline',
          'Clear Markup',
          'Add # Tag',
          'Choose # Tag',
          'Reset Range',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('Copy With Markup'), findsNothing);
        await tester.ensureVisible(find.text(entry.key));
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(chosen, entry.value);
        expect(tester.takeException(), isNull);
      }
    },
  );

  test(
    'tag stores exact excerpt, citation and authored source; duplicate is skipped',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'canonical-selection-tags-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => root.path);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LibraryRootService.instance.invalidateCachedSelection();
      await LibraryRootService.instance.setLibraryRoot(path: root.path);
      final db = await databaseFactoryFfi.openDatabase(
        '${root.path}/fixture.db',
      );
      try {
        await ELibrarySchema.ensure(db);
        await db.insert('library_block_source_map', {
          'library_item_id': 'cis',
          'block_id': block.id,
          'source_href': 'chapter.xhtml',
          'legacy_block_index': 12,
          'legacy_paragraph_index': 7,
          'source_anchor': 'p45',
        });
        final tags = HashTagRepository();
        final repo = LibraryDocumentRepository(db);
        final first = await saveCanonicalSelectionToTag(
          repository: repo,
          tags: tags,
          item: item,
          block: block,
          start: 4,
          end: 11,
          tag: '#sanctuary',
        );
        expect(first.inserted, 1);
        final again = await saveCanonicalSelectionToTag(
          repository: repo,
          tags: tags,
          item: item,
          block: block,
          start: 4,
          end: 11,
          tag: '#sanctuary',
        );
        expect(again.skipped, 1);
        final entries = await tags.loadEntries('#sanctuary');
        expect(entries.length, 1);
        expect(entries.single.noteText, 'ark was');
        final metadata =
            jsonDecode(entries.single.noteFormatJson!) as Map<String, dynamic>;
        expect(metadata['source_reference_text'], 'CIS 45.1');
        expect(metadata['source_href'], 'chapter.xhtml');
        expect(metadata['source_paragraph_index'], 7);
        expect(metadata['source_library_item_id'], 'cis');
        expect(metadata['source_anchor_id'], 'p45');
      } finally {
        await UserDatabase.instance.close();
        await db.close();
        LibraryRootService.instance.invalidateCachedSelection();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await root.delete(recursive: true);
      }
    },
  );
}
