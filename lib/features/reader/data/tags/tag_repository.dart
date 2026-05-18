import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'tag_models.dart';

typedef TagDatabaseProvider = Future<Database> Function();

abstract interface class TagRepository {
  Future<List<TagGroup>> loadGroups({required TagMode mode});

  Future<TagGroup?> loadDefaultGroup({required TagMode mode});

  Future<List<TagItem>> loadItems({
    required TagMode mode,
    required String groupId,
  });

  Future<List<TagItemMedia>> loadMedia({
    required TagMode mode,
    required String itemId,
  });
}
