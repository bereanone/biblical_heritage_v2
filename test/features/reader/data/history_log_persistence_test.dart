import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/bootstrap/sandbox_bootstrap.dart';
import 'package:studybible2/core/bootstrap/startup_coordinator.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/reader/data/history_log_service.dart';

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

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'StudyBible',
      packageName: 'test.studybible',
      version: '2.0.5',
      buildNumber: '75',
      buildSignature: '',
    );
    await UserDatabase.instance.close();
    supportDir = await Directory.systemTemp.createTemp(
      'history_persistence_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'history_persistence_documents_',
    );
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(
      path: documentsDir.path,
      source: LibraryRootSource.defaultAppFolder,
    );
  });

  tearDown(() async {
    await UserDatabase.instance.close();
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    for (final directory in <Directory>[supportDir, documentsDir]) {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test(
    'a new Bible visit survives reopen and completed-update initialization',
    () async {
      const visitedBlockId = 4242;
      final expectedPath = p.join(documentsDir.path, 'Databases', 'user.db');

      expect(await SandboxBootstrap.userDatabasePath(), expectedPath);
      await HistoryLogService.instance.insertHistory(visitedBlockId);
      expect(File(expectedPath).existsSync(), isTrue);
      expect(
        (await HistoryLogService.instance.fetchHistory()).map(
          (entry) => entry.blockId,
        ),
        contains(visitedBlockId),
      );

      // Simulate a normal application restart: close every handle and rebuild
      // the selected-root decision from the persisted local settings.
      await UserDatabase.instance.close();
      LibraryRootService.instance.invalidateCachedSelection();
      expect(await SandboxBootstrap.userDatabasePath(), expectedPath);
      expect(
        (await HistoryLogService.instance.fetchHistory()).map(
          (entry) => entry.blockId,
        ),
        contains(visitedBlockId),
      );

      // A supported completed upgrade re-runs schema initialization and records
      // its migration row in the same database; it must not replace history.
      await LocalSettingsStore.instance.saveMigrationState(<String, Object?>{
        'migration_key': 'history-persistence-regression',
        'from_version': 'legacy-v1',
        'to_version': 'v2',
        'started_at': '2026-09-17T00:00:00Z',
        'completed_at': '2026-09-17T00:00:01Z',
        'backup_path': null,
        'status': 'migration_completed',
        'error_message': null,
      });
      await UserDatabase.instance.close();
      LibraryRootService.instance.invalidateCachedSelection();

      final startup = await StartupCoordinator.instance.initialize();
      expect(startup.isUpdateReview, isTrue);
      await StartupCoordinator.instance.keepCurrentData();
      expect((await StartupCoordinator.instance.initialize()).isReady, isTrue);
      expect(await SandboxBootstrap.userDatabasePath(), expectedPath);
      expect(
        (await HistoryLogService.instance.fetchHistory()).map(
          (entry) => entry.blockId,
        ),
        contains(visitedBlockId),
      );
    },
  );
}
