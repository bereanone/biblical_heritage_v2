import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/audio/narration_diagnostics.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../reader/presentation/kokoro_mac_test_narrator.dart';
import '../../reader/presentation/narration_pronunciation.dart';
import '../../reader/presentation/pronunciation_editor.dart';
import 'mac_reader_autoscroll_controller.dart';
import 'library_narration_media_controls.dart';
import 'library_speech_queue.dart';
import 'recorded_library_audio_controls.dart';
import '../data/bundled_audio_setup.dart';
import 'speech_tilt_binding.dart';
import 'reader_tilt_autoscroll_controller.dart';
import 'dart:io';
export 'library_speech_queue.dart';

/// Shared offline speech controls for both eLibrary text reader implementations.
class LibrarySpeechControls extends StatefulWidget {
  const LibrarySpeechControls({
    super.key,
    required this.controller,
    required this.initialCursor,
    required this.load,
    required this.reveal,
    this.revealRecorded,
    this.onRecordedPlay,
    this.recordedStartCursor,
    this.selectedRecordedCursor,
    required this.onPaused,
    required this.bookId,
    this.title = 'Book narration',
    this.author,
    this.bookSourceHash,
    this.tiltController,
  });
  final VoidCallback? onRecordedPlay;
  final MacReaderAutoScrollController controller;
  final String Function() initialCursor;
  final Future<LibrarySpeechItem?> Function(String) load;
  final Future<void> Function(LibrarySpeechItem) reveal;
  final Future<void> Function(LibrarySpeechItem)? revealRecorded;
  final String? recordedStartCursor;
  final String? Function()? selectedRecordedCursor;
  final VoidCallback onPaused;
  final String bookId;

  /// Shown on the lock screen while narrating.
  final String title;
  final String? author;
  final String? bookSourceHash;
  final ReaderTiltAutoScrollController? tiltController;
  @override
  State<LibrarySpeechControls> createState() => LibrarySpeechControlsState();
}

