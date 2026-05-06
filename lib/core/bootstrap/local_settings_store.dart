import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalSettingsStore {
  LocalSettingsStore._();

  static final LocalSettingsStore instance = LocalSettingsStore._();

  static const _fileName = 'app_local_state.json';

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
    if (existing.isNotEmpty) return existing;

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

  Future<void> saveLibraryRoot({required String path, String? bookmark}) async {
    final settings = await load();
    settings['library_root_path'] = path.trim();
    settings['library_root_bookmark'] = bookmark?.trim().isEmpty == true
        ? null
        : bookmark?.trim();
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
}
