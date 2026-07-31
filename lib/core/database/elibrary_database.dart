import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../bootstrap/sandbox_bootstrap.dart';
import 'elibrary_schema.dart';

const bool kLogKnownELibrarySqfliteFalsePositives = false;

class ELibraryDatabase {
  ELibraryDatabase._();

  static const _bundledAssetPath = 'assets/databases/eLibrary.db';

  static final ELibraryDatabase instance = ELibraryDatabase._();

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    SandboxBootstrap.ensureSqfliteInitializedOnce();
    if (_database != null) {
      return _database!;
    }
    _opening ??= _openDatabase();
    try {
      _database = await _opening!;
      _opening = null;
      return _database!;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    _opening = null;
    if (database != null) {
      await database.close();
    }
  }

  Future<Database> _openDatabase() async {
    final dbPath = await _ensureWritableDatabasePath();
    final db = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (database) async {
        await _executePragmaNonFatal(
          database,
          label: 'eLibrary.db',
          actionLabel: 'enabling WAL',
          sql: 'PRAGMA journal_mode=WAL',
          returnsRows: true,
        );
        await _executePragmaNonFatal(
          database,
          label: 'eLibrary.db',
          actionLabel: 'setting busy_timeout',
          sql: 'PRAGMA busy_timeout = 5000',
          returnsRows: true,
        );
      },
      onCreate: (database, version) async {
        await ELibrarySchema.ensure(database);
      },
      onOpen: (database) async {
        await ELibrarySchema.ensure(database);
      },
    );
    return db;
  }

  static Future<void> _executePragmaNonFatal(
    Database database, {
    required String label,
    required String actionLabel,
    required String sql,
    bool returnsRows = false,
  }) async {
    try {
      if (returnsRows) {
        await database.rawQuery(sql);
      } else {
        await database.execute(sql);
      }
      debugPrint('ELibraryDatabase[$label]: $actionLabel succeeded.');
    } on DatabaseException catch (error) {
      if (_isKnownWalFalsePositive(error)) {
        if (kLogKnownELibrarySqfliteFalsePositives) {
          debugPrint(
            'ELibraryDatabase[$label]: ignoring known sqflite false-positive '
            'while $actionLabel: $error',
          );
        }
        return;
      }
      rethrow;
    }
  }

  static bool _isKnownWalFalsePositive(DatabaseException error) {
    final message = error.toString();
    return message.contains('not an error') &&
        (message.contains('SqfliteDarwinDatabase') ||
            message.contains('SqfliteDatabase'));
  }

  Future<String> _ensureWritableDatabasePath() async {
    final writablePath = await SandboxBootstrap.eLibraryDatabasePath();
    final writableFile = File(writablePath);
    writableFile.parent.createSync(recursive: true);
    if (!writableFile.existsSync()) {
      debugPrint(
        'ELibraryDatabase: no DB found at $writablePath — '
        'copying from asset ($_bundledAssetPath).',
      );
      final copied = await _copyBundledAsset(writableFile);
      if (!copied) {
        debugPrint(
          'ELibraryDatabase: asset copy failed; creating empty schema at $writablePath.',
        );
        writableFile.createSync(recursive: true);
      } else {
        debugPrint(
          'ELibraryDatabase: asset copied successfully to $writablePath.',
        );
      }
    } else {
      debugPrint('ELibraryDatabase: using existing DB at $writablePath.');
    }
    return writablePath;
  }

  static Future<bool> _copyBundledAsset(File destination) async {
    try {
      final bytes = await rootBundle.load(_bundledAssetPath);
      final assetBytes = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      if (assetBytes.isEmpty) return false;
      destination.writeAsBytesSync(assetBytes, flush: true);
      return true;
    } catch (error) {
      debugPrint(
        'ELibraryDatabase: bundled eLibrary asset unavailable; '
        'creating a fresh schema instead. $error',
      );
      return false;
    }
  }
}
