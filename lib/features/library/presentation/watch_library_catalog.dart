import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseExecutor;
import '../../../core/audio/watch_playback_handoff.dart';
import '../../../core/database/elibrary_database.dart';
import '../../../core/theme/app_settings_service.dart';
import '../data/library_catalog_service.dart';
import '../data/library_item_availability.dart';
import 'recorded_library_audio_controls.dart';
import 'watch_library_playback.dart';

/// The Watch receives names and contents only. Recordings stay on the iPhone.
class WatchLibraryCatalog {
  static const channel = MethodChannel('studybible/watch_library');
  static Future<void>? _pending;
  static bool _refreshAgain = false;
  static bool _listening = false;
  static final playback = ValueNotifier<WatchLibraryPlayback?>(null);

  static void _receivePlayback(Object? value) {
    playback.value = WatchLibraryPlayback.fromNative(value);
  }

  static Future<void> _readPlayback() async {
    try {
      _receivePlayback(await channel.invokeMethod<Object?>('readerState'));
    } on MissingPluginException {
      /* Older native counterpart. */
    } on PlatformException catch (error) {
      debugPrint('Watch playback state unavailable: $error');
    }
  }

  static Future<void> command(
    String bookId,
    String command, {
    int? chapter,
    Duration? position,
    bool? play,
  }) async {
    final state = await channel.invokeMethod<Object?>('readerCommand', {
      'bookId': bookId,
      'command': command,
      if (chapter != null) 'chapter': chapter,
      if (position != null) 'position_ms': position.inMilliseconds,
      if (play != null) 'play': play,
    });
    _receivePlayback(state);
  }

