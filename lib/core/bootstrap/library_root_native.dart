import 'dart:io';

import 'package:flutter/services.dart';

class LibraryRootNative {
  LibraryRootNative._();

  static const _channel = MethodChannel('studybible/library_root');

  static Future<({String path, String bookmark})?> pickFolder() async {
    if (!Platform.isMacOS) return null;
    final result = await _channel.invokeMapMethod<String, dynamic>('pickFolder');
    final path = result?['path']?.toString().trim() ?? '';
    final bookmark = result?['bookmark']?.toString().trim() ?? '';
    if (path.isEmpty || bookmark.isEmpty) return null;
    return (path: path, bookmark: bookmark);
  }

  static Future<String?> activateBookmark(String bookmark) async {
    if (!Platform.isMacOS || bookmark.trim().isEmpty) return null;
    return _channel.invokeMethod<String>(
      'activateBookmark',
      {'bookmark': bookmark.trim()},
    );
  }
}
