import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/library/data/library_setup_state.dart';
import '../../features/utilities/data/elibrary_storage_policy.dart';

class LocalSettingsStore {
  LocalSettingsStore._();

  static final LocalSettingsStore instance = LocalSettingsStore._();

  static const _fileName = 'app_local_state.json';
  static const _pioneerCapturedHtmlFolderPathKey =
      'pioneer_captured_html_folder_path';
  static const _pioneerCapturedHtmlFolderBookmarkKey =
      'pioneer_captured_html_folder_bookmark';
  static const _lastPioneerPickerDirectoryKey = 'last_pioneer_picker_directory';
  static const _pioneerEpubSourceFolderPathKey =
      'pioneer_epub_source_folder_path';
  static const _pioneerEpubSourceFolderBookmarkKey =
      'pioneer_epub_source_folder_bookmark';

  Future<File> _settingsFile() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'local_settings'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File(p.join(dir.path, _fileName));
  }

  Future<Map<String, Object?>> load() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      return <String, Object?>{};
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return Map<String, Object?>.from(decoded);
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Fall through to a clean state if the local settings file is corrupt.
    }
    return <String, Object?>{};
  }

  Future<void> save(Map<String, Object?> data) async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  Future<String> ensureDeviceId() async {
    final settings = await load();
    final existing = settings['device_id']?.toString().trim() ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }

    final generated = 'device_${DateTime.now().toUtc().microsecondsSinceEpoch}';
    settings['device_id'] = generated;
    await save(settings);
    return generated;
  }

  Future<String?> loadLibraryRootPath() async {
    final settings = await load();
    final value = settings['library_root_path']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<String?> loadLibraryRootBookmark() async {
    final settings = await load();
    final value = settings['library_root_bookmark']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<String?> loadLibraryRootSource() async {
    final settings = await load();
    final value = settings['library_root_source']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> saveLibraryRoot({
    required String path,
    String? bookmark,
    String? source,
  }) async {
    final settings = await load();
    settings['library_root_path'] = path.trim();
    settings['library_root_bookmark'] = bookmark?.trim().isEmpty == true
        ? null
        : bookmark?.trim();
    settings['library_root_source'] = source?.trim().isEmpty == true
        ? null
        : source?.trim();
    await save(settings);
  }

  Future<void> clearLibraryRoot() async {
    final settings = await load();
    settings.remove('library_root_path');
    settings.remove('library_root_bookmark');
    settings.remove('library_root_source');
    await save(settings);
  }

  Future<Map<String, Object?>> loadMigrationState() async {
    final settings = await load();
    final raw = settings['migration_state'];
    if (raw is Map<String, Object?>) {
      return Map<String, Object?>.from(raw);
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, Object?>{};
  }

  Future<void> saveMigrationState(Map<String, Object?> state) async {
    final settings = await load();
    settings['migration_state'] = state;
    await save(settings);
  }

  Future<void> clearMigrationState() async {
    final settings = await load();
    settings.remove('migration_state');
    await save(settings);
  }

  Future<String?> loadPioneerCapturedHtmlFolderPath() async {
    final settings = await load();
    final value =
        settings[_pioneerCapturedHtmlFolderPathKey]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<String?> loadPioneerCapturedHtmlFolderBookmark() async {
    final settings = await load();
    final value =
        settings[_pioneerCapturedHtmlFolderBookmarkKey]?.toString().trim() ??
        '';
    return value.isEmpty ? null : value;
  }

  Future<void> savePioneerCapturedHtmlFolder({
    required String path,
    String? bookmark,
  }) async {
    final settings = await load();
    settings[_pioneerCapturedHtmlFolderPathKey] = path.trim();
    settings[_pioneerCapturedHtmlFolderBookmarkKey] =
        bookmark?.trim().isEmpty == true ? null : bookmark?.trim();
    await save(settings);
  }

  Future<void> clearPioneerCapturedHtmlFolder() async {
    final settings = await load();
    settings.remove(_pioneerCapturedHtmlFolderPathKey);
    settings.remove(_pioneerCapturedHtmlFolderBookmarkKey);
    await save(settings);
  }

  /// The permanent, external, read-only raw Pioneer EPUB folder the user
  /// selected for "Import Pioneer Library" bulk import. Only the reference
  /// needed to reopen it is stored — never a copy of its contents, and
  /// never Dean-specific in any portable manifest (this is per-device local
  /// state, not synced/exported data).
  Future<String?> loadPioneerEpubSourceFolderPath() async {
    final settings = await load();
    final value =
        settings[_pioneerEpubSourceFolderPathKey]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<String?> loadPioneerEpubSourceFolderBookmark() async {
    final settings = await load();
    final value =
        settings[_pioneerEpubSourceFolderBookmarkKey]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> savePioneerEpubSourceFolder({
    required String path,
    String? bookmark,
  }) async {
    final settings = await load();
    settings[_pioneerEpubSourceFolderPathKey] = path.trim();
    settings[_pioneerEpubSourceFolderBookmarkKey] =
        bookmark?.trim().isEmpty == true ? null : bookmark?.trim();
    await save(settings);
  }

  /// Clears only the stored folder reference/bookmark — never touches any
  /// already-imported book, its canonical content, or user data.
  Future<void> clearPioneerEpubSourceFolder() async {
    final settings = await load();
    settings.remove(_pioneerEpubSourceFolderPathKey);
    settings.remove(_pioneerEpubSourceFolderBookmarkKey);
    await save(settings);
  }

  Future<String?> loadLastPioneerPickerDirectory() async {
    final settings = await load();
    final value =
        settings[_lastPioneerPickerDirectoryKey]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> saveLastPioneerPickerDirectory(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    final settings = await load();
    settings[_lastPioneerPickerDirectoryKey] = normalized;
    await save(settings);
  }

  Future<Map<String, String>> loadPioneerCollectionCheck() async {
    final settings = await load();
    final raw = settings['pioneer_collection_last_check'];
    if (raw is! Map) return const {};
    return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  Future<void> savePioneerCollectionCheck({
    required String filename,
    required String collectionId,
    required String title,
    required DateTime checkedAt,
  }) async {
    final settings = await load();
    settings['pioneer_collection_last_check'] = {
      'filename': filename,
      'collectionId': collectionId,
      'title': title,
      'checkedAt': checkedAt.toUtc().toIso8601String(),
    };
    await save(settings);
  }

  Future<bool> loadLibraryReaderShowRefCodes() async {
    final settings = await load();
    final value = settings['library_reader_show_ref_codes'];
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  Future<void> saveLibraryReaderShowRefCodes(bool value) async {
    final settings = await load();
    settings['library_reader_show_ref_codes'] = value;
    await save(settings);
  }

  Future<ELibraryStoragePolicy> loadELibraryStoragePolicy() async {
    final settings = await load();
    return ELibraryStoragePolicyX.fromStoredValue(
      settings['elibrary_storage_policy']?.toString(),
    );
  }

  Future<void> saveELibraryStoragePolicy(ELibraryStoragePolicy policy) async {
    final settings = await load();
    settings['elibrary_storage_policy'] = policy.storedValue;
    await save(settings);
  }

  Future<LibrarySetupState> loadLibrarySetupState() async {
    final settings = await load();
    return librarySetupStateFromStoredValue(
      settings['elibrary_setup_state']?.toString(),
    );
  }

  Future<void> saveLibrarySetupState(LibrarySetupState state) async {
    final settings = await load();
    settings['elibrary_setup_state'] = state.storedValue;
    await save(settings);
  }

  /// Restores the first-run invitation (e.g. from a future "reset setup"
  /// action in Library Settings). Durable but always resettable.
  Future<void> resetLibrarySetupState() async {
    final settings = await load();
    settings.remove('elibrary_setup_state');
    await save(settings);
  }
}
