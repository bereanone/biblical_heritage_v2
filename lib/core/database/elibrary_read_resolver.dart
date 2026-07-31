import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'elibrary_database.dart';
import 'user_database.dart';

enum ELibraryReadSource { eLibraryDb, userDbFallback, empty }

class ELibraryReadResult<T> {
  const ELibraryReadResult({
    required this.database,
    required this.value,
    required this.source,
  });

  final Database database;
  final T value;
  final ELibraryReadSource source;

  bool get usedELibraryDatabase => source == ELibraryReadSource.eLibraryDb;
  bool get usedUserDatabaseFallback =>
      source == ELibraryReadSource.userDbFallback;
}

class ELibraryReadResolver {
  ELibraryReadResolver._();

  static final ELibraryReadResolver instance = ELibraryReadResolver._();

  Future<Database> primaryDatabase() => ELibraryDatabase.instance.database;

  Future<Database> fallbackDatabase() => UserDatabase.instance.database;

  Future<bool> tableExists(Database db, String tableName) async {
    final rows = await db.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = ?
      LIMIT 1
      ''',
      [tableName],
    );
    return rows.isNotEmpty;
  }

  Future<int> tableRowCount(
    Database db,
    String tableName, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (!await tableExists(db, tableName)) {
      return 0;
    }
    final sql = StringBuffer('SELECT COUNT(*) AS cnt FROM "$tableName"');
    if (where != null && where.trim().isNotEmpty) {
      sql.write(' WHERE $where');
    }
    final rows = await db.rawQuery(sql.toString(), whereArgs ?? const []);
    return rows.isEmpty ? 0 : (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<bool> tableHasRows(
    Database db,
    String tableName, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    return (await tableRowCount(
          db,
          tableName,
          where: where,
          whereArgs: whereArgs,
        )) >
        0;
  }

  Future<ELibraryReadResult<T>> readWithFallback<T>({
    required Future<T> Function(Database db) read,
    required bool Function(T result) hasData,
    Future<Database>? fallbackDatabase,
  }) async {
    final primaryDb = await primaryDatabase();
    try {
      final primaryResult = await read(primaryDb);
      if (hasData(primaryResult)) {
        return ELibraryReadResult<T>(
          database: primaryDb,
          value: primaryResult,
          source: ELibraryReadSource.eLibraryDb,
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'ELibraryReadResolver: primary eLibrary read failed, falling back: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }

    final Database fallbackDb =
        await (fallbackDatabase ?? this.fallbackDatabase());
    final fallbackResult = await read(fallbackDb);
    final source = hasData(fallbackResult)
        ? ELibraryReadSource.userDbFallback
        : ELibraryReadSource.empty;
    return ELibraryReadResult<T>(
      database: fallbackDb,
      value: fallbackResult,
      source: source,
    );
  }
}
