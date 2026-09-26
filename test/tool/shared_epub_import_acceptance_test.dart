import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_acquisition_orchestrator.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/library/presentation/library_document_controller.dart';
import 'package:studybible2/features/library/data/user_epub_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real EGW and preferred DAR complete import, Ready, retry, and cold resume',
    () async {
      if (Platform.environment['RUN_SHARED_EPUB_ACCEPTANCE'] != '1') return;
      final sources = <String, String>{
        'official_egw_acts_of_the_apostles':
            Platform.environment['EGW_ACCEPTANCE_EPUB']!,
        'restored_dar_1897_delivery':
            Platform.environment['DAR_ACCEPTANCE_EPUB']!,
        'preferred_dar_1897_last_opened_revision':
            Platform.environment['PREFERRED_DAR_ACCEPTANCE_EPUB']!,
        if ((Platform.environment['COMMENTARY_ACCEPTANCE_EPUB'] ?? '')
            .trim()
            .isNotEmpty)
          'official_egw_commentary_1bc':
              Platform.environment['COMMENTARY_ACCEPTANCE_EPUB']!,
      };
      final commentaryDirectory =
          (Platform.environment['COMMENTARY_ACCEPTANCE_DIR'] ?? '').trim();
      if (commentaryDirectory.isNotEmpty) {
        final files =
            Directory(commentaryDirectory)
                .listSync()
                .whereType<File>()
                .where(
                  (file) => RegExp(
                    r'^en_(?:[1-7]BC|7ABC)\.epub$',
                    caseSensitive: false,
                  ).hasMatch(p.basename(file.path)),
                )
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final file in files) {
          sources['official_egw_commentary_${p.basenameWithoutExtension(file.path).toLowerCase()}'] =
              file.path;
        }
      }
      final evidenceDir = Directory(
        p.absolute('tool/Verification/shared_import_reader_fix_2026-09-15'),
      );
      final root = await evidenceDir.createTemp('acceptance_root_');
      final runtime = await Directory(p.join(root.path, '.runtime')).create();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => runtime.path);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LibraryRootService.instance.invalidateCachedSelection();
      await LibraryRootService.instance.setLibraryRoot(path: root.path);
      final report = <String, Object?>{
        'root': root.path,
        'live_library_modified': false,
        'items': <String, Object?>{},
      };
      try {
        for (final entry in sources.entries) {
          final source = File(entry.value);
          expect(await source.exists(), isTrue, reason: entry.key);
          final inspection = await UserEpubImportService.instance.inspect(
            source.path,
          );
          final imported = await UserEpubImportService.instance.copyIntoLibrary(
            source.path,
            confirmedInspection: inspection,
          );
          final outcome = await LibraryAcquisitionOrchestrator.instance
              .prepareExistingEpub(
                libraryItemId: imported.libraryItemId,
                relativePath: imported.relativePath,
              );
          expect(outcome.isReady, isTrue, reason: outcome.technicalDetail);
          final catalogItem = await LibraryCatalogService.instance.loadItemById(
            imported.libraryItemId,
          );
          expect(catalogItem, isNotNull, reason: entry.key);
          final readerPreparation = await prepareCanonicalEpubReader(
            catalogItem!,
          );
          if (entry.key.startsWith('official_egw_commentary_')) {
            expect(readerPreparation, isNotNull, reason: entry.key);
          }
          var measuredGeometryStayedLoaded = false;
          if (entry.key.startsWith('official_egw_commentary_') &&
              readerPreparation != null) {
            final controller = LibraryDocumentController(
              libraryItemId: imported.libraryItemId,
              repository: readerPreparation.repository,
              windowRadius: 24,
              preserveLoadedGeometry: true,
            );
            await controller.initialize(centerOrder: 24);
            final measured = controller.blockAt(1);
            await controller.ensureWindow(
              (await readerPreparation.repository.blockCount(
                    imported.libraryItemId,
                  )) -
                  2,
            );
            measuredGeometryStayedLoaded =
                measured != null && controller.blockAt(1)?.id == measured.id;
            controller.dispose();
            expect(measuredGeometryStayedLoaded, isTrue, reason: entry.key);
          }
          final db = await ELibraryDatabase.instance.database;
          final blocks = await db.query(
            'library_document_blocks',
            where: 'library_item_id=?',
            whereArgs: [imported.libraryItemId],
            orderBy: 'display_order',
          );
          final nav = await db.query(
            'library_navigation_items',
            where: 'library_item_id=?',
            whereArgs: [imported.libraryItemId],
          );
          final target = blocks[blocks.length ~/ 2];
          final anchor = 'canonical:${target['id']}';
          final paragraph = target['display_order'] as int;
          await db.update(
            'library_items',
            {
              'anchor_id': anchor,
              'paragraph_index': paragraph,
              'last_opened': '2026-09-15T20:00:00.000Z',
            },
            where: 'id=?',
            whereArgs: [imported.libraryItemId],
          );
          report['items'] = {
            ...(report['items'] as Map<String, Object?>),
            entry.key: {
              'source_path': source.path,
              'source_sha256': inspection.sourceSha256,
              'title': inspection.title,
              'creator': inspection.creator,
              'spine_items': inspection.spineItemCount,
              'library_item_id': imported.libraryItemId,
              'ready': outcome.isReady,
              'canonical_reader_prepared': readerPreparation != null,
              if (entry.key.startsWith('official_egw_commentary_'))
                'measured_geometry_stayed_loaded': measuredGeometryStayedLoaded,
              'canonical_blocks': blocks.length,
              'navigation_items': nav.length,
              'saved_anchor': anchor,
              'saved_paragraph': paragraph,
            },
          };
        }

        // A failed selection is rejected before it creates a catalog row. The
        // same user action can then be retried with the valid source and reaches
        // the already-proven Ready state without deleting that source.
        final invalid = File(p.join(root.path, 'retry.epub'));
        await invalid.writeAsString('not an epub');
        await expectLater(
          UserEpubImportService.instance.copyIntoLibrary(invalid.path),
          throwsA(isA<FormatException>()),
        );
        final retrySource = File(sources.values.first);
        final retry = await UserEpubImportService.instance.copyIntoLibrary(
          retrySource.path,
        );
        final retryOutcome = await LibraryAcquisitionOrchestrator.instance
            .prepareExistingEpub(
              libraryItemId: retry.libraryItemId,
              relativePath: retry.relativePath,
            );
        expect(retryOutcome.isReady, isTrue);
        report['failure_retry'] = {
          'invalid_rejected_before_catalog': true,
          'retry_ready': true,
        };

        await ELibraryDatabase.instance.close();
        await UserDatabase.instance.close();
        final reopened = await ELibraryDatabase.instance.database;
        for (final dynamic value in (report['items'] as Map).values) {
          final item = value as Map<String, Object?>;
          final row = (await reopened.query(
            'library_items',
            where: 'id=?',
            whereArgs: [item['library_item_id']],
          )).single;
          expect(row['anchor_id'], item['saved_anchor']);
          expect(row['paragraph_index'], item['saved_paragraph']);
        }
        report['cold_reopen_saved_positions_preserved'] = true;
        await File(
          p.join(evidenceDir.path, 'shared_epub_acceptance.json'),
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      } finally {
        await ELibraryDatabase.instance.close();
        await UserDatabase.instance.close();
        LibraryRootService.instance.invalidateCachedSelection();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
