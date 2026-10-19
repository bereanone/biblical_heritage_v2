import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../data/optional_book_companions.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'library_speech_queue.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/audio/narration_media_session.dart';
import '../../../core/theme/app_settings_service.dart';

/// A Contents target can be a heading with no recorded cue. Find the first
/// recorded paragraph within that destination, never an earlier saved place.
Future<String?> recordedCursorForNavigation({
  required String cursor,
  required Future<LibrarySpeechItem?> Function(String) load,
  required Set<String> recordedCursors,
  String? endCursor,
}) async {
  final seen = <String>{};
  while (cursor != endCursor && seen.add(cursor) && seen.length <= 10000) {
    final item = await load(cursor);
    if (item == null || item.sourceCursor == endCursor) return null;
    if (recordedCursors.contains(item.sourceCursor)) return item.sourceCursor;
    cursor = item.nextCursor;
  }
  return null;
}

bool recordedChapterOpening(int cueIndex, Duration position) =>
    cueIndex == 0 && position < const Duration(seconds: 3);

int previousRecordedChapterIndex(int currentIndex, Duration position) =>
    position >= const Duration(seconds: 3)
    ? currentIndex
    : (currentIndex - 1).clamp(0, currentIndex);

int recordedNextPlayableCueIndex(
  List<RecordedLibraryAudioCue> cues,
  int currentIndex, {
  required bool includeMarginNotes,
}) {
  var next = currentIndex + 1;
  if (!includeMarginNotes) {
    while (next < cues.length && cues[next].role == 'margin_note') {
      next++;
    }
  }
  return next;
}

/// Estimated progress when a recording supplies paragraph cues only.
/// The end is the next cue or the loaded track duration for its last paragraph.
int recordedParagraphFollowOffset({
  required Duration position,
  required Duration start,
  required Duration end,
  required int textLength,
}) {
  final span = (end - start).inMilliseconds;
  if (span <= 0 || textLength <= 1) return 0;
  final progress = ((position - start).inMilliseconds / span).clamp(0.0, 1.0);
  return ((textLength - 1) * progress).round();
}

@visibleForTesting
double recordedMarginNoteLineStartFraction(String text, int lineIndex) {
  final bodyStart =
      RegExp(
        r'^Margin notes\.\s*',
        caseSensitive: false,
      ).firstMatch(text)?.end ??
      0;
  final body = text.substring(bodyStart);
  final matches = RegExp(r'[^\r\n]+')
      .allMatches(body)
      .where((match) => match.group(0)!.trim().isNotEmpty)
      .toList(growable: false);
  if (matches.isEmpty) return 0;
  final index = lineIndex.clamp(0, matches.length - 1);
  return ((bodyStart + matches[index].start) / text.length).clamp(0.0, 1.0);
}

String _recordedCueWords(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'\[\d+\]'), '')
    .replaceAll('’', "'")
    .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
    .trim();

