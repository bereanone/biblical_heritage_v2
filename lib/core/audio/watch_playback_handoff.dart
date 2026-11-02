/// Readers acknowledge an actual pause before the Watch starts another player.
class WatchPlaybackHandoff {
  static final Map<Object, Future<void> Function()> _readers = {};
  static void register(Object owner, Future<void> Function() pause) =>
      _readers[owner] = pause;
  static void unregister(Object owner) => _readers.remove(owner);
  /// A remote switch needs a real pause, but not a complete catalog rebuild.
  static Future<void> pauseForRemote({
    required Future<void> Function() refresh,
  }) async {
    await pauseReaders();
    // Catalog failures are reported by the catalog owner, independently of pause.
    refresh().ignore();
  }

  static Future<void> pauseReaders() async {
    for (final pause in List.of(_readers.values)) {
      await pause();
    }
  }
}
