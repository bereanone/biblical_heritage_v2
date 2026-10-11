import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'library_speech_queue.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/audio/narration_media_session.dart';
import '../../../core/theme/app_settings_service.dart';

class RecordedLibraryAudioTrack {
  const RecordedLibraryAudioTrack(
    this.chapter,
    this.title,
    this.file, {
    this.cues = const [],
  });
  final int chapter;
  final String title;
  final File file;
  final List<RecordedLibraryAudioCue> cues;
}

class RecordedLibraryAudioCue {
  const RecordedLibraryAudioCue(
    this.start,
    this.text, {
    this.phrases = const [],
  });
  final Duration start;
  final String text;
  final List<RecordedLibraryAudioCue> phrases;
}

class RecordedLibraryAudioPackage {
  const RecordedLibraryAudioPackage(
    this.title,
    this.tracks, {
    this.totalChapters,
  });
  final String title;
  final List<RecordedLibraryAudioTrack> tracks;
  final int? totalChapters;
  bool get isComplete =>
      totalChapters != null &&
      tracks.length == totalChapters &&
      List.generate(
        tracks.length,
        (i) => tracks[i].chapter == i + 1,
      ).every((v) => v);
  static String normalize(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  static Future<RecordedLibraryAudioPackage?> find(String title) async {
    final docs = await getApplicationDocumentsDirectory();
    return findIn(Directory('${docs.path}/elibrary_audio'), title);
  }

  static Future<RecordedLibraryAudioPackage?> findIn(
    Directory root,
    String title,
  ) async {
    if (!await root.exists()) return null;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final manifest = File('${entity.path}/audio-manifest.json');
      if (!await manifest.exists()) continue;
      try {
        final json =
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
        if (normalize(json['title'] as String) != normalize(title)) continue;
        final tracks = <RecordedLibraryAudioTrack>[];
        for (final row in json['tracks'] as List) {
          final name = row['file'] as String;
          // Only files owned by this package are playable.
          if (!RegExp(r'^[A-Za-z0-9 _.-]+\.mp3$').hasMatch(name) ||
              name.contains('..')) {
            continue;
          }
          final file = File('${entity.path}/$name');
          if (!await file.exists() || await file.length() == 0) continue;
          tracks.add(
            RecordedLibraryAudioTrack(
              row['chapter'] as int,
              row['title'] as String,
              file,
              cues: [
                for (final cue in row['cues'] as List? ?? const [])
                  RecordedLibraryAudioCue(
                    Duration(milliseconds: (cue['start_ms'] as num).round()),
                    cue['text'] as String,
                    phrases: [
                      for (final phrase in cue['phrases'] as List? ?? const [])
                        RecordedLibraryAudioCue(
                          Duration(
                            milliseconds: (phrase['start_ms'] as num).round(),
                          ),
                          phrase['text'] as String,
                        ),
                    ],
                  ),
              ],
            ),
          );
        }
        tracks.sort((a, b) => a.chapter.compareTo(b.chapter));
        if (tracks.isNotEmpty) {
          return RecordedLibraryAudioPackage(
            json['title'] as String,
            tracks,
            totalChapters: json['total_chapters'] as int?,
          );
        }
      } catch (_) {
        /* Ignore an incomplete transfer; synthesis remains available. */
      }
    }
    return null;
  }
}

class RecordedLibraryAudioControls extends StatefulWidget {
  const RecordedLibraryAudioControls({
    super.key,
    required this.package,
    required this.bookId,
    required this.beforePlay,
    required this.load,
    required this.reveal,
    required this.startCursor,
    required this.selectedCursor,
  });
  final RecordedLibraryAudioPackage package;
  final String bookId;
  final Future<void> Function() beforePlay;
  final Future<LibrarySpeechItem?> Function(String) load;
  final Future<void> Function(LibrarySpeechItem) reveal;
  final String startCursor;
  final String? Function() selectedCursor;
  @override
  State<RecordedLibraryAudioControls> createState() =>
      _RecordedLibraryAudioControlsState();
}

