import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/features/library/presentation/library_verse_popup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'automatically linked references resolve against the installed Bible',
    () async {
      final fixture = Platform.environment['LIBRARY_CITATION_AUDIT_ROOT'];
      if (fixture == null) return;
      final output = p.absolute(
        'tool/Verification/cis_1914_restoration/output',
      );
      final root = await Directory(output).createTemp('auto_citation_audit_');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => p.join(root.path, '.runtime'),
          );
      await LibraryRootService.instance.setLibraryRoot(path: root.path);
      final db = await openDatabase(
        p.absolute(fixture, 'Databases/eLibrary.db'),
        readOnly: true,
      );
      final rows = await db.rawQuery(
        "SELECT json_extract(n.value,'\$.link') AS link FROM library_document_blocks b,json_each(b.formatted_content,'\$.nodes') n WHERE json_extract(n.value,'\$.link') LIKE 'studybible-citation:%'",
      );
      final links = rows.map((r) => r['link'] as String).toSet();
      final failures = <Map<String, String>>[];
      for (final link in links) {
        final citation = Uri.decodeComponent(
          link.substring('studybible-citation:'.length),
        );
        try {
          expect(await loadLibraryPopupVerses(citation), isNotEmpty);
        } on FormatException catch (error) {
          failures.add({'citation': citation, 'reason': error.message});
        }
      }
      await db.close();
      final report = {
        'fixture': fixture,
        'linked_occurrences': rows.length,
        'unique_targets': links.length,
        'resolved': links.length - failures.length,
        'needs_review': failures,
      };
      await File(
        p.join(root.path, 'report.json'),
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      print(
        'Citation audit: ${rows.length} links, ${links.length - failures.length}/${links.length} unique targets resolved; ${root.path}',
      );
    },
  );
}
