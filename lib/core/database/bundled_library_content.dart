import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bundled_library_catalog_update.dart';

/// Installs the signed APK's managed book resources before updating its catalog.
/// The separate study-list database is never opened here.
class BundledLibraryContent {
  static const manifestAsset = 'assets/bundled_library/manifest.json';

  static Future<int> ensure({
    required Database destination,
    required String libraryRoot,
    AssetBundle? assets,
    Set<String>? onlyItemIds,
  }) async {
    final bundle = assets ?? rootBundle;
    final manifest =
        jsonDecode(await bundle.loadString(manifestAsset))
            as Map<String, dynamic>;
    final revision = manifest['revision'] as String;
    final allBooks = (manifest['books'] as List).cast<Map>();
    if (onlyItemIds != null &&
        (onlyItemIds.isEmpty ||
            !allBooks.map((b) => b['id']).toSet().containsAll(onlyItemIds))) {
      throw const FormatException('Unknown selected publisher book');
    }
    final books = allBooks
        .where(
          (book) => onlyItemIds == null || onlyItemIds.contains(book['id']),
        )
        .toList();
    final prefixes = [
      for (final book in books)
        if (book['resource_prefix'] is String)
          book['resource_prefix'] as String,
    ];
    if (onlyItemIds != null && prefixes.length != books.length) {
      throw const FormatException(
        'Selected publisher book has no resource boundary',
      );
    }
    final ids = books.map((book) => book['id'] as String).toSet();
    if (revision.isEmpty || ids.isEmpty)
      throw const FormatException('Invalid bundled catalog manifest');
    final itemRevisions = <String, String>{
      for (final raw in books)
        raw['id'] as String: raw['revision'] as String? ?? revision,
    };
    final resources = <String, Map<String, dynamic>>{};
    for (final raw in manifest['resources'] as List) {
      final row = raw as Map<String, dynamic>;
      final relative = row['destination'] as String;
      if (onlyItemIds != null && !prefixes.any(relative.startsWith)) continue;
      // Bundles own only this subtree, never Databases, notes, or user imports.
      if (!relative.startsWith('Research/ManagedBundles/') ||
          p.isAbsolute(relative) ||
          relative.split(RegExp(r'[/\\]')).contains('..')) {
        throw const FormatException('Invalid managed resource destination');
      }
      final output = p.normalize(p.join(libraryRoot, relative));
      if (!p.isWithin(p.normalize(libraryRoot), output)) {
        throw const FormatException('Managed resource escapes library root');
      }
      final data = await bundle.load(row['asset'] as String);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.length != row['bytes'] ||
          sha256.convert(bytes).toString() != row['sha256']) {
        throw const FormatException(
          'Bundled book resource failed integrity check',
        );
      }
      if (resources.containsKey(output))
        throw const FormatException('Duplicate bundled resource destination');
      resources[output] = row;
    }
    // Validate every resource before touching the filesystem or catalog.
    for (final entry in resources.entries) {
      final file = File(entry.key);
      if (await file.exists() &&
          sha256.convert(await file.readAsBytes()).toString() ==
              entry.value['sha256'])
        continue;
      // Keep only one resource in memory; the illustrated BRHC source is large.
      final data = await bundle.load(entry.value['asset'] as String);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.length != entry.value['bytes'] ||
          sha256.convert(bytes).toString() != entry.value['sha256']) {
        throw const FormatException(
          'Bundled resource changed after validation',
        );
      }
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.installing');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    }
    // iOS can relocate the sandbox after an update. Restore only missing
    // publisher covers from the already validated resources, without replacing
    // a valid user cover or touching the book text and reading data.
    for (final raw in books) {
      final book = raw as Map<String, dynamic>;
      final relativeCover = book['cover_path'] as String?;
      if (relativeCover == null) continue;
      final cover = p.normalize(p.join(libraryRoot, relativeCover));
      if (!resources.containsKey(cover)) {
        throw const FormatException(
          'Managed cover is not a validated resource',
        );
      }
      final rows = await destination.query(
        'library_items',
        columns: ['cover_path'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [book['id']],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final stored = rows.single['cover_path']?.toString() ?? '';
      if (stored.startsWith('assets/') ||
          (stored.isNotEmpty && File(stored).existsSync()) ||
          (stored == relativeCover && File(cover).existsSync())) {
        continue;
      }
      await destination.update(
        'library_items',
        {'cover_path': relativeCover},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [book['id']],
      );
    }
    final markerTable = await destination.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='bundled_library_updates'",
    );
    if (markerTable.isNotEmpty) {
      final rows = await destination.query('bundled_library_updates');
      if (ids.every(
        (id) => rows.any(
          (row) =>
              row['library_item_id'] == id &&
              row['revision'] == itemRevisions[id],
        ),
      ))
        return 0;
    }
    final catalogData = await bundle.load(manifest['catalog_asset'] as String);
    final catalogBytes = catalogData.buffer.asUint8List(
      catalogData.offsetInBytes,
      catalogData.lengthInBytes,
    );
    if (sha256.convert(catalogBytes).toString() != manifest['catalog_sha256']) {
      throw const FormatException('Bundled catalog failed integrity check');
    }
    final temp = await Directory.systemTemp.createTemp('studybible-content-');
    Database? source;
    try {
      final file = File(p.join(temp.path, 'catalog.db'));
      await file.writeAsBytes(catalogBytes, flush: true);
      source = await openReadOnlyDatabase(file.path, singleInstance: false);
      return await BundledLibraryCatalogUpdate.apply(
        destination: destination,
        source: source,
        managedItemIds: ids,
        revision: revision,
        itemRevisions: itemRevisions,
        resourceRoot: libraryRoot,
      );
    } finally {
      await source?.close();
      await temp.delete(recursive: true);
    }
  }
}

class BundledLibraryPreparationException implements Exception {
  const BundledLibraryPreparationException();
  @override
  String toString() =>
      'The included books could not be prepared. Please retry library setup.';
}
