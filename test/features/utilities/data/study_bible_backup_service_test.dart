import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:studybible2/features/utilities/data/study_bible_backup_service.dart';

Future<File> _writeBackupArchive({
  required Directory directory,
  required Map<String, String> files,
  Map<String, Object?>? manifest,
}) async {
  final stagingDir = Directory(p.join(directory.path, 'staging'))
    ..createSync(recursive: true);
  for (final entry in files.entries) {
    final file = File(p.join(stagingDir.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value, flush: true);
  }
  if (manifest != null) {
    final manifestFile = File(p.join(stagingDir.path, 'backup_manifest.json'));
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
  }
  final archivePath = p.join(directory.path, 'backup.zip');
  final encoder = ZipFileEncoder();
  await encoder.zipDirectory(stagingDir, filename: archivePath);
  return File(archivePath);
}

void main() {
  test('inspectBackupArchive validates a StudyBible2 backup', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'studybible_backup_valid_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final archive = await _writeBackupArchive(
      directory: tempDir,
      manifest: <String, Object?>{
        'backup_format_version': 2,
        'app_name': 'Biblical Heritage',
        'app_version': '1.0.0+1',
        'backup_created_at_utc': '2026-06-12T12:00:00Z',
        'backup_created_at_local': '2026-06-12T08:00:00.000',
        'schema_or_app_data_version': 42,
        'root_path': '/tmp/studybible',
        'root_source': 'User-selected',
        'root_status': 'Confirmed Library Root selected.',
        'included_data_types': <String>[
          'user_database',
          'local_settings',
          'table_counts',
          'library_media',
        ],
        'included_files': <String>[
          'backup_manifest.json',
          'user.db',
          'local_settings.json',
          'table_counts.json',
          'Media/example.pdf',
        ],
        'required_user_database_files': <String>['user.db'],
        'optional_library_media_included': true,
        'optional_library_media_files': <String>['Media/example.pdf'],
      },
      files: <String, String>{
        'user.db': 'sqlite placeholder',
        'local_settings.json': '{"theme":"dark"}',
        'table_counts.json': '{"table_counts":{"notes":1}}',
        'Media/example.pdf': '%PDF-1.4',
      },
    );

    final inspection = await StudyBibleBackupService.instance
        .inspectBackupArchive(archive.path);

    expect(inspection.isPass, isTrue);
    expect(inspection.backupFormatVersion, 2);
    expect(inspection.appName, 'Biblical Heritage');
    expect(inspection.requiredFileChecks['user.db'], isTrue);
    expect(inspection.optionalMediaPresent, isTrue);
    expect(inspection.includedDataTypes, contains('library_media'));
    expect(inspection.warnings, isNotEmpty);
    expect(inspection.userFacingFailureMessage(), isNull);
  });

  test('inspectBackupArchive fails when user.db is missing', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'studybible_backup_invalid_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final archive = await _writeBackupArchive(
      directory: tempDir,
      manifest: <String, Object?>{
        'backup_format_version': 2,
        'app_name': 'Biblical Heritage',
        'app_version': '1.0.0+1',
        'backup_created_at_utc': '2026-06-12T12:00:00Z',
        'backup_created_at_local': '2026-06-12T08:00:00.000',
        'schema_or_app_data_version': 42,
        'included_data_types': <String>['local_settings', 'table_counts'],
        'included_files': <String>[
          'backup_manifest.json',
          'local_settings.json',
          'table_counts.json',
        ],
      },
      files: <String, String>{
        'local_settings.json': '{"theme":"dark"}',
        'table_counts.json': '{"table_counts":{"notes":1}}',
      },
    );

    final inspection = await StudyBibleBackupService.instance
        .inspectBackupArchive(archive.path);

    expect(inspection.isPass, isFalse);
    expect(inspection.requiredFileChecks['user.db'], isFalse);
    expect(inspection.errors, isNotEmpty);
    expect(
      inspection.userFacingFailureMessage(),
      'This backup cannot be restored because required user-data files are missing.',
    );
  });

  test(
    'inspectBackupArchive explains a random ZIP without a manifest',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'studybible_backup_nomani_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final archive = await _writeBackupArchive(
        directory: tempDir,
        files: <String, String>{'README.txt': 'not a studybible backup'},
      );

      final inspection = await StudyBibleBackupService.instance
          .inspectBackupArchive(archive.path);

      expect(inspection.isPass, isFalse);
      expect(
        inspection.userFacingFailureMessage(),
        'This does not appear to be a StudyBible2 backup file.',
      );
      expect(
        inspection.toDiagnosticText(),
        contains(
          'Reason: This does not appear to be a StudyBible2 backup file.',
        ),
      );
    },
  );
}
