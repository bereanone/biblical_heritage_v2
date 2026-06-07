import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../bootstrap/sandbox_bootstrap.dart';
import '../bootstrap/local_settings_store.dart';
import '../bootstrap/library_root_service.dart';
import 'user_v2_schema.dart';

const bool kLogKnownSqfliteFalsePositives = false;

class UserDatabase {
  UserDatabase._();

  static final UserDatabase instance = UserDatabase._();

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    SandboxBootstrap.ensureSqfliteInitializedOnce();
    if (_database != null) return _database!;
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

  Future<Database> _openDatabase() async {
    final dbPath = await _ensureWritableUserDb();
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final db = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (database) async {
        await _executePragmaNonFatal(
          database,
          label: 'user.db',
          actionLabel: 'enabling WAL',
          sql: 'PRAGMA journal_mode=WAL',
        );
        await _executePragmaNonFatal(
          database,
          label: 'user.db',
          actionLabel: 'setting busy_timeout',
          sql: 'PRAGMA busy_timeout = 5000',
        );
      },
      onCreate: (database, version) async {
        await UserV2Schema.ensure(database, deviceId: deviceId);
      },
      onOpen: (database) async {
        await UserV2Schema.ensure(database, deviceId: deviceId);
      },
    );
    return db;
  }

  static Future<void> _executePragmaNonFatal(
    Database database, {
    required String label,
    required String actionLabel,
    required String sql,
  }) async {
    try {
      await database.execute(sql);
      debugPrint('UserDatabase[$label]: $actionLabel succeeded.');
    } on DatabaseException catch (error) {
      if (_isKnownWalFalsePositive(error)) {
        if (kLogKnownSqfliteFalsePositives) {
          debugPrint(
            'UserDatabase[$label]: ignoring known sqflite false-positive while '
            '$actionLabel: '
            '$error',
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

  Future<String> _ensureWritableUserDb() async {
    final writablePath = await SandboxBootstrap.userDatabasePath();
    final writableFile = File(writablePath);
    if (!writableFile.existsSync()) {
      writableFile.parent.createSync(recursive: true);
      final selection = await LibraryRootService.instance.loadSelection();
      final legacyPath = await SandboxBootstrap.legacyV2UserDatabasePath();
      final legacyFile = File(legacyPath);
      if (selection.path != null &&
          selection.exists &&
          writablePath != legacyPath &&
          await legacyFile.exists() &&
          legacyFile.lengthSync() > 0) {
        await LibraryRootService.instance.ensureStructure(selection.path);
        await legacyFile.copy(writablePath);
      } else {
        writableFile.createSync(recursive: true);
      }
    }
    return writablePath;
  }
}