class LibrarySpeechControlsState extends State<LibrarySpeechControls>
    with WidgetsBindingObserver {
  final _recordedKey = GlobalKey<RecordedLibraryAudioControlsState>();
  String? _requestedParagraph;

  Future<void> pauseForInteraction() async {
    widget.controller.pauseNarrationForInteraction();
    await _recordedKey.currentState?.pauseForInteraction();
  }

  int _navigationRevision = 0;

  /// Move the next Play destination without starting narration.
  Future<void> selectForPlayback(String cursor, {String? endCursor}) async {
    final revision = ++_navigationRevision;
    _requestedParagraph = cursor;
    widget.controller.stopForManualInteraction();
    // Register the destination before any await so Play and audio-follow cannot
    // race the Contents selection with the previous saved position.
    final recorded = _recordedKey.currentState;
    final navigation = recorded?.selectForPlayback(
      cursor,
      endCursor: endCursor,
    );
    await _queue.stop();
    if (recorded != null) {
      await navigation;
      return;
    }
    await _ready;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || revision != _navigationRevision) return;
    await _recordedKey.currentState?.selectForPlayback(
      cursor,
      endCursor: endCursor,
    );
  }

  Future<void> playMarginNotesFromParagraph(String cursor) async {
    await _ready;
    if (!mounted) return;
    final recorded = _recordedKey.currentState;
    if (recorded == null) return;
    await recorded.playMarginNotesFromParagraph(cursor);
  }

  Future<void> playMarginNoteFromParagraph(
    String cursor, {
    required int noteOrder,
    required int lineIndex,
  }) async {
    await _ready;
    if (!mounted) return;
    final recorded = _recordedKey.currentState;
    if (recorded == null) return;
    await recorded.playMarginNoteFromParagraph(
      cursor,
      noteOrder: noteOrder,
      lineIndex: lineIndex,
    );
  }

  Future<void> playFromParagraph(String cursor) async {
    await _ready;
    if (!mounted) return;
    final recorded = _recordedKey.currentState;
    if (recorded != null) {
      await recorded.playFromParagraph(cursor);
      return;
    }
    await _queue.stop();
    if (!mounted) return;
    final c = widget.controller;
    c.stopForManualInteraction();
    _requestedParagraph = cursor;
    c.updatePreferences(
      MacAutoscrollPreferences(
        baseSpeed: c.baseSpeed,
        lastNonzeroStep: c.lastNonzeroStep,
        maximumStep: c.maximumStep,
        statusBannerMode: c.statusBannerMode,
        audioEnabled: true,
        announceChapter: c.announceChapter,
        announceVerseNumbers: c.announceVerseNumbers,
        speechRate: c.speechRate,
      ),
    );
    c.setSignedStep(1);
    await _start();
  }

  KokoroMacTestNarrator? _speechEngine;
  SpeechTiltBinding? _speechTilt;
  Map<String, String> _rules = {};
  Map<String, String> _deferredRules = {};
  KokoroMacTestNarrator get _narrator {
    final existing = _speechEngine;
    if (existing != null) return existing;
    final engine = KokoroMacTestNarrator(
      onPlaybackComplete: () => unawaited(_queue.completed()),
      onError: _failed,
    );
    engine.pronunciationCorrections = Map.of(_rules);
    engine.deferredPronunciationCorrections = Map.of(_deferredRules);
    return _speechEngine = engine;
  }

  late final LibrarySpeechQueue _queue;
  late final LibrarySpeechSegmenter _segments;
  late final LibraryNarrationMediaControls _media;
  RecordedLibraryAudioPackage? _recordedPackage;
  bool _firstSegment = true;
  late final Future<void> _ready;
  bool _editing = false;
  int _session = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _segments = LibrarySpeechSegmenter((cursor) => widget.load(cursor));
    _queue = LibrarySpeechQueue(
      load: _segments.load,
      reveal: (item) => widget.reveal(item),
      speak: (item) async {
        final session = _session;
        final speed = widget.controller.speechRate;
        if (_firstSegment) {
          _firstSegment = false;
          // Buffer a bounded current and next segment before the first play.
          await _narrator.prepare(text: item.text, speed: speed);
          if (!_queue.running || session != _session) return;
          final next = await _segments.load(item.nextCursor);
          if (!_queue.running || session != _session) return;
          if (next != null) {
            await _narrator.prepare(text: next.text, speed: speed);
          }
        }
        if (!_queue.running || session != _session) return;
        await _narrator.speak(
          verseKey: 'library-${widget.bookId}-$session-${item.cursor}',
          text: item.text,
          speed: speed,
        );
        if (_queue.running && session == _session) {
          unawaited(_prefetch(item.nextCursor, session, speed));
        }
      },
      stopAudio: () async {
        await _speechEngine?.stop();
      },
      onEnd: () {
        widget.controller.stopForManualInteraction();
        widget.onPaused();
      },
      onError: (error) => _failed(error.toString()),
    );
    if ((Platform.isIOS || Platform.isAndroid) &&
        widget.tiltController != null) {
      _speechTilt = SpeechTiltBinding(
        widget.controller,
        widget.tiltController!,
        (rate) {
          final engine = _speechEngine;
          if (engine != null) unawaited(engine.setLiveRate(rate));
        },
      );
    }
    _media = LibraryNarrationMediaControls(
      autoscroll: widget.controller,
      title: widget.title,
      author: widget.author,
      next: () => unawaited(_skip(next: true)),
      previous: () => unawaited(_skip(next: false)),
    );
    _ready = _loadRules();
    BundledAudioSetup.instance.addListener(_recordingsChanged);
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  Future<void> _prefetch(String cursor, int session, double speed) async {
    try {
      final depth = Platform.isIOS ? KokoroMacTestNarrator.prefetchAhead() : 2;
      for (var i = 0; i < depth; i++) {
        if (!mounted || !_queue.running || session != _session) return;
        final next = await _segments.load(cursor);
        if (!mounted ||
            !_queue.running ||
            session != _session ||
            next == null) {
          return;
        }
        await _narrator.prepare(text: next.text, speed: speed);
        cursor = next.nextCursor;
      }
    } catch (_) {
      // Playback reports an error if it later needs an unavailable segment.
    }
  }

  void _recordingsChanged() {
    if (mounted &&
        _recordedPackage == null &&
        BundledAudioSetup.instance.complete) {
      unawaited(_refreshRecordedPackage());
    }
  }

  Future<void> _refreshRecordedPackage() async {
    final package = await RecordedLibraryAudioPackage.find(
      widget.title,
      sourceHash: widget.bookSourceHash,
    );
    if (mounted) setState(() => _recordedPackage = package);
  }

  Future<void> _loadRules() async {
    final store = AppSettingsService.instance;
    final rules = decodeNarrationPronunciations(
      await store.loadRawSetting('narration_pronunciations_v1'),
    );
    final package = await RecordedLibraryAudioPackage.find(
      widget.title,
      sourceHash: widget.bookSourceHash,
    );
    if (mounted) setState(() => _recordedPackage = package);
    _rules = rules;
    _deferredRules = await loadDeferredNarrationPronunciations(
      rules: rules,
      load: store.loadRawSetting,
      save: store.saveRawSetting,
    );
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final controller = widget.controller;
    if (_editing || !controller.isNarrationMode || !controller.isScrolling) {
      if (_queue.running) {
        unawaited(_queue.stop());
        widget.onPaused();
      }
      return;
    }
    if (_queue.running) return;
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _ready;
      if (!mounted ||
          _editing ||
          !widget.controller.isNarrationMode ||
          !widget.controller.isScrolling ||
          _queue.running) {
        return;
      }
      ++_session;
      _firstSegment = true;
      final cursor = _requestedParagraph ?? widget.initialCursor();
      _requestedParagraph = null;
      await _queue.start(cursor);
    } catch (error) {
      _failed(error.toString());
    }
  }

  /// Lock-screen skip: next paragraph, or back to the start of this one.
  Future<void> _skip({required bool next}) async {
    final item = _queue.current;
    if (item == null || !_queue.running) return;
    final cursor = next ? item.nextCursor : item.sourceCursor;
    await _queue.stop();
    if (!mounted ||
        _editing ||
        !widget.controller.isNarrationMode ||
        !widget.controller.isScrolling) {
      return;
    }
    ++_session;
    _firstSegment = true;
    await _queue.start(cursor);
  }

  void _failed(String message) {
    NarrationDiagnostics.log('library narration FAILED: $message');
    if (!mounted) return;
    unawaited(_queue.stop());
    widget.controller.stopForManualInteraction();
    widget.onPaused();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Book narration stopped: $message')));
  }

  Future<void> _edit() async {
    _editing = true;
    widget.controller.stopForManualInteraction();
    await _queue.stop();
    await _ready;
    if (!mounted) return;
    final original = Map<String, String>.of(_narrator.pronunciationCorrections);
    var saved = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PronunciationEditor(
        initial: original,
        onStopPreview: _narrator.stop,
        onPreview: (text, rules) async {
          await _narrator.stop();
          _narrator.pronunciationCorrections = rules;
          await _narrator.speak(
            verseKey: 'library-preview-${++_session}',
            text: text,
            speed: widget.controller.speechRate,
            preferDictionary: false,
          );
        },
        onSave: (rules) async {
          await AppSettingsService.instance.saveRawSetting(
            'narration_pronunciations_v1',
            jsonEncode(rules),
          );
          _narrator.pronunciationCorrections = Map.of(rules);
          saved = true;
        },
      ),
    );
    await _narrator.stop();
    if (!saved) _narrator.pronunciationCorrections = original;
    _editing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // iOS keeps narrating behind a locked screen; stopping here would end it.
      if (state == AppLifecycleState.paused &&
          _media.keepsSpeakingInBackground) {
        return;
      }
      widget.controller.stopForManualInteraction();
    }
  }

  @override
  void dispose() {
    BundledAudioSetup.instance.removeListener(_recordingsChanged);
    _speechTilt?.dispose();
    _media.dispose();
    widget.controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_queue.stop());
    _speechEngine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final package = _recordedPackage;
    if (package != null) {
      return RecordedLibraryAudioControls(
        key: _recordedKey,
        package: package,
        bookId: widget.bookId,
        load: widget.load,
        reveal: widget.revealRecorded ?? widget.reveal,
        startCursor: widget.recordedStartCursor ?? widget.initialCursor(),
        selectedCursor: widget.selectedRecordedCursor ?? () => null,
        readerCursor: widget.initialCursor,
        beforePlay: () async {
          widget.onRecordedPlay?.call();
          c.stopForManualInteraction();
          await _queue.stop();
          await _speechEngine?.stop();
        },
      );
    }
    if (!c.audioEnabled) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.volume_up_outlined),
          label: const Text('Read aloud'),
          onPressed: () {
            c.stopForManualInteraction();
            c.updatePreferences(
              MacAutoscrollPreferences(
                baseSpeed: c.baseSpeed,
                lastNonzeroStep: c.lastNonzeroStep,
                maximumStep: c.maximumStep,
                statusBannerMode: c.statusBannerMode,
                audioEnabled: true,
                announceChapter: c.announceChapter,
                announceVerseNumbers: c.announceVerseNumbers,
                speechRate: c.speechRate,
              ),
            );
            c.setSignedStep(1);
          },
        ),
      );
    }
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          TextButton.icon(
            label: const Text('Voice'),
            onPressed: () {
              if (c.isScrolling) {
                c.stopForManualInteraction();
              } else {
                c.setSignedStep(1);
              }
            },
            icon: Icon(c.isScrolling ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Slider(
              value: c.speechRate,
              min: .75,
              max: 1.5,
              divisions: 15,
              label: '${c.speechRate.toStringAsFixed(2)}×',
              onChanged: c.setSpeechRate,
            ),
          ),
          Text('${c.speechRate.toStringAsFixed(2)}×'),
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.record_voice_over),
            label: const Text('Pronunciations'),
          ),
        ],
      ),
    );
  }
}
