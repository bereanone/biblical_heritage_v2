import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'local_settings_store.dart';

// Some export/backup tools append a redundant .zip suffix on top of
// .studybook (e.g. "Book.studybook.zip"); a .studybook package is itself a
// ZIP archive, so accept that variant too.
bool _isStudyBookPath(String lowerPath) =>
    lowerPath.endsWith('.studybook') || lowerPath.endsWith('.studybook.zip');

bool _isPioneerPackagePath(String lowerPath) =>
    _isStudyBookPath(lowerPath) ||
    lowerPath.endsWith('.studycollection') ||
    lowerPath.endsWith('.epub');

String validateAndroidPioneerPickerPath(
  String path, {
  required bool collection,
}) {
  final normalized = path.trim();
  final lower = normalized.toLowerCase();
  if (collection && !lower.endsWith('.studycollection')) {
    throw const FormatException('Choose Pioneers.studycollection.');
  }
  if (!collection && !_isStudyBookPath(lower)) {
    throw const FormatException('Choose a .studybook Pioneer package.');
  }
  return normalized;
}

class LibraryRootNative {
  LibraryRootNative._();

  static const _channel = MethodChannel('studybible/library_root');
  static const _androidDocumentPickerChannel = MethodChannel(
    'studybible/android_document_picker',
  );

  static bool get supportsSecurityScopedPicker =>
      Platform.isIOS || defaultTargetPlatform == TargetPlatform.iOS;

  @visibleForTesting
  static bool? debugUsesAndroidDocumentTree;

  static bool get usesAndroidDocumentTree =>
      debugUsesAndroidDocumentTree ?? Platform.isAndroid;

