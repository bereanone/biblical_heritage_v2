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
  }) async {
    final bundle = assets ?? rootBundle;
    final manifest =
        jsonDecode(await bundle.loadString(manifestAsset))
            as Map<String, dynamic>;
    final revision = manifest['revision'] as String;
    final ids = (manifest['books'] as List)
        .map((book) => book['id'] as String)
        .toSet();
    if (revision.isEmpty || ids.isEmpty)
      throw const FormatException('Invalid bundled catalog manifest');
    final resources = <String, Uint8List>{};
    for (final raw in manifest['resources'] as List) {
      final row = raw as Map<String, dynamic>;
      final relative = row['destination'] as String;
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
      resources[output] = bytes;
    }
    // Validate every resource before touching the filesystem or catalog.
    for (final entry in resources.entries) {
      final file = File(entry.key);
      if (await file.exists() &&
          sha256.convert(await file.readAsBytes()).toString() ==
              sha256.convert(entry.value).toString())
        continue;
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.installing');
      await temporary.writeAsBytes(entry.value, flush: true);
      await temporary.rename(file.path);
    }
    final markerTable = await destination.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='bundled_library_updates'",
    );
    if (markerTable.isNotEmpty) {
      final rows = await destination.query('bundled_library_updates');
      if (ids.every(
        (id) => rows.any(
          (row) => row['library_item_id'] == id && row['revision'] == revision,
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
