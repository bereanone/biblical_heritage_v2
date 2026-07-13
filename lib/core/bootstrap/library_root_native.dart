import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LibraryRootNative {
  LibraryRootNative._();

  static const _channel = MethodChannel('studybible/library_root');

  static bool get supportsSecurityScopedPicker =>
      Platform.isIOS || defaultTargetPlatform == TargetPlatform.iOS;

  static Future<({String path, String bookmark})?> pickFolder() async {
    if (Platform.isMacOS || Platform.isIOS) {
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
        (path) => !path.toLowerCase().endsWith('.studybook'),
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
}
