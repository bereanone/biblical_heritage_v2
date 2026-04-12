import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../bootstrap/sandbox_bootstrap.dart';

class UserDatabase {
  UserDatabase._();

  static final UserDatabase instance = UserDatabase._();

  static const _dbName = 'user.db';

  Database? _database;

  Future<Database> get database async {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    await SandboxBootstrap.ensureReady();
    _database ??= await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await _ensureWritableUserDb();
    return openDatabase(dbPath);
  }

  Future<String> _ensureWritableUserDb() async {
    final writablePath = await SandboxBootstrap.userDatabasePath();
    final writableFile = File(writablePath);
    if (!writableFile.existsSync()) {
      final bytes = await _bundledUserDbBytes();
      writableFile.parent.createSync(recursive: true);
      writableFile.writeAsBytesSync(bytes, flush: true);
    }
    return writablePath;
  }

  Future<List<int>> _bundledUserDbBytes() async {
    final asset = await rootBundle.load('assets/databases/$_dbName');
    return asset.buffer.asUint8List();
  }
}
