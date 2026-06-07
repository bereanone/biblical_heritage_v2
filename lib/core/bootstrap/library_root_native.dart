import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class LibraryRootNative {
  LibraryRootNative._();

  static const _channel = MethodChannel('studybible/library_root');

  static Future<({String path, String bookmark})?> pickFolder() async {
    if (Platform.isIOS) {
      final documentsDir = await getApplicationDocumentsDirectory();
      return (path: documentsDir.path, bookmark: '');
    }
    if (Platform.isMacOS) {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickFolder',
      );
      final path = result?['path']?.toString().trim() ?? '';
      final bookmark = result?['bookmark']?.toString().trim() ?? '';
      if (path.isEmpty || bookmark.isEmpty) return null;
      return (path: path, bookmark: bookmark);
    }
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose Folder',
    );
    final normalized = path?.trim() ?? '';
    if (normalized.isEmpty) return null;
    return (path: normalized, bookmark: '');
  }

  static Future<String?> activateBookmark(String bookmark) async {
    if (!Platform.isMacOS || bookmark.trim().isEmpty) {
      return null;
    }
    return _channel.invokeMethod<String>(
      'activateBookmark',
      {'bookmark': bookmark.trim()},
    );
  }
}
