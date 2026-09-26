import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/presentation/library_verse_popup.dart';
import 'package:studybible2/features/library/data/library_citation_links.dart';
import 'package:studybible2/features/library/data/library_xml_html_entities.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

void main() {
  testWidgets('FP Psalm popup button writes only to isolated default hashtag', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final root = (await tester.runAsync(
      () => Directory(
        p.absolute('tool/Verification/cis_1914_restoration/output'),
      ).createTemp('fp_popup_button_'),
    ))!;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => p.join(root.path, '.runtime'),
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    late List<LibraryPopupVerse> verses;
    final repository = HashTagRepository();
    await tester.runAsync(() async {
      LibraryRootService.instance.invalidateCachedSelection();
      await LibraryRootService.instance.setLibraryRoot(path: root.path);
      verses = await loadLibraryPopupVerses('Psalm 139:7');
      expect(
        await tagLibraryPopupVerses(verses),
        'No default hashtag currently selected.',
      );
      final chapter = await loadLibraryPopupVerses('Leviticus 16');
      expect(chapter.length, 34);
      expect(chapter.first.target.verse, 1);
      expect(chapter.last.target.verse, 34);
      expect(
        chapter.every((v) => v.target.book == 3 && v.target.chapter == 16),
        isTrue,
      );
      final peter = await loadLibraryPopupVerses('2 Peter 2:19');
      expect(peter.single.buildSpan(baseStyle: const TextStyle(), redLetterColor: Colors.red).toPlainText(), contains('promise them liberty'));
      final obadiah = await loadLibraryPopupVerses('Obadiah 15, 16');
      expect(obadiah.map((v) => v.target.verse), [15, 16]);
      for (final citation in ['John 3:3,5', 'John 3:3, 5']) {
        final john = await loadLibraryPopupVerses(citation);
        expect(john.map((v) => v.target.verse), [3, 5]);
      }
      final hebrews = await loadLibraryPopupVerses('Hebrews 8:4, 5; 9:6, 7');
      expect(hebrews.map((v) => '${v.target.chapter}:${v.target.verse}'), [
        '8:4',
        '8:5',
        '9:6',
        '9:7',
      ]);
      await repository.saveDefaultTag('#fp-isolated-proof');
      expect(await repository.loadEntries('#fp-isolated-proof'), isEmpty);
      final html = await File('assets/scans/FP187/capture.html').readAsString();
      final text = decodeXmlHtmlEntities(
        html.replaceAll(RegExp(r'<[^>]*>'), ' '),
      );
      final citations =
          linkLibraryCitations([
                {'type': 'text', 'text': text},
              ])
              .where((n) => n['link'] != null)
              .map(
                (n) => Uri.decodeComponent(
                  (n['link'] as String).substring(
                    'studybible-citation:'.length,
                  ),
                ),
              )
              .toSet();
      final failures = <String>[];
      for (final citation in citations) {
        try {
          await loadLibraryPopupVerses(citation);
        } catch (error) {
          failures.add('$citation: $error');
        }
      }
      await File(p.join(root.path, 'citation_audit.txt')).writeAsString(
        '${citations.length} distinct detected FP references; failures: $failures\n',
      );
      expect(failures, isEmpty);
      expect(await repository.loadEntries('#fp-isolated-proof'), isEmpty);
    });
    expect(verses.single.buildSpan(baseStyle: const TextStyle(), redLetterColor: Colors.red).toPlainText(), contains('Whither shall I go'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryVersePopup(
            citation: 'Psalm 139:7',
            loader: (_) async => verses,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Add to active hashtag'));
      for (var i = 0; i < 100; i++) {
        if ((await repository.loadEntries('#fp-isolated-proof')).isNotEmpty)
          break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Added 1 verse(s)'), findsOneWidget);
    await tester.runAsync(() async {
      final rows = await repository.loadEntries('#fp-isolated-proof');
      expect(rows.length, 1);
      expect(rows.single.verse, 7);
      await File(p.join(root.path, 'proof.txt')).writeAsString(
        'Actual popup ! button: Psalm 139:7 -> #fp-isolated-proof; one entry.\n',
      );
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => UserDatabase.instance.close());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    LibraryRootService.instance.invalidateCachedSelection();
  });
}
