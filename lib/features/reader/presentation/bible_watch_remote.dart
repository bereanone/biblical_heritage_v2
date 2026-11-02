import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../library/presentation/watch_library_catalog.dart';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// The iPhone reader owns ordinary playback; native iOS keeps a small recorded
/// audio fallback for Watch commands delivered before the reader is mounted.
class BibleWatchRemote {
  BibleWatchRemote._()
    : _channel = const MethodChannel('studybible/watch_remote'),
      _supportedOverride = null;
  @visibleForTesting
  BibleWatchRemote.forTesting(this._channel) : _supportedOverride = true;

  static final BibleWatchRemote instance = BibleWatchRemote._();
  final MethodChannel _channel;
  final bool? _supportedOverride;

  bool get supported => _supportedOverride ?? Platform.isIOS;
  bool _attached = false;
  String? _lastPublished;

  Future<Map<String, Object?>?> attach(
    Future<void> Function(String command) onCommand,
  ) async {
    if (!supported) return null;
    _attached = true;
    _lastPublished = null;
    WatchLibraryCatalog.initialize();
    unawaited(WatchLibraryCatalog.refresh());
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'command' && call.arguments is String) {
        await onCommand(call.arguments as String);
      }
    });
    final state = await _channel.invokeMapMethod<String, Object?>(
      'readerAttached',
    );
    return state;
  }

  Future<void> detach() async {
    if (!supported || !_attached) return;
    _attached = false;
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod<void>('readerDetached');
  }

  Future<Map<String, Object?>?> handoffNative() async {
    if (!supported || !_attached) return null;
    return _channel.invokeMapMethod<String, Object?>('handoffNative');
  }

  Future<void> publish({
    required int book,
    required int chapter,
    required int verse,
    required String title,
    required String loop,
    required String lastLoop,
    required bool playing,
    required bool pending,
    required int loopTargetBook,
    required int loopTargetChapter,
    required int loopTargetVerse,
  }) async {
    if (!supported || !_attached) return;
    final state = <String, Object?>{
      'book': book,
      'chapter': chapter,
      'verse': verse,
      'title': title,
      'loop': loop,
      'lastLoop': lastLoop,
      'playing': playing,
      'pending': pending,
      'loopTargetBook': loopTargetBook,
      'loopTargetChapter': loopTargetChapter,
      'loopTargetVerse': loopTargetVerse,
    };
    final signature = jsonEncode(state);
    if (_lastPublished == signature) return;
    final previous = _lastPublished;
    _lastPublished = signature;
    try {
      await _channel.invokeMethod<void>('publishState', state);
    } catch (_) {
      if (_lastPublished == signature) _lastPublished = previous;
      rethrow;
    }
  }
}
