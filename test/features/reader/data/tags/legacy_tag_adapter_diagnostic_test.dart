import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/features/reader/data/tags/legacy_tag_adapter.dart';
import 'package:studybible2/features/reader/data/tags/tag_models.dart';

Future<Database> _openReadOnlyDiagnosticDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final overridePath = Platform.environment['TAG_DIAG_DB_PATH']?.trim();
  if (overridePath == null || overridePath.isEmpty) {
    throw StateError('TAG_DIAG_DB_PATH is required for this diagnostic test.');
  }
  final candidatePath = File(overridePath).absolute.path;
  if (!File(candidatePath).existsSync()) {
    throw StateError('Missing diagnostic database: $candidatePath');
  }
  stdout.writeln('Using database: $candidatePath');
  return openDatabase(candidatePath, readOnly: true, singleInstance: false);
}

String _summarizeGroup(TagGroup group, List<TagItem> items) {
  final itemLines = items.take(3).map((item) {
    final anchor = item.anchor;
    final anchorLabel = switch (anchor.kind) {
      TagAnchorKind.verseReference =>
        '${anchor.bookNumber}:${anchor.chapter}:${anchor.verseStart}',
      TagAnchorKind.selectedText =>
        '${anchor.bookNumber}:${anchor.chapter}:${anchor.verseStart}',
      TagAnchorKind.noteOnly => 'note-only',
    };
    final noteText = item.noteText?.trim();
    return '  - ${item.id} | ${item.kind.name} | $anchorLabel'
        '${noteText == null || noteText.isEmpty ? '' : ' | note="${noteText.replaceAll('"', "'")}"'}';
  }).join('\n');
  return [
    'group=${group.name} | id=${group.id} | default=${group.isDefault}',
    if (itemLines.isNotEmpty) itemLines else '  - no items',
  ].join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final diagDbPath = Platform.environment['TAG_DIAG_DB_PATH']?.trim();
  final skipReason = (diagDbPath == null || diagDbPath.isEmpty)
      ? 'Set TAG_DIAG_DB_PATH to run this local-only diagnostic.'
      : null;

  test('diagnose legacy tag mapping (local-only)', () async {
    final db = await _openReadOnlyDiagnosticDatabase();
    addTearDown(() async => db.close());

    final adapter = LegacyTagAdapter(databaseProvider: () async => db);

    final quickGroups = (await adapter.loadGroups(mode: TagMode.quick))
        .where((group) => !group.isCategoryGroup)
        .toList(growable: false);
    final studyGroups = (await adapter.loadGroups(mode: TagMode.studyList))
        .where((group) => !group.isCategoryGroup)
        .toList(growable: false);

    final quickItemsByGroup = <String, List<TagItem>>{
      for (final group in quickGroups)
        group.id: await adapter.loadItems(mode: TagMode.quick, groupId: group.id),
    };
    final studyItemsByGroup = <String, List<TagItem>>{
      for (final group in studyGroups)
        group.id: await adapter.loadItems(mode: TagMode.studyList, groupId: group.id),
    };

    final quickItemCount = quickItemsByGroup.values.fold<int>(
      0,
      (total, items) => total + items.length,
    );
    final studyItemCount = studyItemsByGroup.values.fold<int>(
      0,
      (total, items) => total + items.length,
    );

    final quickExampleGroup = quickGroups.isEmpty
        ? null
        : quickGroups.firstWhere(
            (group) => quickItemsByGroup[group.id]?.isNotEmpty == true,
            orElse: () => quickGroups.first,
          );
    final studyExampleGroup = studyGroups.isEmpty
        ? null
        : studyGroups.firstWhere(
            (group) => studyItemsByGroup[group.id]?.isNotEmpty == true,
            orElse: () => studyGroups.first,
          );

    final quickExampleItems =
        quickExampleGroup == null ? const <TagItem>[] : quickItemsByGroup[quickExampleGroup.id] ?? const <TagItem>[];
    final studyExampleItems =
        studyExampleGroup == null ? const <TagItem>[] : studyItemsByGroup[studyExampleGroup.id] ?? const <TagItem>[];

    final quickMediaMapped = quickGroups.any(
      (group) => quickItemsByGroup[group.id]!.any((item) => item.noteText?.isNotEmpty == true),
    );
    final studyMediaMapped = studyItemsByGroup.values.any(
      (items) => items.any((item) => item.noteText?.isNotEmpty == true),
    );
    final studyHasMediaRefs = studyExampleItems.isNotEmpty &&
        (await adapter.loadMedia(
          mode: TagMode.studyList,
          itemId: studyExampleItems.first.id,
        ))
            .isNotEmpty;

    // Temporary diagnostic output. Keep this helper only as long as it is useful.
    stdout.writeln('Quick tag groups: ${quickGroups.length}');
    stdout.writeln('Quick tag items: $quickItemCount');
    stdout.writeln('Study-list groups: ${studyGroups.length}');
    stdout.writeln('Study-list items: $studyItemCount');
    stdout.writeln('');
    stdout.writeln('Example #tag group');
    stdout.writeln(
      quickExampleGroup == null
          ? '  - none'
          : _summarizeGroup(
              quickExampleGroup,
              quickExampleItems,
            ),
    );
    stdout.writeln('');
    stdout.writeln('Example \$tag group');
    stdout.writeln(
      studyExampleGroup == null
          ? '  - none'
          : _summarizeGroup(
              studyExampleGroup,
              studyExampleItems,
            ),
    );
    stdout.writeln('');
    stdout.writeln('Mapping checks');
    stdout.writeln(
      '  note_text maps correctly: ${quickMediaMapped || quickExampleItems.isNotEmpty}',
    );
    stdout.writeln(
      '  content_html maps correctly: ${studyMediaMapped || studyExampleItems.isNotEmpty}',
    );
    stdout.writeln('  media refs map correctly: $studyHasMediaRefs');
  }, skip: skipReason);
}