class _RecordedLibraryAudioControlsState
    extends State<RecordedLibraryAudioControls>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  NarrationMediaLease? _lease;
  int _index = 0;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _busy = false;
  bool _loaded = false;
  final Map<String, LibrarySpeechItem> _cueItems = {};
  final Map<String, LibrarySpeechItem> _phraseItems = {};
  String? _lastCue;
  String? _lastRequestedCursor;
  String? _loop; // null, chapter, or paragraph
  Duration? _loopStart;
  Duration? _loopEnd;
  int? _loopCueIndex;
  bool _loopSeeking = false;
  Future<void> _chooseLoop() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Loop off'),
              onTap: () => Navigator.pop(context, 'off'),
            ),
            ListTile(
              title: const Text('Loop book'),
              enabled: true,
              subtitle: Text(
                widget.package.isComplete
                    ? widget.package.title
                    : '${widget.package.tracks.length} downloaded chapters',
              ),
              onTap: () => Navigator.pop(context, 'book'),
            ),
            ListTile(
              title: const Text('Loop chapter'),
              subtitle: Text(widget.package.tracks[_index].title),
              onTap: () => Navigator.pop(context, 'chapter'),
            ),
            ListTile(
              title: const Text('Loop paragraph'),
              onTap: () => Navigator.pop(context, 'paragraph'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    setState(() {
      _loop = choice == 'off' ? null : choice;
      _loopStart = null;
      _loopEnd = null;
      if (_loop == 'paragraph') {
        final cues = widget.package.tracks[_index].cues;
        var i = 0;
        for (var j = 0; j < cues.length; j++) {
          if (cues[j].start <= _position) i = j;
        }
        if (cues.isNotEmpty) {
          if (!_cueItems.containsKey('$_index:$i') && i + 1 < cues.length) i++;
          _loopCueIndex = i;
          _loopStart = cues[i].start;
          _loopEnd = i + 1 < cues.length ? cues[i + 1].start : null;
        } else {
          _loop = null;
        }
      }
    });
  }

  Future<void> _repeatAt(Duration start) async {
    if (_loopSeeking) return;
    _loopSeeking = true;
    try {
      await _player.seek(start);
      _lastCue = null;
      _follow(start);
      await _player.resume();
    } finally {
      _loopSeeking = false;
    }
  }

  Future<void> _seekSelected() async {
    final cursor = widget.selectedCursor();
    if (cursor == null || cursor == _lastRequestedCursor) return;
    _lastRequestedCursor = cursor;
    final entries = _cueItems.entries
        .where((e) => e.value.sourceCursor == cursor)
        .toList();
    if (entries.isEmpty) return;
    final parts = entries.first.key.split(':');
    final index = int.parse(parts[0]);
    final cue = widget.package.tracks[index].cues[int.parse(parts[1])];
    if (index != _index) {
      await _player.stop();
      setState(() {
        _index = index;
        _loaded = false;
      });
    }
    _position = cue.start;
    _lastCue = null;
    if (_loaded) await _player.seek(_position);
    _loop = null;
    _loopStart = null;
    _loopEnd = null;
  }

  static String _words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'\[\d+\]'), '')
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
      .trim();
  Future<void> _mapCues() async {
    final items = <LibrarySpeechItem>[];
    var cursor = widget.startCursor;
    final seen = <String>{};
    while (mounted && seen.add(cursor) && items.length < 10000) {
      final item = await widget.load(cursor);
      if (item == null) break;
      items.add(item);
      cursor = item.nextCursor;
    }
    if (!mounted) return;
    var nextItem = 0;
    for (var track = 0; track < widget.package.tracks.length; track++) {
      final cues = widget.package.tracks[track].cues;
      for (var i = 0; i < cues.length; i++) {
        final wanted = _words(cues[i].text);
        final prefix = wanted.split(' ').take(12).join(' ');
        if (prefix.split(' ').length < 5) continue;
        final match = items.indexWhere(
          (item) => _words(item.text).contains(prefix),
          nextItem,
        );
        if (match >= 0) {
          _cueItems['$track:$i'] = items[match];
          nextItem = match;
          var phraseItem = match;
          for (var j = 0; j < cues[i].phrases.length; j++) {
            final wantedWords = _words(
              cues[i].phrases[j].text,
            ).split(' ').where((word) => word.isNotEmpty).take(8).toList();
            if (wantedWords.isEmpty) continue;
            for (var n = phraseItem; n < items.length; n++) {
              final words = RegExp(
                r"[a-zA-Z]+(?:['’][a-zA-Z]+)?",
              ).allMatches(items[n].text).toList();
              var found = false;
              for (var w = 0; w + wantedWords.length <= words.length; w++) {
                if (List.generate(
                      wantedWords.length,
                      (k) => _words(words[w + k].group(0)!),
                    ).join(' ') !=
                    wantedWords.join(' ')) {
                  continue;
                }
                final source = items[n];
                _phraseItems['$track:$i:$j'] = LibrarySpeechItem(
                  cursor: source.cursor,
                  sourceCursor: source.sourceCursor,
                  nextCursor: source.nextCursor,
                  text: source.text,
                  startOffset: words[w].start,
                  sourceLength: source.text.length,
                );
                phraseItem = n;
                found = true;
                break;
              }
              if (found) break;
            }
          }
        }
      }
    }
  }

  void _follow(Duration position) {
    final cues = widget.package.tracks[_index].cues;
    var active = -1;
    for (var i = 0; i < cues.length; i++) {
      if (cues[i].start > position) break;
      active = i;
    }
    final item = _cueItems['$_index:$active'];
    if (item == null) return;
    final cue = cues[active];
    var phraseIndex = 0;
    for (var i = 0; i < cue.phrases.length; i++) {
      if (cue.start + cue.phrases[i].start <= position) phraseIndex = i;
    }
    final phraseKey = '$_index:$active:$phraseIndex';
    final phrase = _phraseItems[phraseKey];
    final key = phrase == null
        ? phraseKey
        : '$phraseKey:${position.inMilliseconds ~/ 400}';
    if (key == _lastCue) return;
    if (phrase != null) {
      final start = cue.start + cue.phrases[phraseIndex].start;
      final end = phraseIndex + 1 < cue.phrases.length
          ? cue.start + cue.phrases[phraseIndex + 1].start
          : active + 1 < cues.length
          ? cues[active + 1].start
          : start;
      final span = (end - start).inMilliseconds;
      final progress = span <= 0
          ? 0.0
          : ((position - start).inMilliseconds / span).clamp(0.0, 1.0);
      final next = _phraseItems['$_index:$active:${phraseIndex + 1}'];
      final limit = next != null && next.sourceCursor == phrase.sourceCursor
          ? next.startOffset
          : (phrase.startOffset + cue.phrases[phraseIndex].text.length).clamp(
              phrase.startOffset,
              phrase.text.length,
            );
      final offset =
          phrase.startOffset +
          ((limit - phrase.startOffset) * progress).round();
      _lastCue = key;
      unawaited(
        widget.reveal(
          LibrarySpeechItem(
            cursor: phrase.cursor,
            sourceCursor: phrase.sourceCursor,
            nextCursor: phrase.nextCursor,
            text: phrase.text,
            startOffset: offset,
            sourceLength: phrase.text.length,
          ),
        ),
      );
      return;
    }
    final changedParagraph =
        _lastCue == null || !_lastCue!.startsWith('$_index:$active:');
    _lastCue = key;
    var offset = 0;
    if (cue.phrases.isNotEmpty) {
      final wanted = _words(
        cue.phrases[phraseIndex].text,
      ).split(' ').take(8).toList();
      final words = RegExp(
        r"[a-zA-Z]+(?:['’][a-zA-Z]+)?",
      ).allMatches(item.text).toList();
      for (var i = 0; i + wanted.length <= words.length; i++) {
        if (List.generate(
              wanted.length,
              (j) => _words(words[i + j].group(0)!),
            ).join(' ') ==
            wanted.join(' ')) {
          offset = words[i].start;
          break;
        }
      }
    }
    unawaited(_revealPosition(item, offset, changedParagraph));
  }

  late final Future<void> _ready;
  Timer? _saveTimer;
  Future<void> _revealPosition(
    LibrarySpeechItem item,
    int offset,
    bool changedParagraph,
  ) async {
    if (changedParagraph) await widget.reveal(item);
    if (!mounted || offset == 0) return;
    await widget.reveal(
      LibrarySpeechItem(
        cursor: item.cursor,
        sourceCursor: item.sourceCursor,
        nextCursor: item.nextCursor,
        text: item.text,
        startOffset: offset,
        sourceLength: item.text.length,
      ),
    );
  }

  String get _setting => 'library_recorded_audio_position:${widget.bookId}';
  void _keepReaderAwake(bool awake) {
    if (!Platform.isIOS) return;
    unawaited(
      const MethodChannel(
        'studybible/narration_media',
      ).invokeMethod<void>('keepReaderAwake', awake).catchError((Object _) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _keepReaderAwake(
      state == AppLifecycleState.resumed &&
          _playing &&
          (ModalRoute.of(context)?.isCurrent ?? true),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(
      _player.onPositionChanged.listen((position) {
        if (!mounted) return;
        setState(() => _position = position);
        if (_playing) {
          if (_loop == 'paragraph' &&
              _loopEnd != null &&
              position >= _loopEnd!) {
            unawaited(_repeatAt(_loopStart!));
          } else {
            _follow(position);
          }
        }
        _saveTimer ??= Timer(const Duration(seconds: 5), () {
          _saveTimer = null;
          unawaited(_save());
        });
      }),
    );
    _subscriptions.add(
      _player.onDurationChanged.listen((duration) {
        // Playback follows paragraph cues rather than a time slider.
      }),
    );
    _subscriptions.add(
      _player.onPlayerComplete.listen((_) => unawaited(_complete())),
    );
    _subscriptions.add(
      _player.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() => _playing = state == PlayerState.playing);
        _keepReaderAwake(_playing);
        _publish();
      }),
    );
    _ready = Future.wait([_restore(), _mapCues()]);
  }

  Future<void> _restore() async {
    final raw = await AppSettingsService.instance.loadRawSetting(_setting);
    if (!mounted || raw == null) return;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final index = widget.package.tracks.indexWhere(
        (t) => t.chapter == saved['chapter'],
      );
      if (index >= 0) {
        setState(() {
          _index = index;
          _position = Duration(milliseconds: saved['position_ms'] as int? ?? 0);
        });
      }
    } catch (_) {}
  }

  Future<void> _save() => AppSettingsService.instance.saveRawSetting(
    _setting,
    jsonEncode({
      'chapter': widget.package.tracks[_index].chapter,
      'position_ms': _position.inMilliseconds,
    }),
  );
  void _publish() => _lease?.update(
    NarrationNowPlaying(
      title: widget.package.title,
      subtitle: widget.package.tracks[_index].title,
      playing: _playing,
      index: _index + 1,
      count: widget.package.tracks.length,
    ),
  );
  Future<void> _play() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _ready;
      if (!mounted) return;
      await widget.beforePlay();
      await _seekSelected();
      _lease ??= NarrationMediaSession.instance.start(
        NarrationTransport(
          isPlaying: () => _playing,
          play: () => unawaited(_play()),
          pause: () => unawaited(_pause()),
          next: () => unawaited(_next()),
          previous: () => unawaited(
            _select(
              (_index - 1).clamp(0, widget.package.tracks.length - 1),
              play: true,
            ),
          ),
        ),
      );
      await NarrationMediaSession.instance.activateAudioSession(
        'recorded library audio',
      );
      if (!_loaded) {
        await _player.setSource(
          DeviceFileSource(widget.package.tracks[_index].file.path),
        );
        _loaded = true;
        if (_position > Duration.zero) await _player.seek(_position);
      }
      _follow(_position);
      await _player.resume();
      _publish();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recorded audio could not start: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() async {
    await _player.pause();
    await _save();
  }

  Future<void> _select(int index, {bool play = false}) async {
    if (_busy) return;
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _index = index;
      _position = Duration.zero;
      _loaded = false;
      _lastCue = null;
      _loop = null;
      _loopStart = null;
      _loopEnd = null;
    });
    await _save();
    _publish();
    if (play && mounted) await _play();
  }

  Future<void> _complete() async {
    if (_loop == 'book') {
      if (_index + 1 < widget.package.tracks.length) {
        await _next();
      } else {
        await _select(0, play: true);
      }
      if (mounted) setState(() => _loop = 'book');
      return;
    }
    if (_loop != null) {
      await _repeatAt(
        _loop == 'paragraph' ? (_loopStart ?? Duration.zero) : Duration.zero,
      );
      return;
    }
    await _next();
  }

  Future<void> _next() async {
    if (_index + 1 < widget.package.tracks.length) {
      await _select(_index + 1, play: true);
    } else {
      await _pause();
      await _player.seek(Duration.zero);
      if (mounted) setState(() => _position = Duration.zero);
      await _save();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keepReaderAwake(false);
    _saveTimer?.cancel();
    unawaited(_save());
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _lease?.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  String get _loopLabel => _loop == 'book'
      ? 'Looping ${widget.package.title}'
      : _loop == 'paragraph'
      ? 'Looping chapter ${widget.package.tracks[_index].chapter}, paragraph ${_loopCueIndex ?? 1}'
      : 'Looping chapter ${widget.package.tracks[_index].chapter}';

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous chapter',
                onPressed: _busy || _index == 0
                    ? null
                    : () => unawaited(_select(_index - 1, play: _playing)),
                icon: const Icon(Icons.skip_previous),
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => unawaited(_playing ? _pause() : _play()),
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                label: Text(_playing ? 'Pause' : 'Play'),
              ),
              IconButton(
                tooltip: 'Next chapter',
                onPressed: _busy || _index + 1 >= widget.package.tracks.length
                    ? null
                    : () => unawaited(_select(_index + 1, play: _playing)),
                icon: const Icon(Icons.skip_next),
              ),
              const Spacer(),
              IconButton(
                tooltip: _loop == null ? 'Loop off' : _loopLabel,
                onPressed: _chooseLoop,
                isSelected: _loop != null,
                icon: const Icon(Icons.repeat),
                selectedIcon: const Icon(Icons.repeat_on),
              ),
            ],
          ),
          if (_loop != null)
            Text(_loopLabel, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}
