import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/user_database.dart';

class ELibraryInstallEstimateRecord {
  const ELibraryInstallEstimateRecord({
    required this.collectionKey,
    required this.format,
    required this.fileCount,
    required this.totalSizeBytes,
    required this.sizeKnown,
    required this.lastCheckedUtc,
    required this.source,
  });

  final String collectionKey;
  final String format;
  final int fileCount;
  final int? totalSizeBytes;
  final bool sizeKnown;
  final DateTime? lastCheckedUtc;
  final String? source;

  factory ELibraryInstallEstimateRecord.fromRow(
    Map<String, Object?> row,
  ) {
    return ELibraryInstallEstimateRecord(
      collectionKey: row['collection_key']?.toString() ?? '',
      format: row['format']?.toString() ?? '',
      fileCount: (row['file_count'] as num?)?.toInt() ?? 0,
      totalSizeBytes: (row['total_size_bytes'] as num?)?.toInt(),
      sizeKnown: ((row['size_known'] as num?)?.toInt() ?? 0) != 0,
      lastCheckedUtc: DateTime.tryParse(
        row['last_checked_utc']?.toString() ?? '',
      ),
      source: row['source']?.toString(),
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
    'collection_key': collectionKey,
    'format': format,
    'file_count': fileCount,
    'total_size_bytes': totalSizeBytes,
    'size_known': sizeKnown ? 1 : 0,
    'last_checked_utc': lastCheckedUtc?.toIso8601String(),
    'source': source,
  };
}

class ELibraryInstallEstimateRepository {
  ELibraryInstallEstimateRepository._();

  static final ELibraryInstallEstimateRepository instance =
      ELibraryInstallEstimateRepository._();

  static const String tableName = 'elibrary_install_estimates';

  Future<Map<String, Map<String, ELibraryInstallEstimateRecord>>>
  loadByCollectionAndFormat() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      tableName,
      orderBy: 'collection_key ASC, format ASC',
    );
    final result = <String, Map<String, ELibraryInstallEstimateRecord>>{};
    for (final row in rows) {
      final record = ELibraryInstallEstimateRecord.fromRow(row);
      if (record.collectionKey.isEmpty || record.format.isEmpty) continue;
      result.putIfAbsent(record.collectionKey, () => <String, ELibraryInstallEstimateRecord>{})[record.format] = record;
    }
    return result;
  }

  Future<void> upsertCollectionCount({
    required String collectionKey,
    required String format,
    required int fileCount,
    int? totalSizeBytes,
    bool sizeKnown = false,
    String? source,
    DateTime? lastCheckedUtc,
  }) async {
    final db = await UserDatabase.instance.database;
    await db.insert(
      tableName,
      ELibraryInstallEstimateRecord(
        collectionKey: collectionKey,
        format: format,
        fileCount: fileCount,
        totalSizeBytes: totalSizeBytes,
        sizeKnown: sizeKnown,
        lastCheckedUtc: lastCheckedUtc ?? DateTime.now().toUtc(),
        source: source,
      ).toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertCollectionCountForBothFormats({
    required String collectionKey,
    required int fileCount,
    int? totalSizeBytes,
    bool sizeKnown = false,
    String? source,
    DateTime? lastCheckedUtc,
  }) async {
    final checkedAt = lastCheckedUtc ?? DateTime.now().toUtc();
    final db = await UserDatabase.instance.database;
    final batch = db.batch();
    for (final format in const ['epub', 'pdf']) {
      batch.insert(
        tableName,
        ELibraryInstallEstimateRecord(
          collectionKey: collectionKey,
          format: format,
          fileCount: fileCount,
          totalSizeBytes: totalSizeBytes,
          sizeKnown: sizeKnown,
          lastCheckedUtc: checkedAt,
          source: source,
        ).toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
