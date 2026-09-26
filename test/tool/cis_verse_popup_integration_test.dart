import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_xml_html_entities.dart';
import 'package:studybible2/features/library/presentation/library_verse_popup.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('CIS popup uses actual isolated Bible and active hashtag repositories', () async {
    if (Platform.environment['RUN_CIS_POPUP_INTEGRATION'] != '1') return;
    final output = Directory(p.absolute('tool/Verification/cis_1914_restoration/output'));
    final root = await output.createTemp('popup_integration_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel, (_) async => p.join(root.path, '.runtime'));
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    LibraryRootService.instance.invalidateCachedSelection();
    await LibraryRootService.instance.setLibraryRoot(path: root.path);
    final verses = await loadLibraryPopupVerses('(John 3:16,18)');
    expect(verses.map((v) => v.target.verse), [16, 18]);
    expect(verses.first.buildSpan(baseStyle: const TextStyle(), redLetterColor: Colors.red).toPlainText(), contains('God so loved the world'));
    final repository = HashTagRepository();
    await repository.saveDefaultTag('#popup-isolated-proof');
    final first = await tagLibraryPopupVerses(verses);
    expect(first, contains('Added 2'));
    final again = await tagLibraryPopupVerses(verses);
    expect(again, contains('already'));
    final rows = await repository.loadEntries('#popup-isolated-proof');
    expect(rows.length, 2);
    expect(rows.map((r) => r.verse).toSet(), {16, 18});
    final books = await StudyBibleDatabase.instance.loadBooks();
    final epub = ZipDecoder().decodeBytes(await File(p.join(output.path, 'CIS_reference_preview.epub')).readAsBytes());
    final failures = <Map<String, String>>[];
    final unavailable = <Map<String, String>>[];
    var citations = 0;
    for (final file in epub.files.where((f) => f.name.endsWith('.xhtml'))) {
      final html = utf8.decode(file.content as List<int>);
      for (final match in RegExp(r'<span\b[^>]*class="cis-inline-bible"[^>]*>([^<]*)').allMatches(html)) {
        final citation = decodeXmlHtmlEntities(match.group(1)!);
        citations++;
        try {
          parseLibraryCitation(citation, books);
          try { await loadLibraryPopupVerses(citation); }
          on FormatException { unavailable.add({'file': file.name, 'citation': citation.trim()}); }
        }
        on FormatException { failures.add({'file': file.name, 'citation': citation.trim()}); }
      }
    }
    expect(citations, 1048);
    final report = {'root': root.path, 'actual_bible_lookup': true,
      'actual_active_tag_repository': true, 'gap_not_tagged': true, 'duplicates_prevented': true,
      'citations': citations, 'parsed': citations - failures.length,
      'fully_resolved': citations - failures.length - unavailable.length,
      'unavailable_in_bible': unavailable, 'needs_review': failures};
    await File(p.join(output.path, 'popup_integration_report.json')).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    print('Popup integration passed; parsed ${citations-failures.length}/$citations citations. Isolated root: ${root.path}');
    await UserDatabase.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    LibraryRootService.instance.invalidateCachedSelection();
  });
}