  static Future<AndroidLibraryAuthorization>
  validateAndroidLibraryTree() async {
    if (!usesAndroidDocumentTree) {
      return const AndroidLibraryAuthorization.notApplicable();
    }
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'validateAndroidLibraryTree',
    );
    return AndroidLibraryAuthorization.fromMap(result);
  }

  static Future<AndroidLibraryAuthorization?> pickAndroidLibraryTree({
    bool requireExisting = false,
  }) async {
    if (!usesAndroidDocumentTree) return null;
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickAndroidLibraryTree',
      {'requireExisting': requireExisting},
    );
    if (result?['cancelled'] == true) return null;
    return AndroidLibraryAuthorization.fromMap(result);
  }

  static Future<void> clearAndroidLibraryTree() async {
    if (!usesAndroidDocumentTree) return;
    await _channel.invokeMethod<void>('clearAndroidLibraryTree');
  }

  static Future<({int created, int existing})?> syncAndroidLibraryTree() async {
    if (!usesAndroidDocumentTree) return null;
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'syncAndroidLibraryTree',
    );
    return (
      created: (result?['created'] as num?)?.toInt() ?? 0,
      existing: (result?['existing'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<({String path, String bookmark})?> pickFolder() async {
    if (Platform.isIOS || defaultTargetPlatform == TargetPlatform.iOS) {
      throw UnsupportedError(
        'iPhone and iPad import books by selecting a .studybook package or '
        'CaptureClipper files. A persistent Files-provider folder is not '
        'required or supported.',
      );
    }
    if (usesAndroidDocumentTree) {
      final authorization = await pickAndroidLibraryTree();
      if (authorization == null) return null;
      if (!authorization.isAuthorized ||
          authorization.path == null ||
          authorization.treeUri == null) {
        throw StateError(
          authorization.validationError ??
              'StudyBible cannot access the selected library folder.',
        );
      }
      return (path: authorization.path!, bookmark: authorization.treeUri!);
    }
    if (Platform.isMacOS) {
      debugPrint(
        'Library root native picker requested on ${Platform.operatingSystem}.',
      );
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickFolder',
      );
      final path = result?['path']?.toString().trim() ?? '';
      final bookmark = result?['bookmark']?.toString().trim() ?? '';
      if (path.isEmpty || bookmark.isEmpty) {
        debugPrint(
          'Library root native picker returned no usable folder selection.',
        );
        return null;
      }
      debugPrint('Library root native picker selected: $path');
      return (path: path, bookmark: bookmark);
    }
    debugPrint('Desktop folder picker requested.');
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose Folder',
    );
    final normalized = path?.trim() ?? '';
    if (normalized.isEmpty) return null;
    debugPrint('Desktop folder picker selected: $normalized');
    return (path: normalized, bookmark: '');
  }

  static Future<({String path, String bookmark})?> pickScannedHtmlFile() async {
    if (supportsSecurityScopedPicker) {
      debugPrint(
        'Library root native HTML picker requested on ${Platform.operatingSystem}.',
      );
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickScannedHtmlFile',
      );
      final path = result?['path']?.toString().trim() ?? '';
      final bookmark = result?['bookmark']?.toString().trim() ?? '';
      if (path.isEmpty || bookmark.isEmpty) {
        debugPrint(
          'Library root native HTML picker returned no usable folder selection.',
        );
        return null;
      }
      debugPrint('Library root native HTML picker selected: $path');
      return (path: path, bookmark: bookmark);
    }
    debugPrint(
      'Library root native HTML picker unavailable on ${Platform.operatingSystem}.',
    );
    return null;
  }

  /// Opens the iOS Files picker in copy mode so OneDrive (or any Files
  /// provider) can be used without granting folder access. Returns local
  /// copy paths of the selected files, or null when cancelled/unavailable.
  ///
  /// [kind] is 'html' for CaptureClipper HTML files or 'assets' to also
  /// allow images, CSS, and text files.
  static Future<List<String>?> pickImportFiles({String kind = 'html'}) async {
    if (Platform.isAndroid || defaultTargetPlatform == TargetPlatform.android) {
      if (kind == 'pioneerZip') {
        final zipPath =
            (await _androidDocumentPickerChannel.invokeMethod<String>(
              'pickFile',
              {'kind': kind},
            ))?.trim() ??
            '';
        if (zipPath.isEmpty) return null;
        if (!zipPath.toLowerCase().endsWith('.zip')) {
          throw const FormatException(
            'Choose the Pioneer Library ZIP file you downloaded.',
          );
        }
        return <String>[zipPath];
      }
      if (kind != 'collection' &&
          kind != 'bookPackage' &&
          kind != 'pioneerPackage') {
        debugPrint(
          'CaptureClipper file import picker unavailable for kind=$kind on Android.',
        );
        return null;
      }
      final resolvedPath =
          (await _androidDocumentPickerChannel.invokeMethod<String>(
            'pickFile',
            {'kind': kind},
          ))?.trim() ??
          '';
      if (resolvedPath.isEmpty) return null;
      if (kind == 'pioneerPackage') {
        if (!_isPioneerPackagePath(resolvedPath.toLowerCase())) {
          throw const FormatException(
            'Choose a .studybook, .studycollection, or .epub Pioneer file.',
          );
        }
        return <String>[resolvedPath];
      }
      return <String>[
        validateAndroidPioneerPickerPath(
          resolvedPath,
          collection: kind == 'collection',
        ),
      ];
    }
    if ((defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux) &&
        kind == 'pioneerZip') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        allowMultiple: false,
        dialogTitle: 'Choose the Pioneer Library ZIP file',
        initialDirectory: await _lastPioneerPickerDirectory(),
      );
      final selectedPath = result?.files.firstOrNull?.path?.trim() ?? '';
      if (selectedPath.isEmpty) return null;
      await LocalSettingsStore.instance.saveLastPioneerPickerDirectory(
        p.dirname(selectedPath),
      );
      return <String>[selectedPath];
    }
    if ((defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux) &&
        (kind == 'collection' ||
            kind == 'bookPackage' ||
            kind == 'pioneerPackage')) {
      final collection = kind == 'collection';
      final anyPioneerPackage = kind == 'pioneerPackage';
      final dialogTitle = anyPioneerPackage
          ? 'Choose a Pioneer book, EPUB, or collection'
          : collection
          ? 'Choose Pioneers.studycollection'
          : 'Choose a Pioneer .studybook package';
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        dialogTitle: dialogTitle,
        initialDirectory: await _lastPioneerPickerDirectory(),
      );
      final selectedPath = result?.files.firstOrNull?.path?.trim() ?? '';
      if (selectedPath.isEmpty) {
        debugPrint('Desktop Pioneer package picker returned no file.');
        return null;
      }
      await LocalSettingsStore.instance.saveLastPioneerPickerDirectory(
        p.dirname(selectedPath),
      );
      if (anyPioneerPackage) {
        if (!_isPioneerPackagePath(selectedPath.toLowerCase())) {
          throw const FormatException(
            'Choose a .studybook, .studycollection, or .epub Pioneer file.',
          );
        }
        return <String>[selectedPath];
      }
      return <String>[
        validateAndroidPioneerPickerPath(selectedPath, collection: collection),
      ];
    }
    if (!supportsSecurityScopedPicker) {
      debugPrint(
        'CaptureClipper file import picker unavailable on '
        '${Platform.operatingSystem}.',
      );
      return null;
    }
    debugPrint('CaptureClipper file import picker requested (kind=$kind).');
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickImportFiles',
      {'kind': kind},
    );
    final rawPaths = result?['paths'];
    final paths = rawPaths is List
        ? rawPaths
              .map((path) => path?.toString().trim() ?? '')
              .where((path) => path.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    if (kind == 'collection') {
      final invalid = paths.where(
        (path) => !path.toLowerCase().endsWith('.studycollection'),
      );
      if (invalid.isNotEmpty) {
        throw const FormatException(
          'That is an individual book package. Choose Pioneers.studycollection to check the full collection.',
        );
      }
    } else if (kind == 'bookPackage') {
      final invalid = paths.where(
        (path) => !_isStudyBookPath(path.toLowerCase()),
      );
      if (invalid.isNotEmpty) {
        throw const FormatException(
          'Choose an individual book package, not a collection file.',
        );
      }
    }
    if (paths.isEmpty) {
      debugPrint(
        'CaptureClipper file import picker cancelled or returned no files.',
      );
      return null;
    }
    debugPrint(
      'CaptureClipper file import picker selected ${paths.length} file(s).',
    );
    return paths;
  }

  static Future<String?> pickStudyCollection() async =>
      (await pickImportFiles(kind: 'collection'))?.firstOrNull;

  static Future<String?> pickStudyBookPackage() async =>
      (await pickImportFiles(kind: 'bookPackage'))?.firstOrNull;

  static Future<String?> pickPioneerPackage() async =>
      (await pickImportFiles(kind: 'pioneerPackage'))?.firstOrNull;

  /// Picks a single Pioneer Library collection ZIP file. Selecting one file
  /// is far more reliable across cloud storage
  /// providers than navigating the folder-tree picker, which several
  /// providers (notably Google Drive) present poorly.
  static Future<String?> pickPioneerZipFile() async =>
      (await pickImportFiles(kind: 'pioneerZip'))?.firstOrNull;

  static Future<String?> pickSavedPioneerExport() async {
    if (Platform.isAndroid || defaultTargetPlatform == TargetPlatform.android) {
      final path =
          (await _androidDocumentPickerChannel.invokeMethod<String>(
            'pickFile',
            {'kind': 'savedExport'},
          ))?.trim() ??
          '';
      return path.isEmpty ? null : path;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
      dialogTitle: 'Choose a saved Pioneer export or EPUB',
      initialDirectory: await _lastPioneerPickerDirectory(),
    );
    final path = result?.files.firstOrNull?.path?.trim() ?? '';
    if (path.isEmpty) return null;
    await LocalSettingsStore.instance.saveLastPioneerPickerDirectory(
      p.dirname(path),
    );
    return path;
  }

  /// Requests temporary read access to the Books parent folder from the iOS
  /// Files provider. Its contents are copied immediately by the caller; the
  /// returned path is never retained as a persistent provider root.
  static Future<List<String>?> pickImportFolders() async {
    if (!supportsSecurityScopedPicker) return null;
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickImportFolders',
    );
    final rawPaths = result?['paths'];
    final paths = rawPaths is List
        ? rawPaths
              .map((path) => path?.toString().trim() ?? '')
              .where((path) => path.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return paths.isEmpty ? null : paths;
  }

  static Future<String?> activateBookmark(String bookmark) async {
    if (!(Platform.isMacOS || Platform.isIOS) || bookmark.trim().isEmpty) {
      return null;
    }
    return _channel.invokeMethod<String>('activateBookmark', {
      'bookmark': bookmark.trim(),
    });
  }

  static Future<String?> _lastPioneerPickerDirectory() async {
    final saved = await LocalSettingsStore.instance
        .loadLastPioneerPickerDirectory();
    if (saved == null || saved.trim().isEmpty) return null;
    return await Directory(saved).exists() ? saved : null;
  }
}

