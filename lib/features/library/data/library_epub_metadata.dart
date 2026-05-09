import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

class LibraryEpubMetadata {
  const LibraryEpubMetadata({required this.creator});

  final String? creator;
}

Future<LibraryEpubMetadata?> readLibraryEpubMetadata(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final containerEntry = archive.findFile('META-INF/container.xml');
    if (containerEntry == null) return null;

    final containerXml = utf8.decode(
      containerEntry.content as List<int>,
      allowMalformed: true,
    );
    final rootfileMatch = RegExp(
      r'full-path="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(containerXml);
    final opfPath = rootfileMatch?.group(1);
    if (opfPath == null || opfPath.trim().isEmpty) return null;

    final opfEntry = archive.findFile(opfPath);
    if (opfEntry == null) return null;

    final opfXml = utf8.decode(
      opfEntry.content as List<int>,
      allowMalformed: true,
    );
    final creatorMatch = RegExp(
      r'<dc:creator[^>]*>(.*?)</dc:creator>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(opfXml);
    final creator = _cleanXmlText(creatorMatch?.group(1));
    if (creator == null || creator.isEmpty) return null;

    return LibraryEpubMetadata(creator: creator);
  } catch (_) {
    return null;
  }
}

String? _cleanXmlText(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}
