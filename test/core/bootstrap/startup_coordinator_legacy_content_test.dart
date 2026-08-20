import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/sandbox_bootstrap.dart';
import 'package:studybible2/core/bootstrap/startup_coordinator.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/database/user_v2_schema.dart';

Future<void> _installPathProviderMocks({
  required Directory supportDir,
  required Directory documentsDir,
}) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getApplicationSupportDirectory':
            return supportDir.path;
          case 'getApplicationDocumentsDirectory':
            return documentsDir.path;
          case 'getTemporaryDirectory':
            return supportDir.path;
          case 'getLibraryDirectory':
            return supportDir.path;
        }
        return supportDir.path;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'startup_legacy_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'startup_legacy_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'startup_legacy_library_',
    );
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    await LocalSettingsStore.instance.ensureDeviceId();
    await LocalSettingsStore.instance.clearPioneerCapturedHtmlFolder();
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await UserDatabase.instance.close();
    await ELibraryDatabase.instance.close();
    if (supportDir.existsSync()) {
      await supportDir.delete(recursive: true);
    }
    if (documentsDir.existsSync()) {
      await documentsDir.delete(recursive: true);
    }
    if (libraryRootDir.existsSync()) {
      await libraryRootDir.delete(recursive: true);
    }
  });

  Future<void> createLegacyDatabase({required bool withRealContent}) async {
    final legacyPath = await SandboxBootstrap.legacyUserDatabasePath();
    await Directory(File(legacyPath).parent.path).create(recursive: true);
    final db = await databaseFactory.openDatabase(legacyPath);
    await UserV2Schema.ensure(db, deviceId: 'legacy-test-device');
    if (withRealContent) {
      await db.insert('hash_tags', <String, Object?>{
        'user_id': 1,
        'tag': 'Grace',
        'verse_ref': 'John 1:1',
        'book_number': 43,
        'chapter_number': 1,
        'verse_number': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    await db.close();
  }

  test(
    'a legacy user.db with no real content is treated as no legacy data',
    () async {
      await createLegacyDatabase(withRealContent: false);

      final snapshot = await StartupCoordinator.instance.initialize();

      expect(snapshot.phase, StartupPhase.noLegacyFound);
      expect(snapshot.migrationKey, 'no_legacy_content');
    },
  );

  test(
    'a legacy user.db with real tag content still triggers the decision prompt',
    () async {
      await createLegacyDatabase(withRealContent: true);

      final snapshot = await StartupCoordinator.instance.initialize();

      expect(snapshot.phase, StartupPhase.legacyFoundWaitingForUser);
    },
  );
}
