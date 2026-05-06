import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'library_root_service.dart';

class SandboxBootstrap {
  SandboxBootstrap._();

  static const _bibleDbName = 'bible_base.db';
  static const _userDbName = 'user.db';
  static bool _sqfliteInitialized = false;

  static Future<String> bibleDatabasePath() async {
    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'databases', _bibleDbName);
  }

  static Future<String> userDatabasePath() async {
    final root = await LibraryRootService.instance.accessibleLibraryRootPath();
    if (root != null) {
      return p.join(root, 'Databases', _userDbName);
    }
    return legacyV2UserDatabasePath();
  }

  static Future<String> legacyV2UserDatabasePath() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, 'BiblicalHeritage', 'v2', _userDbName);
  }

  static Future<String> legacyUserDatabasePath() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, _userDbName);
  }

  static Future<String> legacyDocumentsUserDatabasePath() async {
    return legacyUserDatabasePath();
  }

  static Future<String> legacySupportUserDatabasePath() async {
    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'databases', _userDbName);
  }

  static void ensureSqfliteInitializedOnce() {
    if (_sqfliteInitialized || !_isDesktopPlatform) {
      return;
    }
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _sqfliteInitialized = true;
  }

  static Future<void> ensureBibleReady({ValueChanged<String>? onStatus}) async {
    ensureSqfliteInitializedOnce();

    onStatus?.call('Preparing database sandbox...');
    final supportDir = await getApplicationSupportDirectory();
    final supportDbDir = Directory(p.join(supportDir.path, 'databases'));
    if (!supportDbDir.existsSync()) {
      supportDbDir.createSync(recursive: true);
    }

    final biblePath = await bibleDatabasePath();
    onStatus?.call('Materializing Bible database...');
    await _ensureAssetFile(
      assetPath: 'assets/databases/$_bibleDbName',
      destinationPath: biblePath,
    );

    onStatus?.call('Validating sandbox...');
    await _touchDatabase(
      biblePath,
      assetPath: 'assets/databases/$_bibleDbName',
    );
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
    file.writeAsBytesSync(assetBytes, flush: true);
  }

  static Future<void> _touchDatabase(
    String path, {
    String? assetPath,
  }) async {
    try {
      final db = await openDatabase(path, singleInstance: false);
      await db.close();
      return;
    } catch (_) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      if (assetPath != null) {
        await _ensureAssetFile(assetPath: assetPath, destinationPath: path);
      }
      final db = await openDatabase(path, singleInstance: false);
      await db.close();
    }
  }

  static bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
}
