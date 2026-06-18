import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/sandbox_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('sandbox_support_');
    documentsDir = await Directory.systemTemp.createTemp('sandbox_documents_');
    libraryRootDir = await Directory.systemTemp.createTemp('sandbox_root_');
    LibraryRootService.instance.invalidateCachedSelection();
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
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
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

  test(
    'resolves eLibrary DB under the active Library Root Databases folder',
    () async {
      await LibraryRootService.instance.setLibraryRoot(
        path: libraryRootDir.path,
      );

      final path = await SandboxBootstrap.eLibraryDatabasePath();

      expect(path, p.join(libraryRootDir.path, 'Databases', 'eLibrary.db'));
    },
  );
}