/// Short headings are real audio destinations too. Validate saved source
/// locations against their text, then fall back to forward source matching.
int recordedCueItemIndex(
  RecordedLibraryAudioCue cue,
  List<LibrarySpeechItem> items, {
  int startIndex = 0,
}) {
  if (cue.textDigest != null) {
    bool matches(LibrarySpeechItem item) =>
        sha256.convert(utf8.encode(_recordedCueWords(item.text))).toString() ==
        cue.textDigest;
    if (cue.sourceCursor != null) {
      final direct = items.indexWhere(
        (item) => item.sourceCursor == cue.sourceCursor && matches(item),
        startIndex,
      );
      if (direct >= 0) return direct;
    }
    return items.indexWhere(matches, startIndex);
  }
  final wanted = _recordedCueWords(cue.text);
  if (wanted.isEmpty) return -1;
  // A separate margin-note recording belongs to its owning paragraph even
  // though its words differ from the paragraph's narration.
  if (cue.role == 'margin_note' && cue.sourceCursor != null) {
    return items.indexWhere((item) => item.sourceCursor == cue.sourceCursor);
  }
  if (cue.sourceCursor != null) {
    final direct = items.indexWhere(
      (item) =>
          item.sourceCursor == cue.sourceCursor &&
          _recordedCueWords(item.text) == wanted,
      startIndex,
    );
    if (direct >= 0) return direct;
  }
  final words = wanted.split(' ');
  if (words.length < 5) {
    return items.indexWhere(
      (item) => _recordedCueWords(item.text) == wanted,
      startIndex,
    );
  }
  final prefix = words.take(12).join(' ');
  return items.indexWhere(
    (item) => _recordedCueWords(item.text).contains(prefix),
    startIndex,
  );
}

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
    this.textDigest,
    this.sourceCursor,
    this.role,
    this.noteOrder,
    this.openingSources = const [],
  });
  final List<RecordedLibraryAudioCue> openingSources;
  final String? role;
  final int? noteOrder;
  final String? sourceCursor;
  final Duration start;
  final String text;
  final String? textDigest;
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
  bool get hasMarginNotes =>
      tracks.any((track) => track.cues.any((cue) => cue.role == 'margin_note'));
  bool get isComplete =>
      totalChapters != null &&
      tracks.length == totalChapters &&
      List.generate(
        tracks.length,
        (i) => tracks[i].chapter == i + 1,
      ).every((v) => v);
  static String normalize(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  static Future<RecordedLibraryAudioPackage?> find(
    String title, {
    String? sourceHash,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    return findIn(
      Directory('${docs.path}/elibrary_audio'),
      title,
      sourceHash: sourceHash,
    );
  }

  static Future<RecordedLibraryAudioPackage?> findIn(
    Directory root,
    String title, {
    String? sourceHash,
  }) async {
    if (!await root.exists()) return null;
    final directories = (await root.list(followLinks: false).toList())
        .whereType<Directory>()
        .where(
          (d) => !d.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last
              .startsWith('.'),
        )
        .toList();
    final selected = <String>{};
    final pointer = File('${root.path}/bundled-current.json');
    if (await pointer.exists()) {
      try {
        final current = jsonDecode(await pointer.readAsString()) as Map;
        selected.addAll(current.values.whereType<String>());
      } catch (_) {
        /* Existing manually installed packages remain usable. */
      }
    }
    String folderName(Directory d) =>
        d.uri.pathSegments.where((s) => s.isNotEmpty).last;
    directories.removeWhere(
      (d) =>
          folderName(d).startsWith('bundled-') &&
          !selected.contains(folderName(d)),
    );
    directories.sort(
      (a, b) => (selected.contains(folderName(b)) ? 1 : 0).compareTo(
        selected.contains(folderName(a)) ? 1 : 0,
      ),
    );
    for (final entity in directories) {
      final manifest = File('${entity.path}/audio-manifest.json');
      if (!await manifest.exists()) continue;
      try {
        final json =
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
        final requiredSource = json['requires_source_sha256'] as String?;
        final isWor =
            normalize(json['title'] as String) ==
            normalize('Waggoner on Romans');
        // Even older manually copied WOR packages cannot attach by title alone.
        if (isWor && !OptionalBookCompanions.matchesWor(sourceHash)) continue;
        if (requiredSource != null && requiredSource != sourceHash) continue;
        if (!isWor && normalize(json['title'] as String) != normalize(title))
          continue;
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
                    cue['text'] as String? ?? '',
                    textDigest: cue['text_sha256'] as String?,
                    sourceCursor: cue['source_cursor']?.toString(),
                    role: cue['role']?.toString(),
                    noteOrder: (cue['note_order'] as num?)?.toInt(),
                    openingSources: [
                      for (final alias
                          in cue['opening_sources'] as List? ?? const [])
                        RecordedLibraryAudioCue(
                          Duration.zero,
                          alias['text'] as String? ?? '',
                          textDigest: alias['text_sha256'] as String?,
                          sourceCursor: alias['cursor']?.toString(),
                        ),
                    ],
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
    this.readerCursor,
  });
  final RecordedLibraryAudioPackage package;
  final String bookId;
  final Future<void> Function() beforePlay;
  final Future<LibrarySpeechItem?> Function(String) load;
  final Future<void> Function(LibrarySpeechItem) reveal;
  final String startCursor;
  final String? Function() selectedCursor;
  final String Function()? readerCursor;
  @override
  State<RecordedLibraryAudioControls> createState() =>
      RecordedLibraryAudioControlsState();
}

class RecordedLibraryAudioControlsState
    extends State<RecordedLibraryAudioControls>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  NarrationMediaLease? _lease;
  int _index = 0;
  Duration _position = Duration.zero;
  Duration _trackDuration = Duration.zero;
  bool _playing = false;
  bool _busy = false;
  String? _feedbackMessage;
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
  bool _includeMarginNotes = true;
  bool _skippingMarginNote = false;

  int _activeCueIndex(Duration position) {
    final cues = widget.package.tracks[_index].cues;
    var active = -1;
    for (var i = 0; i < cues.length; i++) {
      if (cues[i].start > position) break;
      active = i;
    }
    return active;
  }

  Future<void> _skipMarginNoteAt(Duration position) async {
    if (_includeMarginNotes || _skippingMarginNote) return;
    final cues = widget.package.tracks[_index].cues;
    final active = _activeCueIndex(position);
    if (active < 0 || cues[active].role != 'margin_note') return;
    _skippingMarginNote = true;
    try {
      final next = recordedNextPlayableCueIndex(
        cues,
        active,
        includeMarginNotes: false,
      );
      if (next < cues.length) {
        final target = cues[next].start;
        _lastCue = null;
        _position = target;
        await _player.seek(target);
        _follow(target);
      } else {
        await _next();
      }
    } finally {
      _skippingMarginNote = false;
    }
  }

  Future<void> _toggleMarginNotes() async {
    setState(() => _includeMarginNotes = !_includeMarginNotes);
    await _save();
    if (!_includeMarginNotes) await _skipMarginNoteAt(_position);
  }

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

  Future<void>? _navigationReady;
  int _navigationRevision = 0;
  bool _navigationUnavailable = false;
  bool _chapterStartPending = false;
  bool _changingSource = false;

  Future<void> selectForPlayback(String cursor, {String? endCursor}) {
    final revision = ++_navigationRevision;
    // A Contents selection owns the location immediately, before platform I/O.
    if (_playing) setState(() => _playing = false);
    return _navigationReady = _selectForPlayback(cursor, endCursor, revision);
  }

  Future<void> _selectForPlayback(
    String cursor,
    String? endCursor,
    int revision,
  ) async {
    await _ready;
    if (!mounted || revision != _navigationRevision) return;
    await _pause();
    final target = await recordedCursorForNavigation(
      cursor: cursor,
      load: widget.load,
      recordedCursors: _cueItems.values
          .map((item) => item.sourceCursor)
          .toSet(),
      endCursor: endCursor,
    );
    if (!mounted || revision != _navigationRevision) return;
    _navigationUnavailable = target == null;
    _chapterStartPending = false;
    if (target != null) {
      await _seekSelected(requestedCursor: target, force: true);
      await _save();
      _publish();
    }
    if (mounted) setState(() {});
  }

  Future<void> playFromParagraph(String cursor) async {
    await _ready;
    if (!mounted) return;
    _navigationUnavailable = false;
    _chapterStartPending = false;
    await _pause();
    if (!_cueItems.values.any((item) => item.sourceCursor == cursor)) {
      if (mounted) {
        setState(
          () => _feedbackMessage =
              'No recorded audio is available for this paragraph.',
        );
      }
      return;
    }
    await _seekSelected(requestedCursor: cursor, force: true);
    await _play();
  }

  Future<void> playMarginNotesFromParagraph(String cursor) async {
    await _ready;
    if (!mounted) return;
    _navigationUnavailable = false;
    _chapterStartPending = false;
    await _pause();
    final hasMarginNote = _cueItems.entries.any((entry) {
      if (entry.value.sourceCursor != cursor) return false;
      final parts = entry.key.split(':');
      if (parts.length < 2) return false;
      final track = int.tryParse(parts[0]);
      final cueIndex = int.tryParse(parts[1]);
      if (track == null || cueIndex == null) return false;
      return widget.package.tracks[track].cues[cueIndex].role == 'margin_note';
    });
    if (!hasMarginNote) {
      if (mounted) {
        setState(
          () => _feedbackMessage =
              'No recorded margin-note audio is available here.',
        );
      }
      return;
    }
    if (!_includeMarginNotes) {
      setState(() => _includeMarginNotes = true);
      await _save();
    }
    await _seekSelected(
      requestedCursor: cursor,
      requestedRole: 'margin_note',
      force: true,
    );
    await _play();
  }

  Future<void> playMarginNoteFromParagraph(
    String cursor, {
    required int noteOrder,
    required int lineIndex,
  }) async {
    await _ready;
    if (!mounted) return;
    _navigationUnavailable = false;
    _chapterStartPending = false;
    await _pause();
    MapEntry<String, LibrarySpeechItem>? match;
    for (final entry in _cueItems.entries) {
      if (entry.value.sourceCursor != cursor) continue;
      final parts = entry.key.split(':');
      if (parts.length < 2) continue;
      final track = int.tryParse(parts[0]);
      final cueIndex = int.tryParse(parts[1]);
      if (track == null || cueIndex == null) continue;
      final cue = widget.package.tracks[track].cues[cueIndex];
      if (cue.role == 'margin_note' && (cue.noteOrder ?? 0) == noteOrder) {
        match = entry;
        break;
      }
    }
    if (match == null) {
      if (mounted) {
        setState(
          () => _feedbackMessage =
              'No recorded audio is available for this margin note.',
        );
      }
      return;
    }
    final parts = match.key.split(':');
    final trackIndex = int.parse(parts[0]);
    final cueIndex = int.parse(parts[1]);
    final cues = widget.package.tracks[trackIndex].cues;
    final cue = cues[cueIndex];
    if (trackIndex != _index) {
      await _player.stop();
      setState(() {
        _index = trackIndex;
        _trackDuration = Duration.zero;
        _loaded = false;
      });
    }
    if (!_includeMarginNotes) {
      setState(() => _includeMarginNotes = true);
    }
    final cueEnd = cueIndex + 1 < cues.length
        ? cues[cueIndex + 1].start
        : _trackDuration;
    final available = (cueEnd - cue.start).inMilliseconds;
    final fraction = recordedMarginNoteLineStartFraction(cue.text, lineIndex);
    _position =
        cue.start +
        Duration(
          milliseconds: available <= 0 ? 0 : (available * fraction).round(),
        );
    _lastRequestedCursor = cursor;
    _lastCue = null;
    if (_loaded) await _player.seek(_position);
    _loop = null;
    _loopStart = null;
    _loopEnd = null;
    await _save();
    await _play();
  }

  Future<void> _seekSelected({
    String? requestedCursor,
    String? requestedRole,
    bool force = false,
  }) async {
    final cursor = requestedCursor ?? widget.selectedCursor();
    if (cursor == null || (!force && cursor == _lastRequestedCursor)) return;
    _lastRequestedCursor = cursor;
    final entries = _cueItems.entries.where((entry) {
      if (entry.value.sourceCursor != cursor) return false;
      if (requestedRole == null) return true;
      final parts = entry.key.split(':');
      if (parts.length < 2) return false;
      final track = int.tryParse(parts[0]);
      final cueIndex = int.tryParse(parts[1]);
      if (track == null || cueIndex == null) return false;
      return widget.package.tracks[track].cues[cueIndex].role == requestedRole;
    }).toList();
    if (entries.isEmpty) return;
    final parts = entries.first.key.split(':');
    final index = int.parse(parts[0]);
    final cue = widget.package.tracks[index].cues[int.parse(parts[1])];
    if (index != _index) {
      await _player.stop();
      setState(() {
        _index = index;
        _trackDuration = Duration.zero;
        _loaded = false;
      });
    }
    _position = entries.first.key.contains(':opening:')
        ? Duration.zero
        : cue.start;
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
        final match = recordedCueItemIndex(
          cues[i],
          items,
          startIndex: nextItem,
        );
        if (match >= 0) {
          _cueItems['$track:$i'] = items[match];
          for (final alias in cues[i].openingSources) {
            final aliasMatch = recordedCueItemIndex(alias, items);
            if (aliasMatch >= 0 &&
                aliasMatch <= match &&
                items[aliasMatch].sourceCursor == alias.sourceCursor) {
              _cueItems['$track:$i:opening:${alias.sourceCursor}'] =
                  items[aliasMatch];
            }
          }
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
    final active = _activeCueIndex(position);
    if (active < 0 && cues.isNotEmpty) {
      final opening = _cueItems['$_index:0'];
      final key = '$_index:opening';
      if (opening != null && _lastCue != key) {
        _lastCue = key;
        unawaited(
          widget.reveal(
            LibrarySpeechItem(
              cursor: opening.cursor,
              nextCursor: opening.nextCursor,
              sourceCursor: opening.sourceCursor,
              text: opening.text,
              showSectionStart: true,
            ),
          ),
        );
      }
      return;
    }
    final item = _cueItems['$_index:$active'];
    if (item == null) return;
    final cue = cues[active];
    if (cue.role == 'margin_note') {
      final end = active + 1 < cues.length
          ? cues[active + 1].start
          : _trackDuration;
      final span = (end - cue.start).inMilliseconds;
      final progress = span <= 0
          ? 0.0
          : ((position - cue.start).inMilliseconds / span).clamp(0.0, 1.0);
      final key =
          '$_index:$active:margin-note:${position.inMilliseconds ~/ 400}';
      if (key == _lastCue) return;
      _lastCue = key;
      unawaited(
        widget.reveal(
          LibrarySpeechItem(
            cursor: item.cursor,
            sourceCursor: item.sourceCursor,
            nextCursor: item.nextCursor,
            text: item.text,
            showMarginNotes: true,
            marginNoteIndex: cue.noteOrder ?? 0,
            marginNoteProgress: progress,
          ),
        ),
      );
      return;
    }
    if (recordedChapterOpening(active, position)) {
      final key = '$_index:opening';
      if (_lastCue != key) {
        _lastCue = key;
        unawaited(
          widget.reveal(
            LibrarySpeechItem(
              cursor: item.cursor,
              nextCursor: item.nextCursor,
              sourceCursor: item.sourceCursor,
              text: item.text,
              showSectionStart: true,
            ),
          ),
        );
      }
      return;
    }
    var phraseIndex = 0;
    for (var i = 0; i < cue.phrases.length; i++) {
      if (cue.start + cue.phrases[i].start <= position) phraseIndex = i;
    }
    final phraseKey = '$_index:$active:$phraseIndex';
    final phrase = _phraseItems[phraseKey];
    final key = phrase != null || cue.phrases.isEmpty
        ? '$phraseKey:${position.inMilliseconds ~/ 400}'
        : phraseKey;
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
    if (cue.phrases.isEmpty) {
      final end = active + 1 < cues.length
          ? cues[active + 1].start - const Duration(milliseconds: 750)
          : _trackDuration;
      offset = recordedParagraphFollowOffset(
        position: position,
        start: cue.start,
        end: end,
        textLength: item.text.length,
      );
    }
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
        if (!mounted || _changingSource) return;
        setState(() => _position = position);
        if (_playing) {
          if (!_includeMarginNotes &&
              _activeCueIndex(position) >= 0 &&
              widget
                      .package
                      .tracks[_index]
                      .cues[_activeCueIndex(position)]
                      .role ==
                  'margin_note') {
            unawaited(_skipMarginNoteAt(position));
          } else if (_loop == 'paragraph' &&
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
        _trackDuration = duration;
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
    _ready = _initializePosition();
  }

  Future<void> _initializePosition() async {
    await Future.wait([_restore(), _mapCues()]);
    if (!mounted) return;
    final cursor = widget.readerCursor?.call();
    if (cursor != null) {
      await _seekSelected(requestedCursor: cursor, force: true);
      if (mounted) setState(() {});
    }
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
          _trackDuration = Duration.zero;
          _position = Duration(milliseconds: saved['position_ms'] as int? ?? 0);
          _includeMarginNotes = saved['include_margin_notes'] as bool? ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _save() => AppSettingsService.instance.saveRawSetting(
    _setting,
    jsonEncode({
      'chapter': widget.package.tracks[_index].chapter,
      'position_ms': _position.inMilliseconds,
      'include_margin_notes': _includeMarginNotes,
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
      await _navigationReady;
      if (!mounted) return;
      if (_navigationUnavailable) {
        setState(
          () => _feedbackMessage =
              'No recorded audio is available for this selection.',
        );
        return;
      }
      await widget.beforePlay();
      if (_chapterStartPending) {
        _position = Duration.zero;
      } else {
        await _seekSelected();
      }
      _lease ??= NarrationMediaSession.instance.start(
        NarrationTransport(
          isPlaying: () => _playing,
          play: () => unawaited(_play()),
          pause: () => unawaited(_pause()),
          next: () => unawaited(_next()),
          previous: () => unawaited(_previousChapter(play: true)),
        ),
      );
      await NarrationMediaSession.instance.activateAudioSession(
        'recorded library audio',
      );
      if (!_loaded) {
        final destination = _position;
        _changingSource = true;
        try {
          await _player.setSource(
            DeviceFileSource(widget.package.tracks[_index].file.path),
          );
          await _player.seek(destination);
          _position = destination;
          _loaded = true;
        } finally {
          _changingSource = false;
        }
      }
      _chapterStartPending = false;
      if (!_includeMarginNotes) await _skipMarginNoteAt(_position);
      _follow(_position);
      await _player.resume();
      _publish();
    } catch (error) {
      if (mounted) {
        setState(
          () => _feedbackMessage = 'Recorded audio could not start: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> pauseForInteraction() async {
    if (!_playing) return;
    // Stop follow callbacks immediately, before the platform pause completes.
    setState(() => _playing = false);
    await _pause();
  }

  Future<void> _pause() async {
    await _player.pause();
    await _save();
  }

  Future<void> _previousChapter({required bool play}) =>
      _select(previousRecordedChapterIndex(_index, _position), play: play);

  Future<void> _select(int index, {bool play = false}) async {
    if (_busy) return;
    setState(() => _playing = false);
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _chapterStartPending = true;
      _lastRequestedCursor = widget.selectedCursor();
      _navigationUnavailable = false;
      _index = index;
      _trackDuration = Duration.zero;
      _position = Duration.zero;
      _loaded = false;
      _lastCue = null;
      _loop = null;
      _loopStart = null;
      _loopEnd = null;
    });
    await _save();
    _publish();
    if (play && mounted) {
      await _play();
    } else {
      await _ready;
      if (!mounted) return;
      final first = _cueItems.entries
          .where((entry) => entry.key.startsWith('$index:'))
          .firstOrNull;
      if (first != null) await widget.reveal(first.value);
    }
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
          if (_feedbackMessage != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _feedbackMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous chapter',
                onPressed: _busy || (_index == 0 && _position == Duration.zero)
                    ? null
                    : () => unawaited(_previousChapter(play: _playing)),
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
              if (widget.package.hasMarginNotes)
                IconButton(
                  tooltip: _includeMarginNotes
                      ? 'Margin notes on'
                      : 'Margin notes off',
                  onPressed: _busy
                      ? null
                      : () => unawaited(_toggleMarginNotes()),
                  isSelected: _includeMarginNotes,
                  icon: const Icon(Icons.speaker_notes_off_outlined),
                  selectedIcon: const Icon(Icons.speaker_notes_outlined),
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
