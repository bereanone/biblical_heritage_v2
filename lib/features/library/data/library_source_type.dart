import 'dart:convert';
import 'package:archive/archive.dart';

/// Handles old provider cache names without treating arbitrary ZIPs as text.
String normalizedEpubFileName(String name) {
  return name.replaceFirstMapped(
    RegExp(r'\.epub\.(\d+)$', caseSensitive: false),
    (match) => '.${match[1]}.epub',
  );
}

bool librarySourceIsEpub(
  List<int> bytes, {
  required String path,
  String? originalName,
  String? mimeType,
}) {
  final zipHeader = bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;
  // A canonical HTML derivative may retain its original EPUB catalog name.
  if (!zipHeader && RegExp(r'\.html?$', caseSensitive: false).hasMatch(path)) {
    return false;
  }
  final declared =
      [path, originalName ?? ''].any(
        (name) => normalizedEpubFileName(name).toLowerCase().endsWith('.epub'),
      ) ||
      mimeType?.toLowerCase() == 'application/epub+zip';
  if (declared) return true; // Structural validation remains mandatory.
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) return false;
  try {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final mimetype = archive.findFile('mimetype');
    if (mimetype != null &&
        utf8.decode(mimetype.content, allowMalformed: true).trim() ==
            'application/epub+zip') {
      return true;
    }
    if (archive.findFile('META-INF/container.xml') != null) return true;
  } catch (_) {
    throw const FormatException(
      'Unreadable ZIP source; cannot render as text.',
    );
  }
  throw const FormatException(
    'ZIP source is not an EPUB; cannot render as text.',
  );
}
