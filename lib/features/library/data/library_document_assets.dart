import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'library_document_models.dart';

/// Immutable image bytes belonging to one explicit item/source revision.
/// Authored layout, rotation, captions and citation targets remain on blocks.
class LibraryDocumentAsset {
  LibraryDocumentAsset(this.name, List<int> bytes)
    : bytes = Uint8List.fromList(bytes) {
    validate();
  }

  final String name;
  final Uint8List bytes;
  String get hash => name.split('.').first;

  void validate() {
    if (!RegExp(r'^[a-f0-9]{64}\.[a-z0-9]{1,10}$').hasMatch(name) ||
        sha256.convert(bytes).toString() != hash) {
      throw FormatException(
        'Canonical asset name/content hash mismatch: $name',
      );
    }
  }

  String get mediaType => switch (p.extension(name)) {
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.svg' => 'image/svg+xml',
    '.bmp' => 'image/bmp',
    '.tif' || '.tiff' => 'image/tiff',
    _ => 'application/octet-stream',
  };
}

class LibraryDocumentAssets {
  const LibraryDocumentAssets._();

  static Set<String> imageNames(List<Map<String, Object?>> blocks) => {
    for (final block in blocks)
      for (final node in LibraryFormattedContent.fromJson(
        block['formatted_content'] as String?,
      ).nodes)
        if (node['type'] == 'image') node['source']?.toString() ?? '',
  };

