import 'dart:io';

import 'library_epub_metadata.dart';

String? normalizeLibraryAuthor(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (trimmed.toLowerCase() == 'unknown author') return null;
  return trimmed;
}

bool isEgwLibraryItem({
  required String relativePath,
  String? collectionName,
  String? sourceSite,
}) {
  final normalizedCollection = (collectionName ?? '').trim().toLowerCase();
  final normalizedPath = relativePath.replaceAll('\\', '/').toLowerCase();
  final normalizedSourceSite = sourceSite?.trim().toLowerCase() ?? '';
  return <String>{
        'egw books',
        'egw devotionals',
        'egw commentaries',
      }.contains(normalizedCollection) ||
      normalizedPath.contains('/egw_books/') ||
      normalizedPath.contains('/egw_devotionals/') ||
      normalizedPath.contains('/egw_commentaries/') ||
      normalizedSourceSite == 'egwwritings.org';
}

String? resolveLibraryAuthor({
  String? author,
  String? collectionName,
  String? sourceSite,
  required String relativePath,
}) {
  final normalizedAuthor = normalizeLibraryAuthor(author);
  if (normalizedAuthor != null) return normalizedAuthor;
  if (isEgwLibraryItem(
    relativePath: relativePath,
    collectionName: collectionName,
    sourceSite: sourceSite,
  )) {
    return 'Ellen G. White';
  }
  return null;
}

Future<String?> resolveLibraryAuthorFromEpub(
  File file, {
  String? collectionName,
  String? sourceSite,
  required String relativePath,
}) async {
  final metadata = await readLibraryEpubMetadata(file);
  final author = resolveLibraryAuthor(
    author: metadata?.creator,
    collectionName: collectionName,
    sourceSite: sourceSite,
    relativePath: relativePath,
  );
  return author;
}
