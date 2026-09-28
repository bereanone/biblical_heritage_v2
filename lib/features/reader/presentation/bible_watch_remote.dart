import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// The iPhone reader owns ordinary playback; native iOS keeps a small recorded
/// audio fallback for Watch commands delivered before the reader is mounted.
class BibleWatchRemote {
  BibleWatchRemote._();

  static final BibleWatchRemote instance = BibleWatchRemote._();
  static const MethodChannel _channel = MethodChannel(
    'studybible/watch_remote',
  );

  bool get supported => Platform.isIOS;
  bool _attached = false;

  Future<Map<String, Object?>?> attach(
    Future<void> Function(String command) onCommand,
  ) async {
    if (!supported) return null;
    _attached = true;
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
    await _channel.invokeMethod<void>('publishState', {
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
    });
  }
}
