import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _sourceDb = '/Users/deanbowen/Development/eLibrary/Databases/user.db';
const _targetDb =
    '/Users/deanbowen/Library/Containers/com.example.studybible2/Data/Documents/BiblicalHeritage/v2/user.db';
const _sourceMediaRoot = '/Users/deanbowen/Development/eLibrary';
const _targetMediaRoot =
    '/Users/deanbowen/Library/Containers/com.example.studybible2/Data/Documents/BiblicalHeritage/v2';
const _tags = <String>['#Test2', '#Test4', '#Test5'];
const _packageId = 'legacy_import_eLibrary_user_db';

typedef DbRow = Map<String, Object?>;

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final apply = args.contains('--apply');
  final report = await LegacyTagImporter().run(apply: apply);
  stdout.writeln(report);
}

class LegacyTagImporter {
  Future<String> run({required bool apply}) async {
    final sourceDb = await openDatabase(_sourceDb, readOnly: true, singleInstance: false);
    final targetDb = await openDatabase(_targetDb, singleInstance: false);
    try {
      final sourceRows = await _loadSourceRows(sourceDb);
      final sourceMediaRows = await _loadSourceMediaRows(
        sourceDb,
        sourceRows.map((row) => _i(row['id'])!).toList(growable: false),
      );
      final targetGroups = await _loadTargetGroups(targetDb);
      final targetItems = await _loadTargetItems(targetDb);
      final targetMediaRows = await _loadTargetMediaRows(targetDb);
      final plan = _buildPlan(
        sourceRows: sourceRows,
        sourceMediaRows: sourceMediaRows,
        targetGroups: targetGroups,
        targetItems: targetItems,
        targetMediaRows: targetMediaRows,
      );
      if (apply && plan.conflicts.isEmpty) {
        await _apply(targetDb, plan);
      }
      return _report(
        apply: apply,
        sourceRows: sourceRows,
        sourceMediaRows: sourceMediaRows,
        targetGroups: targetGroups,
        targetItems: targetItems,
        plan: plan,
      );
    } finally {
      await sourceDb.close();
      await targetDb.close();
    }
  }

  Future<List<DbRow>> _loadSourceRows(Database db) async {
    return db.query(
      'hash_tags',
      columns: const [
        'id',
        'user_id',
        'tag',
        'category',
        'verse_ref',
        'book_number',
        'chapter_number',
        'verse_number',
        'token_number',
        'created_at',
        'sort_order',
        'created_at_utc',
        'updated_at_utc',
        'deleted_at_utc',
        'device_id',
        'revision',
        'sync_status',
        'last_synced_at',
        'reference_code',
        'note_text',
        'note_format_json',
        'presentation_slide_number',
      ],
      where: 'tag IN (${List.filled(_tags.length, '?').join(', ')})',
      whereArgs: _tags,
      orderBy: 'tag COLLATE NOCASE ASC, COALESCE(sort_order, created_at) ASC, id ASC',
    );
  }

  Future<List<DbRow>> _loadSourceMediaRows(Database db, List<int> itemIds) async {
    if (itemIds.isEmpty) return const <DbRow>[];
    return db.query(
      'tag_item_media',
      columns: const [
        'id',
        'tag_item_id',
        'media_type',
        'relative_path',
        'caption',
        'file_hash',
        'file_size',
        'sort_order',
        'source_device_name',
        'legacy_group_id',
        'legacy_item_id',
        'legacy_import_package_id',
        'imported_at',
        'created_at',
        'updated_at',
        'deleted_at',
        'device_id',
        'revision',
        'sync_status',
        'last_synced_at',
        'change_id',
      ],
      where: 'tag_item_id IN (${List.filled(itemIds.length, '?').join(', ')})',
      whereArgs: [for (final id in itemIds) id.toString()],
      orderBy: 'tag_item_id ASC, sort_order ASC, id ASC',
    );
  }

  Future<List<DbRow>> _loadTargetGroups(Database db) async {
    return db.query(
      'tag_groups',
      columns: const ['id', 'tag_kind', 'name', 'sort_order', 'legacy_import_package_id', 'legacy_group_id', 'legacy_item_id', 'change_id'],
      where: 'tag_kind = ? AND name IN (${List.filled(_tags.length, '?').join(', ')})',
      whereArgs: ['hash', ..._tags],
    );
  }

