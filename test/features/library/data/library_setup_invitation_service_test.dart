import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_setup_invitation_service.dart';
import 'package:studybible2/features/library/data/library_setup_state.dart';

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
    supportDir = await Directory.systemTemp.createTemp('setup_invite_support_');
    documentsDir = await Directory.systemTemp.createTemp('setup_invite_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp(
      'setup_invite_root_',
    );
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
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
    for (final dir in [supportDir, documentsDir, libraryRootDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  Future<void> seedReadableItem() async {
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': 'readable-1',
      'title': 'A Ready Book',
      'file_name': 'ready.epub',
      'relative_path': 'ready.epub',
      'file_format': 'epub',
      'source_type': 'official_download',
      'index_status': 'indexed',
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
  }

  test('1. shows the invitation when no readable items exist and setup was '
      'never started', () async {
    expect(
      await LibrarySetupInvitationService.instance.shouldShowInvitation(),
      isTrue,
    );
  });

  test('2. does not show again once setup is marked completed', () async {
    await LibrarySetupInvitationService.instance.markCompleted();
    expect(
      await LibrarySetupInvitationService.instance.shouldShowInvitation(),
      isFalse,
    );
  });

  test('does not show again once at least one readable item exists', () async {
    await seedReadableItem();
    expect(
      await LibrarySetupInvitationService.instance.shouldShowInvitation(),
      isFalse,
    );
  });

  test('3. Skip for Now persists across reads', () async {
    await LibrarySetupInvitationService.instance.markSkipped();
    expect(
      await LocalSettingsStore.instance.loadLibrarySetupState(),
      LibrarySetupState.skipped,
    );
    expect(
      await LibrarySetupInvitationService.instance.shouldShowInvitation(),
      isFalse,
    );
  });

  test('reset() restores the invitation', () async {
    await LibrarySetupInvitationService.instance.markSkipped();
    expect(
      await LibrarySetupInvitationService.instance.shouldShowInvitation(),
      isFalse,
    );
    await LibrarySetupInvitationService.instance.reset();
    expect(
      await LibrarySetupInvitationService.instance.shouldShowInvitation(),
      isTrue,
    );
  });

  test(
    'an unavailable (needs_attention) item alone does not count as readable',
    () async {
      final db = await ELibraryDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('library_items', <String, Object?>{
        'id': 'broken-1',
        'title': 'Broken Book',
        'file_name': 'broken.epub',
        'relative_path': 'broken.epub',
        'file_format': 'epub',
        'source_type': 'official_download',
        'index_status': 'needs_attention',
        'index_error': 'Structurally invalid EPUB (missingOpf).',
        'is_missing': 0,
        'created_at': now,
        'updated_at': now,
        'device_id': 'test-device',
      });
      expect(
        await LibrarySetupInvitationService.instance.hasAnyReadableItem(),
        isFalse,
      );
      expect(
        await LibrarySetupInvitationService.instance.shouldShowInvitation(),
        isTrue,
      );
    },
  );

  test('a readable Pioneer EPUB folder import counts as an acquired book, same '
      'as any other setup path', () async {
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': 'pioneer-epub-1',
      'title': 'A Pioneer Book',
      'file_name': 'pioneer.epub',
      'relative_path': 'ImportedPioneerEpubs/pioneer.epub',
      'file_format': 'epub',
      'source_type': 'pioneer_epub_import',
      'index_status': 'indexed',
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    expect(
      await LibrarySetupInvitationService.instance.hasAnyReadableItem(),
      isTrue,
    );
    expect(
      await LibrarySetupInvitationService.instance.shouldShowInvitation(),
      isFalse,
    );
  });
}
