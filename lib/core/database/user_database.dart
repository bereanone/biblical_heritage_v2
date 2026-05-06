import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../bootstrap/sandbox_bootstrap.dart';
import '../bootstrap/local_settings_store.dart';
import '../bootstrap/library_root_service.dart';
import 'user_v2_schema.dart';

class UserDatabase {
  UserDatabase._();

  static final UserDatabase instance = UserDatabase._();

  Database? _database;

  Future<Database> get database async {
    SandboxBootstrap.ensureSqfliteInitializedOnce();
    _database ??= await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await _ensureWritableUserDb();
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final db = await openDatabase(
      dbPath,
      version: 1,
      singleInstance: false,
      onCreate: (database, version) async {
        await UserV2Schema.ensure(database, deviceId: deviceId);
      },
      onOpen: (database) async {
        await UserV2Schema.ensure(database, deviceId: deviceId);
      },
    );
    await UserV2Schema.ensure(db, deviceId: deviceId);
    return db;
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