  Future<List<DbRow>> _loadTargetItems(Database db) async {
    return db.query(
      'tag_items',
      columns: const ['id', 'tag_group_id', 'legacy_import_package_id', 'legacy_item_id', 'change_id', 'sort_order'],
      where: 'legacy_import_package_id = ?',
      whereArgs: [_packageId],
    );
  }

  Future<List<DbRow>> _loadTargetMediaRows(Database db) async {
    return db.query(
      'tag_item_media',
      columns: const ['id', 'tag_item_id', 'relative_path', 'file_hash', 'file_size', 'legacy_import_package_id', 'legacy_item_id', 'change_id'],
      where: 'legacy_import_package_id = ?',
      whereArgs: [_packageId],
    );
  }

  Plan _buildPlan({
    required List<DbRow> sourceRows,
    required List<DbRow> sourceMediaRows,
    required List<DbRow> targetGroups,
    required List<DbRow> targetItems,
    required List<DbRow> targetMediaRows,
  }) {
    final sourceByTag = <String, List<DbRow>>{};
    for (final row in sourceRows) {
      sourceByTag.putIfAbsent(_s(row['tag']), () => <DbRow>[]).add(row);
    }

    final targetGroupByName = {for (final row in targetGroups) _s(row['name']): row};
    final targetItemByLegacy = {
      for (final row in targetItems) '${_s(row['legacy_import_package_id'])}|${_s(row['legacy_item_id'])}': row,
    };
    final targetMediaByLegacy = {
      for (final row in targetMediaRows) '${_s(row['legacy_import_package_id'])}|${_s(row['legacy_item_id'])}|${_s(row['file_hash'])}': row,
    };

    final groupPlans = <GroupPlan>[];
    final itemPlans = <ItemPlan>[];
    final mediaPlans = <MediaPlan>[];
    final conflicts = <String>[];
    var nextGroupOrder = _maxInt(targetGroups, 'sort_order') + 1;
    var nextItemOrder = _maxInt(targetItems, 'sort_order') + 1;

    for (final tag in _tags) {
      final rows = sourceByTag[tag] ?? const <DbRow>[];
      final existingGroup = targetGroupByName[tag];
      final groupId = existingGroup?['id']?.toString() ?? _groupId(tag);
      final groupRow = existingGroup ??
          <String, Object?>{
            'id': groupId,
            'parent_group_id': null,
            'tag_kind': 'hash',
            'name': tag,
            'description': null,
            'sort_order': nextGroupOrder++,
            'source_device_name': 'Development eLibrary',
            'legacy_group_id': tag,
            'legacy_item_id': null,
            'legacy_import_package_id': _packageId,
            'imported_at': _isoForRows(rows),
            'created_at': _isoForRows(rows, first: true),
            'updated_at': _isoForRows(rows),
            'deleted_at': null,
            'device_id': 'legacy_import',
            'revision': 1,
            'sync_status': 'pending',
            'last_synced_at': null,
            'change_id': _groupChangeId(tag),
          };
      groupPlans.add(
        GroupPlan(tag: tag, create: existingGroup == null, groupId: groupId, row: groupRow),
      );

      for (final row in rows) {
        final sourceId = _i(row['id'])!;
        final itemKey = '$_packageId|$sourceId';
        final existingItem = targetItemByLegacy[itemKey];
        final itemId = existingItem?['id']?.toString() ?? _itemId(tag, sourceId);
        final itemRow = existingItem ??
            <String, Object?>{
              'id': itemId,
              'tag_group_id': groupId,
              'tag_kind': 'hash',
              'book_id': _i(row['book_number']) ?? 0,
              'chapter': _i(row['chapter_number']) ?? 0,
              'verse_start': _i(row['verse_number']) ?? 0,
              'verse_end': _i(row['verse_number']) ?? 0,
              'note_text': _n(row['note_text']),
              'sort_order': _i(row['sort_order']) ?? _i(row['created_at']) ?? nextItemOrder++,
              'source_device_name': 'Development eLibrary',
              'legacy_group_id': tag,
              'legacy_item_id': sourceId.toString(),
              'legacy_import_package_id': _packageId,
              'imported_at': _isoForRow(row),
              'created_at': _isoForRow(row),
              'updated_at': _isoForRow(row),
              'deleted_at': null,
              'device_id': _s(row['device_id']).isEmpty ? 'legacy_import' : row['device_id'],
              'revision': _i(row['revision']) ?? 1,
              'sync_status': _s(row['sync_status']).trim().isEmpty ? 'pending' : row['sync_status'],
              'last_synced_at': _n(row['last_synced_at']),
              'change_id': _itemChangeId(tag, sourceId),
            };
        itemPlans.add(
          ItemPlan(tag: tag, sourceRow: row, create: existingItem == null, itemId: itemId, row: itemRow),
        );

        final itemMediaRows = sourceMediaRows.where((media) => _i(media['tag_item_id']) == sourceId).toList(growable: false);
        for (final media in itemMediaRows) {
          final mediaKey = '$_packageId|$sourceId|${_s(media['file_hash'])}';
          final existingMedia = targetMediaByLegacy[mediaKey];
          final relativePath = _s(media['relative_path']);
          final sourcePath = p.join(_sourceMediaRoot, relativePath);
          final targetPath = p.join(_targetMediaRoot, relativePath);
          final sourceExists = File(sourcePath).existsSync();
          final targetExists = File(targetPath).existsSync();
          final targetMatches = targetExists &&
              _hashOfFile(targetPath) == _s(media['file_hash']) &&
              File(targetPath).lengthSync() == (_i(media['file_size']) ?? 0);
          final conflict = !sourceExists || (targetExists && !targetMatches && existingMedia == null);
          if (conflict) {
            conflicts.add('Media conflict for $tag row $sourceId: $relativePath');
          }
          mediaPlans.add(
            MediaPlan(
              tag: tag,
              sourceRow: media,
              create: existingMedia == null,
              copy: existingMedia == null && sourceExists && !targetMatches,
              skipCopy: existingMedia != null || targetMatches,
              conflict: conflict,
              itemId: itemId,
              targetPath: targetPath,
              row: existingMedia ??
                  <String, Object?>{
                    'id': _mediaId(tag, sourceId, media),
                    'tag_item_id': itemId,
                    'media_type': _s(media['media_type']).isEmpty ? 'image' : media['media_type'],
                    'relative_path': relativePath,
                    'caption': _n(media['caption']),
                    'file_hash': _n(media['file_hash']),
                    'file_size': _i(media['file_size']),
                    'sort_order': _i(media['sort_order']) ?? 0,
                    'source_device_name': _n(media['source_device_name']) ?? 'Development eLibrary',
                    'legacy_group_id': tag,
                    'legacy_item_id': sourceId.toString(),
                    'legacy_import_package_id': _packageId,
                    'imported_at': _isoForRow(row),
                    'created_at': _isoForMedia(media),
                    'updated_at': _isoForMedia(media),
                    'deleted_at': null,
                    'device_id': _s(media['device_id']).isEmpty ? 'legacy_import' : media['device_id'],
                    'revision': _i(media['revision']) ?? 1,
                    'sync_status': _s(media['sync_status']).trim().isEmpty ? 'pending' : media['sync_status'],
                    'last_synced_at': _n(media['last_synced_at']),
                    'change_id': _mediaChangeId(tag, sourceId, media),
                  },
            ),
          );
        }
      }
    }

    return (groupPlans: groupPlans, itemPlans: itemPlans, mediaPlans: mediaPlans, conflicts: conflicts);
  }