  /// Read only the images actually referenced by this accepted generation.
  /// Never copy unrelated files left in an extraction directory.
  static Future<List<LibraryDocumentAsset>> collect({
    required List<Map<String, Object?>> blocks,
    required Directory directory,
  }) async {
    final result = <LibraryDocumentAsset>[];
    for (final name in imageNames(blocks).toList()..sort()) {
      if (!RegExp(r'^[a-f0-9]{64}\.[a-z0-9]{1,10}$').hasMatch(name)) {
        throw FormatException('Unsafe or unhashed canonical image: $name');
      }
      final file = File(p.join(directory.path, name));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FileSystemException('Missing regular canonical image', file.path);
      }
      result.add(LibraryDocumentAsset(name, await file.readAsBytes()));
    }
    return result;
  }

  /// Call in the same transaction that activates the matching document.
  /// A failed write rolls back the generation; old revisions stay intact.
  static Future<void> store(
    DatabaseExecutor db, {
    required String itemId,
    required String sourceHash,
    required List<LibraryDocumentAsset> assets,
    String? coverAssetName,
  }) async {
    _checkHash(sourceHash);
    final names = assets.map((asset) => asset.name).toSet();
    if (names.length != assets.length ||
        (coverAssetName != null && !names.contains(coverAssetName))) {
      throw StateError('Incomplete or duplicate document asset manifest.');
    }
    final existing = await db.query(
      'library_document_asset_sets',
      where: 'library_item_id=? AND source_hash=?',
      whereArgs: [itemId, sourceHash],
    );
    if (existing.isNotEmpty) {
      final stored = await db.query(
        'library_document_assets',
        where: 'library_item_id=? AND source_hash=?',
        whereArgs: [itemId, sourceHash],
      );
      final storedNames = stored.map((row) => row['asset_name']).toSet();
      if (stored.any(
        (row) =>
            (row['asset_name'] as String).split('.').first !=
            row['asset_sha256'],
      )) {
        throw StateError('Stored asset mapping has inconsistent identity.');
      }
      if (storedNames.length != names.length ||
          !storedNames.containsAll(names) ||
          existing.single['asset_count'] != names.length ||
          (coverAssetName != null &&
              existing.single['cover_asset_name'] != coverAssetName)) {
        throw StateError(
          'An immutable asset manifest changed for this source.',
        );
      }
    }
    for (final asset in assets) {
      asset.validate();
      final old = await db.query(
        'library_asset_blobs',
        where: 'sha256=?',
        whereArgs: [asset.hash],
      );
      if (old.isEmpty) {
        await db.insert('library_asset_blobs', {
          'sha256': asset.hash,
          'byte_length': asset.bytes.length,
          'media_type': asset.mediaType,
          'data': asset.bytes,
        });
      } else {
        LibraryDocumentAsset(asset.name, old.single['data'] as List<int>);
      }
    }
    if (existing.isNotEmpty) return;
    await db.insert('library_document_asset_sets', {
      'library_item_id': itemId,
      'source_hash': sourceHash,
      'asset_count': assets.length,
      'cover_asset_name': coverAssetName,
      'stored_at': DateTime.now().toUtc().toIso8601String(),
    });
    for (final asset in assets) {
      await db.insert('library_document_assets', {
        'library_item_id': itemId,
        'source_hash': sourceHash,
        'asset_name': asset.name,
        'asset_sha256': asset.hash,
        'review_status': 'unreviewed',
      });
    }
  }

  /// Returns null for legacy generations without embedded assets. For an
  /// embedded generation, completeness and every digest are verified before
  /// creating an isolated, disposable cache. No EPUB or network is needed.
  static Future<Directory?> restore({
    required Database db,
    required String itemId,
    required Directory libraryRoot,
  }) async {
    final sets = await db.rawQuery(
      '''
      SELECT a.* FROM library_document_asset_sets a
      JOIN library_document_conversion c
        ON c.library_item_id=a.library_item_id AND c.source_hash=a.source_hash
      WHERE a.library_item_id=? AND c.status='complete'
    ''',
      [itemId],
    );
    if (sets.isEmpty) return null;
    final sourceHash = sets.single['source_hash'] as String;
    _checkHash(sourceHash);
    final rows = await db.rawQuery(
      '''
      SELECT a.asset_name, a.asset_sha256, b.data
      FROM library_document_assets a
      JOIN library_asset_blobs b ON b.sha256=a.asset_sha256
      WHERE a.library_item_id=? AND a.source_hash=? ORDER BY a.asset_name
    ''',
      [itemId, sourceHash],
    );
    final blocks = await db.query(
      'library_document_blocks',
      columns: ['formatted_content'],
      where: 'library_item_id=?',
      whereArgs: [itemId],
    );
    final expected = imageNames(blocks);
    final names = rows.map((row) => row['asset_name']).toSet();
    if (rows.length != sets.single['asset_count'] ||
        names.length != expected.length ||
        !names.containsAll(expected)) {
      throw StateError('Incomplete embedded image set for this document.');
    }
    final assets = [
      for (final row in rows)
        LibraryDocumentAsset(
          row['asset_name'] as String,
          row['data'] as List<int>,
        ),
    ];
    for (var i = 0; i < assets.length; i++) {
      if (assets[i].hash != rows[i]['asset_sha256']) {
        throw StateError('Embedded image identity mismatch.');
      }
    }
    final target = await _cacheDirectory(libraryRoot, itemId, sourceHash);
    for (final asset in assets) {
      await _cacheAsset(target, asset);
    }
    return target;
  }

  /// Cover bytes use the same revision-scoped image set as the reader.
  /// This avoids shipping a device-specific absolute cover path.
  static Future<Map<String, String>> restoreCovers({
    required Database db,
    required Set<String> itemIds,
    required Directory libraryRoot,
  }) async {
    // Catalog hydration can hand this a legacy user database that predates
    // the canonical asset tables; such libraries simply have no embedded covers.
    final hasAssetSets = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'library_document_asset_sets' LIMIT 1",
    );
    if (hasAssetSets.isEmpty) return const {};
    final rows = await db.rawQuery('''
      SELECT s.library_item_id, s.source_hash, a.asset_name, a.asset_sha256, b.data
      FROM library_document_asset_sets s
      JOIN library_document_conversion c ON c.library_item_id=s.library_item_id
        AND c.source_hash=s.source_hash AND c.status='complete'
      JOIN library_document_assets a ON a.library_item_id=s.library_item_id
        AND a.source_hash=s.source_hash AND a.asset_name=s.cover_asset_name
      JOIN library_asset_blobs b ON b.sha256=a.asset_sha256
      WHERE s.cover_asset_name IS NOT NULL
    ''');
    final result = <String, String>{};
    for (final row in rows) {
      final itemId = row['library_item_id'] as String;
      if (!itemIds.contains(itemId)) continue;
      final asset = LibraryDocumentAsset(
        row['asset_name'] as String,
        row['data'] as List<int>,
      );
      if (asset.hash != row['asset_sha256']) {
        throw StateError('Embedded cover identity mismatch.');
      }
      final directory = await _cacheDirectory(
        libraryRoot,
        itemId,
        row['source_hash'] as String,
      );
      result[itemId] = (await _cacheAsset(directory, asset)).path;
    }
    return result;
  }

  static void _checkHash(String value) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const FormatException('Invalid source revision hash.');
    }
  }

  static Future<Directory> _cacheDirectory(
    Directory root,
    String itemId,
    String sourceHash,
  ) async {
    _checkHash(sourceHash);
    var directory = root;
    for (final component in [
      '_database_assets',
      sha256.convert(utf8.encode(itemId)).toString(),
      sourceHash,
    ]) {
      directory = Directory(p.join(directory.path, component));
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) {
        await directory.create();
      } else if (type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'Unsafe canonical cache directory',
          directory.path,
        );
      }
    }
    return directory;
  }

  static Future<File> _cacheAsset(
    Directory directory,
    LibraryDocumentAsset asset,
  ) async {
    final file = File(p.join(directory.path, asset.name));
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      // A conflicting file is never overwritten, even in the disposable cache.
      LibraryDocumentAsset(asset.name, await file.readAsBytes());
      return file;
    }
    if (type != FileSystemEntityType.notFound) {
      throw FileSystemException('Unsafe canonical cache file', file.path);
    }
    // A temporary sibling plus rename prevents exposing a partially written image.
    final temp = await Directory(directory.path).createTemp('.asset-');
    try {
      final staged = File(p.join(temp.path, asset.name));
      await staged.writeAsBytes(asset.bytes, flush: true);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return _cacheAsset(directory, asset);
      }
      return await staged.rename(file.path);
    } finally {
      await temp.delete(recursive: true);
    }
  }
}
