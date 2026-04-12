import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SandboxBootstrap {
  SandboxBootstrap._();

  static const _bibleDbName = 'bible_base.db';
  static const _userDbName = 'user.db';
  static const _initializedKey = 'sandbox_initialized';
  static Future<void>? _ensureFuture;

  static Future<String> bibleDatabasePath() async {
    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'databases', _bibleDbName);
  }

  static Future<String> userDatabasePath() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, _userDbName);
  }

  static Future<String> legacyUserDatabasePath() async {
    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'databases', _userDbName);
  }

  static Future<bool> needsInteractiveBootstrap() async {
    final biblePath = await bibleDatabasePath();
    final userPath = await userDatabasePath();

    final bibleFile = File(biblePath);
    final userFile = File(userPath);
    if (!bibleFile.existsSync() || !userFile.existsSync()) {
      return true;
    }

    if (_isDesktopPlatform) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final db = await openDatabase(userPath, readOnly: true);
    try {
      final rows = await db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [_initializedKey],
        limit: 1,
      );
      if (rows.isEmpty) return true;
      final value = rows.first['value']?.toString() ?? '';
      return value != '1';
    } catch (_) {
      return true;
    } finally {
      await db.close();
    }
  }

  static Future<void> ensureReady({
    ValueChanged<String>? onStatus,
  }) async {
    _ensureFuture ??= _ensureReadyImpl(onStatus: onStatus);
    try {
      await _ensureFuture;
    } catch (_) {
      _ensureFuture = null;
      rethrow;
    }
  }

  static Future<void> _ensureReadyImpl({
    ValueChanged<String>? onStatus,
  }) async {
    if (_isDesktopPlatform) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    onStatus?.call('Preparing database sandbox...');
    final supportDir = await getApplicationSupportDirectory();

    final supportDbDir = Directory(p.join(supportDir.path, 'databases'));
    if (!supportDbDir.existsSync()) {
      supportDbDir.createSync(recursive: true);
    }

    final biblePath = await bibleDatabasePath();
    final userPath = await userDatabasePath();
    final legacyUserPath = await legacyUserDatabasePath();

    onStatus?.call('Materializing Bible database...');
    await _ensureAssetFile(
      assetPath: 'assets/databases/$_bibleDbName',
      destinationPath: biblePath,
    );

    onStatus?.call('Preparing user data...');
    await _ensureUserDb(
      userPath: userPath,
      legacyUserPath: legacyUserPath,
    );

    onStatus?.call('Validating sandbox...');
    await _touchDatabase(biblePath);
    await _touchDatabase(userPath);
    await _markInitialized(userPath);
  }

  static Future<void> _ensureAssetFile({
    required String assetPath,
    required String destinationPath,
  }) async {
    final file = File(destinationPath);
    final bytes = await rootBundle.load(assetPath);
    final assetBytes = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    if (file.existsSync() &&
        file.lengthSync() == assetBytes.length &&
        file.lengthSync() > 0) {
      return;
    }
    file.writeAsBytesSync(
      assetBytes,
      flush: true,
    );
  }

  static Future<void> _ensureUserDb({
    required String userPath,
    required String legacyUserPath,
  }) async {
    final userFile = File(userPath);
    if (userFile.existsSync() && userFile.lengthSync() > 0) {
      return;
    }

    userFile.parent.createSync(recursive: true);

    final legacyFile = File(legacyUserPath);
    if (legacyFile.existsSync() && legacyFile.lengthSync() > 0) {
      legacyFile.copySync(userPath);
      return;
    }

    final bytes = await rootBundle.load('assets/databases/$_userDbName');
    userFile.writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
  }

  static Future<void> _touchDatabase(String path) async {
    final db = await openDatabase(path, singleInstance: false);
    await db.close();
  }

  static Future<void> _markInitialized(String userPath) async {
    final db = await openDatabase(userPath, singleInstance: false);
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
      await db.insert(
        'app_settings',
        {'key': _initializedKey, 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } finally {
      await db.close();
    }
  }

  static bool get _isDesktopPlatform =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
}