  Future<void> _apply(Database db, Plan plan) async {
    final copied = <String>[];
    try {
      for (final media in plan.mediaPlans.where((m) => m.copy)) {
        final sourcePath = p.join(_sourceMediaRoot, _s(media.row['relative_path']));
        await File(sourcePath).copy(media.targetPath);
        copied.add(media.targetPath);
        final bytes = await File(media.targetPath).readAsBytes();
        if (_hashOfBytes(bytes) != _s(media.row['file_hash']) ||
            bytes.length != (_i(media.row['file_size']) ?? 0)) {
          throw StateError('Copied media verification failed for ${media.row['relative_path']}');
        }
      }
      await db.transaction((txn) async {
        for (final group in plan.groupPlans.where((g) => g.create)) {
          await txn.insert('tag_groups', group.row);
        }
        for (final item in plan.itemPlans.where((i) => i.create)) {
          await txn.insert('tag_items', item.row);
        }
        for (final media in plan.mediaPlans.where((m) => m.create)) {
          await txn.insert('tag_item_media', media.row);
        }
      });
    } catch (_) {
      for (final path in copied.reversed) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // Best effort only.
        }
      }
      rethrow;
    }
  }

  String _report({
    required bool apply,
    required List<DbRow> sourceRows,
    required List<DbRow> sourceMediaRows,
    required List<DbRow> targetGroups,
    required List<DbRow> targetItems,
    required Plan plan,
  }) {
    final out = StringBuffer();
    out.writeln('== Legacy #tag Import ==');
    out.writeln('Mode: ${apply ? 'apply' : 'dry-run'}');
    out.writeln('Source DB: $_sourceDb');
    out.writeln('Target DB: $_targetDb');
    out.writeln('Source media: $_sourceMediaRoot/Media/tag_content');
    out.writeln('Target media: $_targetMediaRoot/Media/tag_content');
    out.writeln('');
    out.writeln('Tag | Source rows | Target groups | Target items | Media rows | Image files exist | Status');
    for (final tag in _tags) {
      final sRows = sourceRows.where((row) => _s(row['tag']) == tag).toList(growable: false);
      final gPlan = plan.groupPlans.firstWhere((group) => group.tag == tag);
      final iPlans = plan.itemPlans.where((item) => item.tag == tag).toList(growable: false);
      final mPlans = plan.mediaPlans.where((media) => media.tag == tag).toList(growable: false);
      final targetGroupCount = targetGroups.where((row) => _s(row['name']) == tag).length + (gPlan.create ? 1 : 0);
      final targetItemCount = targetItems.where((row) => _s(row['legacy_import_package_id']) == _packageId && _s(row['legacy_group_id']) == tag).length + iPlans.where((item) => item.create).length;
      final filesExist = mPlans.isEmpty
          ? 'n/a'
          : mPlans.every((media) => File(p.join(_sourceMediaRoot, _s(media.row['relative_path']))).existsSync())
              ? 'yes'
              : 'no';
      out.writeln(
        '$tag | ${sRows.length} | $targetGroupCount | $targetItemCount | ${mPlans.length} | $filesExist | '
        '${gPlan.create || iPlans.any((item) => item.create) ? 'pending import' : 'already imported'}',
      );
      for (final row in sRows) {
        out.writeln('  source row ${_i(row['id'])}: ${_rowPreview(row)}');
      }
      out.writeln('  group: ${gPlan.create ? 'create' : 'reuse'} id=${gPlan.groupId}');
      for (final item in iPlans) {
        out.writeln(
          '  item: ${item.create ? 'create' : 'skip'} id=${item.itemId} legacy_item_id=${_i(item.sourceRow['id'])} '
          'book=${_i(item.row['book_id'])} chapter=${_i(item.row['chapter'])} '
          'verse=${_i(item.row['verse_start'])}-${_i(item.row['verse_end'])} note=${_n(item.row['note_text']) ?? ''}',
        );
      }
      for (final media in mPlans) {
        out.writeln(
          '  media: ${media.create ? (media.copy ? 'copy+insert' : 'insert') : 'skip'} '
          '${media.relativePath} -> ${media.targetPath} hash=${_n(media.row['file_hash'])} size=${_i(media.row['file_size'])}',
        );
      }
    }
    out.writeln('');
    out.writeln('Would create groups: ${plan.groupPlans.where((group) => group.create).length}');
    out.writeln('Would create items: ${plan.itemPlans.where((item) => item.create).length}');
    out.writeln('Would create media rows: ${plan.mediaPlans.where((media) => media.create).length}');
    out.writeln('Would copy media files: ${plan.mediaPlans.where((media) => media.copy).length}');
    out.writeln('Rerun idempotent: ${plan.conflicts.isEmpty ? 'yes' : 'no'}');
    if (plan.conflicts.isNotEmpty) {
      out.writeln('Conflicts:');
      for (final conflict in plan.conflicts) {
        out.writeln('  $conflict');
      }
    }
    return out.toString();
  }

  String _groupId(String tag) => 'legacy_import_hash_${_slug(tag)}';
  String _itemId(String tag, int sourceId) => 'legacy_import_hash_${_slug(tag)}_$sourceId';
  String _mediaId(String tag, int sourceId, DbRow media) =>
      'legacy_import_hash_${_slug(tag)}_${sourceId}_${_slug(_s(media['relative_path']))}_${_slug(_s(media['file_hash']))}';
  String _groupChangeId(String tag) => 'legacy-import:${_slug(_sourceDb)}:group:${_slug(tag)}';
  String _itemChangeId(String tag, int sourceId) => 'legacy-import:${_slug(_sourceDb)}:item:${_slug(tag)}:$sourceId';
  String _mediaChangeId(String tag, int sourceId, DbRow media) =>
      'legacy-import:${_slug(_sourceDb)}:media:${_slug(tag)}:$sourceId:${_slug(_s(media['file_hash']))}';
  String _rowPreview(DbRow row) =>
      '${_s(row['tag'])} | ${_s(row['verse_ref'])} | sort=${_i(row['sort_order']) ?? _i(row['created_at']) ?? 0} | '
      'note=${_n(row['note_text']) ?? ''} | ref=${_n(row['reference_code']) ?? ''} | slide=${_i(row['presentation_slide_number']) ?? ''}';

  String _isoForRows(List<DbRow> rows, {bool first = false}) {
    if (rows.isEmpty) return DateTime.now().toUtc().toIso8601String();
    return _isoForRow(first ? rows.first : rows.last);
  }

  String _isoForRow(DbRow row) {
    final utc = _n(row['created_at_utc']) ?? _n(row['updated_at_utc']);
    if (utc != null) return utc;
    final created = _i(row['created_at']) ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(created, isUtc: true).toIso8601String();
  }

  String _isoForMedia(DbRow row) => _isoForRow(row);

  int _maxInt(List<DbRow> rows, String column) {
    var max = 0;
    for (final row in rows) {
      final value = _i(row[column]);
      if (value != null && value > max) max = value;
    }
    return max;
  }

  String _hashOfFile(String path) => _hashOfBytes(File(path).readAsBytesSync());
  String _hashOfBytes(List<int> bytes) => sha256.convert(bytes).toString();

  String _s(Object? value) => value?.toString() ?? '';
  String? _n(Object? value) {
    final text = _s(value).trim();
    return text.isEmpty ? null : text;
  }

  int? _i(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  String _slug(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

typedef Plan = ({
  List<GroupPlan> groupPlans,
  List<ItemPlan> itemPlans,
  List<MediaPlan> mediaPlans,
  List<String> conflicts,
});

class GroupPlan {
  GroupPlan({
    required this.tag,
    required this.create,
    required this.groupId,
    required this.row,
  });

  final String tag;
  final bool create;
  final String groupId;
  final DbRow row;
}

class ItemPlan {
  ItemPlan({
    required this.tag,
    required this.sourceRow,
    required this.create,
    required this.itemId,
    required this.row,
  });

  final String tag;
  final DbRow sourceRow;
  final bool create;
  final String itemId;
  final DbRow row;
}

class MediaPlan {
  MediaPlan({
    required this.tag,
    required this.sourceRow,
    required this.create,
    required this.copy,
    required this.skipCopy,
    required this.conflict,
    required this.itemId,
    required this.targetPath,
    required this.row,
  });

  final String tag;
  final DbRow sourceRow;
  final bool create;
  final bool copy;
  final bool skipCopy;
  final bool conflict;
  final String itemId;
  final String targetPath;
  final DbRow row;

  String get relativePath => row['relative_path']?.toString() ?? '';
}