  static void initialize() {
    if (!Platform.isIOS || _listening) return;
    _listening = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'playbackChanged') {
        _receivePlayback(call.arguments);
        return null;
      }
      if (call.method == 'pauseReaders') {
        // The completed shelf is published independently through catalogChanged.
        await WatchPlaybackHandoff.pauseForRemote(refresh: refresh);
        return null;
      }
      throw MissingPluginException('Unsupported Watch library request');
    });
    unawaited(_readPlayback());
  }

  static Future<void> refresh() {
    if (!Platform.isIOS) return Future.value();
    initialize();
    _refreshAgain = true;
    return _pending ??= (() async {
      do {
        _refreshAgain = false;
        try {
          await _refresh();
        } catch (error) {
          debugPrint('Watch audio shelf could not refresh: $error');
          await _write(const []);
        }
      } while (_refreshAgain);
    })().whenComplete(() => _pending = null);
  }

  static Future<void> _refresh() async {
    final raw = await AppSettingsService.instance.loadRawSetting(
      'elibrary_top_shelf_v1',
    );
    final ids = raw == null
        ? <String>[]
        : (jsonDecode(raw) as List).whereType<String>().toSet().toList();
    final items = await LibraryCatalogService.instance.loadItems(
      hydrateMetadata: false,
    );
    final docs = await getApplicationDocumentsDirectory();
    final db = await ELibraryDatabase.instance.database;
    await _write(
      await buildShelf(
        docs: docs,
        items: items,
        ids: ids,
        database: db,
        readPosition: (id) => AppSettingsService.instance.loadRawSetting(
          'library_recorded_audio_position:$id',
        ),
      ),
    );
  }

  @visibleForTesting
  static Future<List<Map<String, Object?>>> buildShelf({
    required Directory docs,
    required List<LibraryCatalogItem> items,
    required List<String> ids,
    required DatabaseExecutor database,
    required Future<String?> Function(String id) readPosition,
  }) async {
    final db = database;
    final byId = {for (final item in items) item.id: item};
    final result = <Map<String, Object?>>[];
    for (final id in ids.toSet()) {
      final item = byId[id];
      if (item == null || !libraryItemIsNormallyReadable(item)) continue;
      final package = await RecordedLibraryAudioPackage.findIn(
        Directory(p.join(docs.path, 'elibrary_audio')),
        item.displayTitle,
        sourceHash: item.fileHash,
      );
      if (package == null || package.tracks.isEmpty) continue;
      final directory = package.tracks.first.file.parent;
      if (!p.isWithin(p.join(docs.path, 'elibrary_audio'), directory.path)) {
        continue;
      }
      final manifest = File(p.join(directory.path, 'audio-manifest.json'));
      if (!await manifest.exists()) continue;
      final positions = <int, Map<String, Object?>>{};
      final textPositions = <String, Map<String, Object?>>{};
      for (final track in package.tracks) {
        for (var i = 0; i < track.cues.length; i++) {
          final cue = track.cues[i];
          final target = <String, Object?>{
            'chapter': track.chapter,
            'paragraph': i + 1,
          };
          final cursor = int.tryParse(cue.sourceCursor ?? '');
          if (cursor != null) positions[cursor] = target;
          textPositions.putIfAbsent(
            cue.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
            () => target,
          );
        }
      }
      final blocks = await db.query(
        'library_document_blocks',
        columns: ['id', 'display_order', 'plain_text'],
        where: 'library_item_id=?',
        whereArgs: [id],
        orderBy: 'display_order',
      );
      final orderById = {
        for (final b in blocks) b['id']: b['display_order'] as int,
      };
      final blockPositions = <int, Map<String, Object?>>{};
      for (final block in blocks) {
        final target =
            textPositions[block['plain_text']
                .toString()
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim()];
        if (target != null) {
          blockPositions[block['display_order'] as int] = target;
        }
      }
      blockPositions.addAll(positions);
      final orders = blockPositions.keys.toList()..sort();
      final navigation = await db.query(
        'library_document_navigation',
        columns: ['label', 'depth', 'target_block_id'],
        where: 'library_item_id=?',
        whereArgs: [id],
        orderBy: 'display_order',
      );
      final toc = <Map<String, Object?>>[];
      for (final n in navigation) {
        final order = orderById[n['target_block_id']];
        if (order == null) continue;
        final next = orders.where((v) => v >= order).firstOrNull;
        // Front matter without recordings is not an audio destination.
        if (next == null || next - order > 8) continue;
        toc.add({
          'title': n['label'].toString(),
          'depth': n['depth'] ?? 0,
          ...blockPositions[next]!,
        });
      }
      if (toc.isEmpty) {
        toc.addAll(
          package.tracks.map(
            (t) => <String, Object?>{
              'title': t.title,
              'chapter': t.chapter,
              'paragraph': 1,
              'depth': 0,
            },
          ),
        );
      }
      final rawPosition = await readPosition(id);
      final saved = rawPosition == null
          ? null
          : jsonEncode(
              package.remapSavedPosition(
                Map<String, dynamic>.from(jsonDecode(rawPosition) as Map),
              ),
            );
      result.add({
        'id': id,
        'title': item.displayTitle,
        'sourceHash': item.fileHash ?? '',
        'manifest': p.relative(manifest.path, from: docs.path),
        'toc': toc,
        'position': saved == null ? null : jsonDecode(saved),
        'positionRevision': sha256.convert(utf8.encode(saved ?? '')).toString(),
      });
    }
    return result;
  }

  static Future<void> _write(List<Map<String, Object?>> books) async {
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, 'watch-audio-shelf.json'));
    final content = jsonEncode({'schema': 1, 'books': books});
    if (await file.exists() && await file.readAsString() == content) return;
    final pending = File('${file.path}.pending');
    await pending.writeAsString(content, flush: true);
    await pending.rename(file.path);
    try {
      await channel.invokeMethod<void>('catalogChanged');
    } on MissingPluginException {
      /* Older installed native counterpart. */
    }
  }

  static Future<void> pauseNative() async {
    if (!Platform.isIOS) return;
    initialize();
    await channel.invokeMethod<void>('pauseNative');
  }
}
