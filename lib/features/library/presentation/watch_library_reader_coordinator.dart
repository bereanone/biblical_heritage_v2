import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'watch_library_playback.dart';

/// An existing book route replaces itself, preserving its Bible/theme callbacks.
class WatchLibraryReaderNavigation {
  static final _readers = <Object, Future<bool> Function(String)>{};
  static void register(Object owner, Future<bool> Function(String) open) =>
      _readers[owner] = open;
  static void unregister(Object owner) => _readers.remove(owner);

  static Future<bool> open(String bookId) async {
    for (final open in List.of(_readers.values).reversed) {
      if (await open(bookId)) return true;
    }
    return false;
  }
}

/// Follow book choices, without pushing another route for position updates.
class WatchLibraryReaderCoordinator with WidgetsBindingObserver {
  WatchLibraryReaderCoordinator({
    required this.playback,
    required this.openBook,
  });
  final ValueListenable<WatchLibraryPlayback?> playback;
  final Future<void> Function(String) openBook;
  String? _lastBook;
  bool _disposed = false;
  int _revision = 0;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    playback.addListener(_changed);
    _changed();
  }

  void dispose() {
    _disposed = true;
    _revision++;
    playback.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _changed();
  }

  void _changed() {
    final state = playback.value;
    if (state == null || !state.nativePlayback) {
      _lastBook = null;
      _revision++;
      return;
    }
    if (state.bookId.isEmpty || state.bookId == _lastBook) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _lastBook = state.bookId;
    final revision = ++_revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && revision == _revision) {
        unawaited(_open(state.bookId, revision));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _open(String bookId, int revision) async {
    try {
      if (await WatchLibraryReaderNavigation.open(bookId)) return;
      if (!_disposed && revision == _revision) await openBook(bookId);
    } catch (error) {
      if (revision == _revision) _lastBook = null;
      debugPrint('Watch-selected book could not open: $error');
    }
  }
}
