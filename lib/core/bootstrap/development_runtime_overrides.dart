import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

const String _elibraryDatabaseOverride = String.fromEnvironment(
  'STUDYBIBLE2_ELIBRARY_DB_OVERRIDE',
);
const String _userDatabaseOverride = String.fromEnvironment(
  'STUDYBIBLE2_USER_DB_OVERRIDE',
);
const bool _skipCaptureClipperStartupScan = bool.fromEnvironment(
  'STUDYBIBLE2_SKIP_CAPTURECLIPPER_STARTUP_SCAN',
  defaultValue: false,
);

String? resolveDevelopmentDatabaseOverride({
  required String suppliedPath,
  required String label,
  required bool releaseMode,
  bool Function(String path)? fileExists,
}) {
  if (releaseMode) return null;
  final value = suppliedPath.trim();
  if (value.isEmpty) return null;
  if (!p.isAbsolute(value)) {
    throw StateError('$label override must be an absolute path.');
  }
  final normalized = p.normalize(value);
  final exists = fileExists ?? (path) => File(path).existsSync();
  if (!exists(normalized)) {
    throw StateError('$label override does not exist: $normalized');
  }
  return normalized;
}

String? developmentELibraryDatabaseOverride({
  bool releaseMode = kReleaseMode,
}) => resolveDevelopmentDatabaseOverride(
  suppliedPath: _elibraryDatabaseOverride,
  label: 'eLibrary.db',
  releaseMode: releaseMode,
);

String? developmentUserDatabaseOverride({bool releaseMode = kReleaseMode}) =>
    resolveDevelopmentDatabaseOverride(
      suppliedPath: _userDatabaseOverride,
      label: 'user.db',
      releaseMode: releaseMode,
    );

bool shouldSkipCaptureClipperStartupScan({
  bool releaseMode = kReleaseMode,
  bool suppliedValue = _skipCaptureClipperStartupScan,
}) => !releaseMode && suppliedValue;
