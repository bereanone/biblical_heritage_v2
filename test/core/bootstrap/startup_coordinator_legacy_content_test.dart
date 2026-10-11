import 'package:package_info_plus/package_info_plus.dart';
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
    PackageInfo.setMockInitialValues(
      appName: 'StudyBible',
      packageName: 'test.studybible',
      version: '2.0.5',
      buildNumber: '75',
      buildSignature: '',
    );
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
  test(
    'remembered keep-current-data survives relaunch without changing legacy tags',
    () async {
      await createLegacyDatabase(withRealContent: true);
      expect(
        (await StartupCoordinator.instance.initialize()).requiresDecision,
        isTrue,
      );
      await StartupCoordinator.instance.keepCurrentData();
      await UserDatabase.instance.close();
      expect(
        (await StartupCoordinator.instance.initialize()).phase,
        StartupPhase.ready,
      );
      final legacy = await openDatabase(
        await SandboxBootstrap.legacyUserDatabasePath(),
        readOnly: true,
        singleInstance: false,
      );
      expect(await legacy.query('hash_tags'), hasLength(1));
      await legacy.close();
    },
  );

  test(
    'database completion recovers a missing local startup setting',
    () async {
      await createLegacyDatabase(withRealContent: true);
      await StartupCoordinator.instance.keepCurrentData();
      final db = await UserDatabase.instance.database;
      await db.update('app_migrations', {'status': 'migration_completed'});
      await UserDatabase.instance.close();
      await LocalSettingsStore.instance.saveMigrationState({});
      expect(
        (await StartupCoordinator.instance.initialize()).phase,
        StartupPhase.ready,
      );
      expect(
        (await LocalSettingsStore.instance.loadMigrationState())['status'],
        'migration_completed',
      );
    },
  );

  test('completed no-legacy startup does not later re-prompt', () async {
    await StartupCoordinator.instance.initialize();
    await createLegacyDatabase(withRealContent: true);
    expect(
      (await StartupCoordinator.instance.initialize()).phase,
      StartupPhase.ready,
    );
  });

  test('explicit failed migration is not hidden by older completion', () async {
    await createLegacyDatabase(withRealContent: true);
    await StartupCoordinator.instance.keepCurrentData();
    await LocalSettingsStore.instance.saveMigrationState({
      'status': 'migration_failed',
    });
    expect(
      (await StartupCoordinator.instance.initialize()).requiresDecision,
      isTrue,
    );
  });
  void installBuild(String build) {
    PackageInfo.setMockInitialValues(
      appName: 'StudyBible',
      packageName: 'test.studybible',
      version: '2.0.5',
      buildNumber: build,
      buildSignature: '',
    );
  }

  test(
    'each update asks once and ordinary relaunches keep the choice',
    () async {
      await StartupCoordinator.instance.initialize();
      for (final build in ['76', '77']) {
        installBuild(build);
        await UserDatabase.instance.close();
        final updated = await StartupCoordinator.instance.initialize();
        expect(updated.requiresDecision, isTrue);
        expect(updated.isUpdateReview, isTrue);
        // Seeing the screen alone is not an acknowledgement.
        expect(
          (await StartupCoordinator.instance.initialize()).requiresDecision,
          isTrue,
        );
        await StartupCoordinator.instance.keepCurrentData();
        for (var restart = 0; restart < 2; restart++) {
          await UserDatabase.instance.close();
          expect(
            (await StartupCoordinator.instance.initialize()).isReady,
            isTrue,
          );
        }
      }
    },
  );

  test('an older completion with no build acknowledgement asks once', () async {
    await StartupCoordinator.instance.keepCurrentData();
    final settings = await LocalSettingsStore.instance.load();
    settings.remove('startup_reviewed_version');
    await LocalSettingsStore.instance.save(settings);
    expect(
      (await StartupCoordinator.instance.initialize()).isUpdateReview,
      isTrue,
    );
    await StartupCoordinator.instance.keepCurrentData();
    expect((await StartupCoordinator.instance.initialize()).isReady, isTrue);
  });

  test('both backup choices acknowledge only the current build', () async {
    for (final upgrade in [false, true]) {
      installBuild(upgrade ? '77' : '76');
      await createLegacyDatabase(withRealContent: true);
      if (upgrade) {
        await StartupCoordinator.instance.backUpAndUpgrade();
      } else {
        await StartupCoordinator.instance.startFreshButKeepLegacyBackup();
      }
      await UserDatabase.instance.close();
      expect((await StartupCoordinator.instance.initialize()).isReady, isTrue);
    }
    installBuild('78');
    expect(
      (await StartupCoordinator.instance.initialize()).isUpdateReview,
      isTrue,
    );
  });
}
