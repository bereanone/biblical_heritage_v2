import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/sandbox_bootstrap.dart';
import 'package:studybible2/core/bootstrap/startup_coordinator.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_availability_service.dart';

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

Future<void> _installLibraryRootNativeMock({
  required String activatedPath,
  required void Function() onActivated,
}) async {
  const channel = MethodChannel('studybible/library_root');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'activateBookmark':
            onActivated();
            return activatedPath;
          case 'pickFolder':
            return <String, Object?>{
              'path': activatedPath,
              'bookmark': 'bookmark-token',
            };
        }
        return null;
      });
}

Future<Directory> _createCaptureFolder({
  required Directory root,
  required String title,
  required String abbreviation,
  required String workId,
  required String sourceUrl,
  required String authorName,
  required String bodyHtml,
}) async {
  final booksRoot = p.basename(root.path) == 'Books'
      ? root
      : Directory(p.join(root.path, 'Books'));
  final folder = Directory(p.join(booksRoot.path, workId));
  await folder.create(recursive: true);
  await File(p.join(folder.path, 'metadata.json')).writeAsString('''
{
  "title": "$title",
  "abbreviation": "$abbreviation",
  "work_id": "$workId",
  "source_type": "pioneer_captured_html",
  "source_site": "user_capture",
  "source_url": "$sourceUrl",
  "contributors": [
    {
      "name": "$authorName",
      "role": "author",
      "sort_order": 1,
      "primary": true
    }
  ]
}
''');
  await File(p.join(folder.path, 'capture.html')).writeAsString('''
<!doctype html>
<html>
  <head>
    <title>$title</title>
    <meta name="author" content="$authorName" />
    <link rel="canonical" href="$sourceUrl" />
  </head>
  <body>
    <h1>$title</h1>
    $bodyHtml
  </body>
</html>
''');
  return folder;
}

Future<void> _createLegacyMarkerFile(Directory documentsDir) async {
  final legacyPath = await SandboxBootstrap.legacyUserDatabasePath();
  final file = File(legacyPath);
  await file.parent.create(recursive: true);
  await file.writeAsString('legacy');
  expect(documentsDir.existsSync(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  late Directory captureRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'startup_capture_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'startup_capture_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'startup_capture_library_',
    );
    captureRootDir = await Directory.systemTemp.createTemp(
      'startup_capture_folder_',
    );
    LibraryRootService.instance.invalidateCachedSelection();
    PioneerCapturedHtmlImportAvailabilityService.instance.clear();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    await LocalSettingsStore.instance.ensureDeviceId();
    PioneerCapturedHtmlImportAvailabilityService.instance.clear();
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    PioneerCapturedHtmlImportAvailabilityService.instance.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('studybible/library_root'),
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
    if (captureRootDir.existsSync()) {
      await captureRootDir.delete(recursive: true);
    }
    PioneerCapturedHtmlImportAvailabilityService.instance.clear();
  });

  test(
    'initialize reports available CaptureClipper folders without moving them',
    () async {
      await _installLibraryRootNativeMock(
        activatedPath: captureRootDir.path,
        onActivated: () {},
      );
      await _createLegacyMarkerFile(documentsDir);
      await _createCaptureFolder(
        root: captureRootDir,
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        workId: 'DAR',
        sourceUrl: 'https://example.invalid/dar',
        authorName: 'Uriah Smith',
        bodyHtml: '''
    <div class="clip clip-text">
      <p>Chapter 1 — Opening DAR 1 Intro text. DAR 1.1 First paragraph text. DAR 1.2</p>
    </div>
    <div class="clip clip-text">
      <p>Chapter 2 — Section Two DAR 2.1 Second paragraph text.</p>
    </div>
''',
      );
      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
        bookmark: 'bookmark-token',
      );

      final statuses = <String>[];
      final snapshot = await StartupCoordinator.instance.initialize(
        onStatus: statuses.add,
      );

      expect(snapshot.phase, StartupPhase.legacyFoundWaitingForUser);
      expect(
        PioneerCapturedHtmlImportAvailabilityService.instance.latestReport,
        isNull,
        reason: 'folder discovery must not block initialize()',
      );
      await StartupCoordinator.instance.runBackgroundMaintenance();
      expect(
        statuses.any((status) => status.contains('bookmark-token')),
        isFalse,
      );
      expect(
        PioneerCapturedHtmlImportAvailabilityService
            .instance
            .latestReport
            ?.availableCount,
        1,
      );
      expect(
        Directory(p.join(captureRootDir.path, 'Backup')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(captureRootDir.path, 'Books', 'DAR')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(captureRootDir.path, 'Books', 'DAR', 'capture.html'),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'initialize leaves ready CaptureClipper folders untouched during discovery',
    () async {
      await _installLibraryRootNativeMock(
        activatedPath: captureRootDir.path,
        onActivated: () {},
      );
      await _createLegacyMarkerFile(documentsDir);
      final folder = await _createCaptureFolder(
        root: captureRootDir,
        title: 'The Cross and Its Shadow',
        abbreviation: 'CIS',
        workId: 'CIS',
        sourceUrl: 'https://example.invalid/cis-repair',
        authorName: 'Uriah Smith',
        bodyHtml: '''
    <div class="clip clip-text">
      <p>Chapter 33-The Jubilee
CIS 247
THE jubilee the climax of a series of sabbatical institutions.
CIS 247.1
After the children of Israel entered the promised land, God commanded that every seventh year should be a Sabbath of rest unto the land.
CIS 247.2</p>
    </div>
''',
      );
      await File(p.join(folder.path, 'cover.jpg')).writeAsString('cover');

      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: captureRootDir.path,
      );

      final statuses = <String>[];
      final snapshot = await StartupCoordinator.instance.initialize(
        onStatus: statuses.add,
      );

      expect(snapshot.phase, StartupPhase.legacyFoundWaitingForUser);
      expect(
        PioneerCapturedHtmlImportAvailabilityService.instance.latestReport,
        isNull,
        reason: 'folder discovery must not block initialize()',
      );
      await StartupCoordinator.instance.runBackgroundMaintenance();
      expect(
        PioneerCapturedHtmlImportAvailabilityService
            .instance
            .latestReport
            ?.availableCount,
        1,
      );
      expect(folder.existsSync(), isTrue);
      expect(
        Directory(p.join(captureRootDir.path, 'Backup')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'initialize skips CaptureClipper discovery when no folder is configured',
    () async {
      await _createLegacyMarkerFile(documentsDir);
      await LocalSettingsStore.instance.clearPioneerCapturedHtmlFolder();

      final statuses = <String>[];
      final snapshot = await StartupCoordinator.instance.initialize(
        onStatus: statuses.add,
      );

      expect(snapshot.phase, StartupPhase.legacyFoundWaitingForUser);
      await StartupCoordinator.instance.runBackgroundMaintenance();
      expect(
        PioneerCapturedHtmlImportAvailabilityService.instance.latestReport,
        isNull,
      );
    },
  );
}