class AndroidLibraryAuthorization {
  const AndroidLibraryAuthorization({
    required this.isAuthorized,
    required this.persistedRead,
    required this.persistedWrite,
    required this.enumerates,
    required this.expectedMarkersFound,
    required this.authorizationState,
    this.treeUri,
    this.path,
    this.displayName,
    this.legacyPathHint,
    this.validationError,
    this.fileCount = 0,
    this.authorizationTimestamp,
    this.lastReconnect,
    this.lastAuthorizationError,
  });

  const AndroidLibraryAuthorization.notApplicable()
    : isAuthorized = true,
      persistedRead = true,
      persistedWrite = true,
      enumerates = true,
      expectedMarkersFound = true,
      authorizationState = 'notApplicable',
      treeUri = null,
      path = null,
      displayName = null,
      legacyPathHint = null,
      validationError = null,
      fileCount = 0,
      authorizationTimestamp = null,
      lastReconnect = null,
      lastAuthorizationError = null;

  factory AndroidLibraryAuthorization.fromMap(Map<dynamic, dynamic>? map) {
    final value = map ?? const <dynamic, dynamic>{};
    return AndroidLibraryAuthorization(
      isAuthorized: value['authorized'] == true,
      persistedRead: value['persistedRead'] == true,
      persistedWrite: value['persistedWrite'] == true,
      enumerates: value['enumerates'] == true,
      expectedMarkersFound: value['expectedMarkersFound'] == true,
      authorizationState:
          value['authorizationState']?.toString() ??
          'libraryRootAuthorizationMissing',
      treeUri: _nonEmpty(value['treeUri']),
      path: _nonEmpty(value['path']),
      displayName: _nonEmpty(value['displayName']),
      legacyPathHint: _nonEmpty(value['legacyPathHint']),
      validationError: _nonEmpty(value['validationError']),
      fileCount: (value['fileCount'] as num?)?.toInt() ?? 0,
      authorizationTimestamp: (value['authorizationTimestamp'] as num?)
          ?.toInt(),
      lastReconnect: (value['lastReconnect'] as num?)?.toInt(),
      lastAuthorizationError: _nonEmpty(value['lastAuthorizationError']),
    );
  }

  final bool isAuthorized;
  final bool persistedRead;
  final bool persistedWrite;
  final bool enumerates;
  final bool expectedMarkersFound;
  final String authorizationState;
  final String? treeUri;
  final String? path;
  final String? displayName;
  final String? legacyPathHint;
  final String? validationError;
  final int fileCount;
  final int? authorizationTimestamp;
  final int? lastReconnect;
  final String? lastAuthorizationError;

  static String? _nonEmpty(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
