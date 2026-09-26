// Opt-in audit of the user's reviewed DAR through the actual single import path.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';
import 'package:studybible2/features/library/presentation/library_embedded_raster.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_collection_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_text_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reviewed DAR retains images and illustration destinations',
    () async {
      final source = Platform.environment['DAR_AUDIT_EPUB'];
      if (source == null) return;
      final output = p.absolute(
        'tool/Verification/cis_1914_restoration/output',
      );
      final root = await Directory(output).createTemp('dar_single_import_');
      final runtime = await Directory(p.join(root.path, '.runtime')).create();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => runtime.path);
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      LibraryRootService.instance.invalidateCachedSelection();
      await LibraryRootService.instance.setLibraryRoot(path: root.path);
      try {
        final archive = ZipDecoder().decodeBytes(
          await File(source).readAsBytes(),
        );
        var sourceImages = 0;
        var decodedWrappers = 0;
        for (final file in archive.files.where(
          (f) => f.name.endsWith('.svg'),
        )) {
          final raster = LibraryEmbeddedRaster.parse(
            utf8.decode(file.content as List<int>),
          );
          final codec = await ui.instantiateImageCodec(raster.bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThan(0));
          frame.image.dispose();
          codec.dispose();
          decodedWrappers++;
        }
        final links = <Map<String, String>>[];
        for (final file in archive.files.where(
          (f) => f.name.endsWith('.xhtml'),
        )) {
          final html = utf8.decode(file.content as List<int>);
          sourceImages += RegExp(
            r'<img\b',
            caseSensitive: false,
          ).allMatches(html).length;
          for (final paragraph in RegExp(
            r'<p\b[^>]*id="dar-illustration-entry-[^"]+"[^>]*>(.*?)</p>',
            dotAll: true,
          ).allMatches(html)) {
            final href = RegExp(
              r'<a\b[^>]*href="([^"]+)"',
            ).firstMatch(paragraph[1]!);
            if (href != null) links.add({'from': file.name, 'href': href[1]!});
          }
        }
        final work = await loadPioneerWorkFromLocalEpubFile(source);
        expect(work, isNotNull);
        final result = await PioneerTextImportService.instance
            .importLocalEpubFile(work: work!, filePath: source);
        final db = await ELibraryDatabase.instance.database;
        final images = await db.query(
          'library_document_blocks',
          where: "library_item_id=? AND block_type='image'",
          whereArgs: [result.libraryItemId],
          orderBy: 'display_order',
        );
        final repository = LibraryDocumentRepository(db);
        final destinations = <Map<String, Object?>>[];
        for (final link in links) {
          final target = await repository.resolveSourceLink(
            result.libraryItemId,
            fromHref: link['from']!,
            href: link['href']!,
          );
          destinations.add({
            ...link,
            'resolved': target != null,
            'type': target?.blockType.name,
            'order': target?.displayOrder,
            'text': target?.plainText,
          });
        }
        final report = {
          'root': root.path,
          'item_id': result.libraryItemId,
          'source_images': sourceImages,
          'canonical_images': images.length,
          'decoded_svg_raster_wrappers': decodedWrappers,
          'illustration_links': destinations,
          'live_library_modified': false,
        };
        await File(
          p.join(output, 'dar_single_import_audit.json'),
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        print(
          'DAR audit root: ${root.path}; images ${images.length}/$sourceImages; links ${destinations.where((d) => d['resolved'] == true).length}/${links.length}',
        );
        expect(images.length, sourceImages);
        expect(links, isNotEmpty);
        expect(destinations.where((d) => d['resolved'] != true), isEmpty);
      } finally {
        await ELibraryDatabase.instance.close();
        await UserDatabase.instance.close();
        LibraryRootService.instance.invalidateCachedSelection();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
