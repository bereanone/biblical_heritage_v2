import 'dart:async';

import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_controller.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_models.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_ports.dart';

/// Stand-in for Kokoro: never loads a model. Clips complete on their own
/// (auto) or when the test says so (manual), and every file's life is tracked.
class FakeRenderer implements TagClipRenderer {
  FakeRenderer({this.auto = true});

  bool auto;
  final List<TagSpeechClip> requested = [];
  final Map<String, Completer<String>> _pending = {};
  final Set<String> live = {};
  final List<String> discarded = [];
  final Set<String> failing = {};
  int inFlight = 0;
  int maxInFlight = 0;
  int maxLive = 0;
  int _serial = 0;

  /// Texts in the order the controller asked for them.
  List<String> get requestedTexts => [for (final c in requested) c.text];

  @override
  Future<String> render(TagSpeechClip clip) {
    requested.add(clip);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final path = 'audio/${++_serial}:${clip.text}';
    final done = Completer<String>();
    _pending[path] = done;
    if (auto) Future<void>.microtask(() => complete(path));
    return done.future;
  }

  /// Paths handed out but not yet completed, oldest first.
  List<String> get pendingPaths => _pending.keys.toList();

  void complete(String path) {
    final done = _pending.remove(path);
    if (done == null) return;
    inFlight--;
    if (failing.contains(_textOf(path))) {
      done.completeError(StateError('render failed for ${_textOf(path)}'));
      return;
    }
    live.add(path);
    if (live.length > maxLive) maxLive = live.length;
    done.complete(path);
  }

  void fail(String path) {
    final done = _pending.remove(path);
    if (done == null) return;
    inFlight--;
    done.completeError(StateError('render failed'));
  }

  void completeAll() {
    for (final path in pendingPaths) {
      complete(path);
    }
  }

  @override
  Future<void> discard(String path) async {
    discarded.add(path);
    live.remove(path);
  }

  static String _textOf(String path) => path.substring(path.indexOf(':') + 1);
}

class FakePlayer implements TagClipPlayer {
  final StreamController<void> _completions = StreamController.broadcast();
  final StreamController<Object> _failures = StreamController.broadcast();
  final List<String> played = [];
  final List<String> preloaded = [];
  String? current;
  bool paused = false;
  int resumeCount = 0;
  int stopCount = 0;
  bool disposed = false;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<Object> get failures => _failures.stream;

  /// Text of every clip started, in order.
  List<String> get playedTexts => [for (final p in played) textOf(p)];

  static String textOf(String path) => path.substring(path.indexOf(':') + 1);

  @override
  Future<void> prepareNext(String path) async => preloaded.add(path);

  @override
  Future<void> play(String path) async {
    played.add(path);
    current = path;
    paused = false;
  }

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async {
    paused = false;
    resumeCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    current = null;
    paused = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _completions.close();
    await _failures.close();
  }

  /// The clip that is playing ends by itself.
  void finishCurrent() => _completions.add(null);

  void failCurrent(Object error) => _failures.add(error);
}

TagPlaybackItem fakeItem(
  int index, {
  int verses = 1,
  int notes = 0,
  String? label,
}) => TagPlaybackItem(
  entryId: index,
  label: label ?? 'Ref $index',
  preview: 'preview $index',
  contentClips: [
    for (var i = 0; i < verses; i++)
      TagSpeechClip(text: 'v$index.$i', kind: TagClipKind.verse),
  ],
  noteClips: [
    for (var i = 0; i < notes; i++)
      TagSpeechClip(text: 'n$index.$i', kind: TagClipKind.note),
  ],
);

class Harness {
  Harness(
    List<TagPlaybackItem> items, {
    bool auto = true,
    bool includeNotes = true,
    bool loop = false,
    int maxAhead = 2,
    int backgroundMaxAhead = 5,
    int maxConcurrentRenders = 2,
    Duration renderTimeout = const Duration(seconds: 90),
  }) : renderer = FakeRenderer(auto: auto),
       player = FakePlayer() {
    controller = TagPlaybackController(
      items: items,
      renderer: renderer,
      player: player,
      includeNotes: includeNotes,
      loop: loop,
      maxAhead: maxAhead,
      backgroundMaxAhead: backgroundMaxAhead,
      maxConcurrentRenders: maxConcurrentRenders,
      renderTimeout: renderTimeout,
    );
  }

  final FakeRenderer renderer;
  final FakePlayer player;
  late final TagPlaybackController controller;

  /// Lets queued microtasks (synthesis completions, player calls) run.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// The current clip ends and the next one starts.
  Future<void> finishClip() async {
    player.finishCurrent();
    await settle();
  }

  /// Plays a whole pass by finishing clips until playback stops.
  Future<void> runToEnd({int limit = 200}) async {
    for (var i = 0; i < limit; i++) {
      if (!controller.isPlaying) return;
      await finishClip();
    }
  }
}
