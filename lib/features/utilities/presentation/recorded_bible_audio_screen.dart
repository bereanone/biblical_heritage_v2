import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/audio/narration_media_session.dart';
import '../../../core/database/study_bible_database.dart';

class RecordedBibleAudioScreen extends StatefulWidget {
  const RecordedBibleAudioScreen({
    super.key,
    this.documentsDirectory,
    this.loadBooks,
  });

  final Future<Directory> Function()? documentsDirectory;
  final Future<List<BookRecord>> Function()? loadBooks;
  @override
  State<RecordedBibleAudioScreen> createState() =>
      _RecordedBibleAudioScreenState();
}

class _RecordedBibleAudioScreenState extends State<RecordedBibleAudioScreen> {
  static const _channel = MethodChannel('studybible/recorded_audio');
  static const _testChapterAssets = [
    'assets/audio/qwen_test/66_Rev_001.m4a',
    'assets/audio/qwen_test/66_Rev_002.m4a',
  ];
  static final _chapterFilePattern = RegExp(
    r'^([0-9]{2})(?:_([A-Za-z0-9]{3,4})_([0-9]{3})|-([0-9]{3})(?:-[A-Za-z0-9-]+)?)\.m4a$',
  );

  final List<Map<String, dynamic>> _files = [];
  final List<Map<String, dynamic>> _books = [];
  int? _selectedIndex;
  bool _playing = false;
  double _duration = 0.0;
  double _position = 0.0;
  double _rate = 1.0;
  int _pitchSemitones = 0;
  String? _error;
  bool _busy = false;
  bool _seekDrag = false;
  Timer? _pollTimer;
  bool _polling = false;
  bool _advancePending = false;
  String? _loadedPath;
  NarrationMediaLease? _lease;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'complete' && mounted) {
        setState(() => _playing = false);
        _publish();
        if (_busy) {
          _advancePending = true;
        } else {
          unawaited(_run(_next));
        }
      }
    });
    unawaited(
      _run(() async {
        await _loadBooks();
        await _loadFiles();
        await _loadSettings();
      }),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _channel.setMethodCallHandler(null);
    unawaited(_channel.invokeMethod<void>('stop').catchError((Object _) {}));
    _lease?.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    if (!mounted) return;
    try {
      final dir =
          await (widget.documentsDirectory ??
              getApplicationDocumentsDirectory)();
      if (!mounted) return;
      final targetDir = Directory('${dir.path}/recorded_bible_audio');
      if (!await targetDir.exists()) await targetDir.create();
      final files = await targetDir.list().toList();
      final m4aFiles =
          files
              .where((f) => f is File && f.path.endsWith('.m4a'))
              .map((f) => f.path)
              .where((p) => _chapterFilePattern.hasMatch(p.split('/').last))
              .toList()
            ..sort();
      if (!mounted) return;
      setState(() => _files.clear());
      for (final path in m4aFiles) {
        final name = path.split('/').last;
        final reference = _chapterFilePattern.firstMatch(name)!;
        final bookNum = int.parse(reference.group(1)!);
        final chapter = int.parse(reference.group(3) ?? reference.group(4)!);
        final bookName =
            _books.firstWhere(
              (b) => b['bookNumber'] == bookNum,
              orElse: () => {'bookName': 'Unknown'},
            )['bookName'] ??
            'Unknown';
        setState(
          () => _files.add({
            'path': path,
            'label': '$bookName $chapter',
            'bookNum': bookNum,
            'chapter': chapter,
          }),
        );
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> _loadBooks() async {
    if (!mounted) return;
    try {
      final books =
          await (widget.loadBooks ?? StudyBibleDatabase.instance.loadBooks)();
      if (!mounted) return;
      setState(
        () => _books.addAll(
          books.map(
            (b) => {'bookNumber': b.bookNumber, 'bookName': b.bookName},
          ),
        ),
      );
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<File> _settingsFile() async {
    final documents =
        await (widget.documentsDirectory ?? getApplicationDocumentsDirectory)();
    final dir = Directory('${documents.path}/recorded_bible_audio');
    await dir.create(recursive: true);
    return File('${dir.path}/preferences.json');
  }

  Future<void> _loadSettings() async {
    final file = await _settingsFile();
    if (await file.exists()) {
      final data = jsonDecode(await file.readAsString()) as Map;
      final rate = (data['rate'] as num?)?.toDouble();
      final pitch = (data['pitch'] as num?)?.toDouble();
      if (rate != null && rate.isFinite && rate >= .5 && rate <= 2) {
        _rate = rate;
      }
      if (pitch != null && pitch.isFinite && pitch >= -6 && pitch <= 6) {
        _pitchSemitones = pitch.round();
      }
    }
    if (!mounted) return;
    await _channel.invokeMethod<void>('setRate', {'rate': _rate});
    if (!mounted) return;
    await _channel.invokeMethod<void>('setPitch', {
      'pitch': _pitchSemitones.toDouble(),
    });
  }

  Future<void> _saveSettings() async {
    final file = await _settingsFile();
    await file.writeAsString(
      jsonEncode({'rate': _rate, 'pitch': _pitchSemitones}),
      flush: true,
    );
  }

  void _publish() {
    final i = _selectedIndex;
    if (i != null && i < _files.length) {
      _lease?.update(
        NarrationNowPlaying(
          title: _files[i]['label'] as String,
          playing: _playing,
        ),
      );
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_advancePending) {
          _advancePending = false;
          unawaited(_run(_next));
        }
      }
    }
  }

  void _setError(String? msg) {
    if (mounted) setState(() => _error = msg);
  }

  Future<void> _startPoll() async {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(milliseconds: 500), (t) async {
      if (_busy || _seekDrag || _polling || !mounted) return;
      _polling = true;
      try {
        final state = await _channel.invokeMapMethod<String, dynamic>('state');
        if (state == null) return;
        final duration = (state['duration'] as num?)?.toDouble() ?? 0.0;
        final position = (state['position'] as num?)?.toDouble() ?? 0.0;
        final playing = state['playing'] as bool? ?? false;
        if (mounted) {
          setState(() {
            _duration = duration;
            _position = position;
            _playing = playing;
          });
        }
      } catch (e) {
        _setError(e.toString());
        t.cancel();
      } finally {
        _polling = false;
      }
    });
  }

  Future<void> _play() async {
    if (!mounted ||
        _selectedIndex == null ||
        _selectedIndex! >= _files.length) {
      return;
    }
    final path = _files[_selectedIndex!]['path'] as String;
    _lease ??= NarrationMediaSession.instance.start(
      NarrationTransport(
        isPlaying: () => _playing,
        play: () => unawaited(_run(_play)),
        pause: () => unawaited(_run(_pause)),
        next: () => unawaited(_run(_next)),
        previous: () => unawaited(_run(_previous)),
      ),
    );
    await NarrationMediaSession.instance.activateAudioSession('recorded bible');
    if (!mounted) return;
    if (_loadedPath != path) {
      await _channel.invokeMethod<void>('load', {'path': path});
      _loadedPath = path;
      _position = 0;
      _duration = 0;
    }
    if (!mounted) return;
    await _channel.invokeMethod<void>('play');
    if (!mounted) return;
    setState(() => _playing = true);
    _publish();
    await _startPoll();
  }

  Future<void> _pause() async {
    await _channel.invokeMethod<void>('pause');
    if (mounted) setState(() => _playing = false);
    _publish();
  }

  Future<void> _next() async {
    if (_selectedIndex == null) return;
    final nextIndex = _selectedIndex! + 1;
    if (nextIndex < _files.length) {
      setState(() => _selectedIndex = nextIndex);
      await _play();
    } else {
      await _pause();
    }
  }

  Future<void> _previous() async {
    if (_selectedIndex == null) return;
    final prevIndex = _selectedIndex! - 1;
    if (prevIndex >= 0) {
      setState(() => _selectedIndex = prevIndex);
      await _play();
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _pause();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m4a'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      final dir =
          await (widget.documentsDirectory ??
              getApplicationDocumentsDirectory)();
      if (!mounted) return;
      final targetDir = Directory('${dir.path}/recorded_bible_audio');
      if (!await targetDir.exists()) await targetDir.create();
      for (final file in result.files) {
        final filename = file.name;
        if (!_chapterFilePattern.hasMatch(filename)) continue;
        final destPath = '${targetDir.path}/$filename';
        if (await File(destPath).exists()) continue;
        if (file.path == null) continue;
        final temp = await File(file.path!).copy('$destPath.importing');
        await temp.rename(destPath);
      }
      if (!mounted) return;
      await _channel.invokeMethod<void>('stop');
      if (!mounted) return;
      _selectedIndex = null;
      _loadedPath = null;
      await _loadFiles();
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _hasTestChapters =>
      _files.any((f) => f['bookNum'] == 66 && f['chapter'] == 1) &&
      _files.any((f) => f['bookNum'] == 66 && f['chapter'] == 2);

  Future<void> _addTestChapters() async {
    final documents =
        await (widget.documentsDirectory ?? getApplicationDocumentsDirectory)();
    final dir = Directory('${documents.path}/recorded_bible_audio');
    await dir.create(recursive: true);
    for (final assetPath in _testChapterAssets) {
      final destination = File('${dir.path}/${assetPath.split('/').last}');
      if (await destination.exists()) continue;
      final bytes = await rootBundle.load(assetPath);
      final temporary = File('${destination.path}.importing');
      await temporary.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      await temporary.rename(destination.path);
    }
    if (!mounted) return;
    await _channel.invokeMethod<void>('stop');
    _selectedIndex = null;
    _loadedPath = null;
    _playing = false;
    await _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Bible Audio'),
        actions: [
          IconButton(
            icon: Icon(Icons.file_upload),
            onPressed: _busy ? null : _import,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_error!, style: TextStyle(color: Colors.red)),
            ),
          if (!_hasTestChapters)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => unawaited(_run(_addTestChapters)),
                icon: const Icon(Icons.headphones),
                label: const Text('Add Qwen test chapters'),
              ),
            ),
          if (_files.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Add Revelation 1 and 2 to test playback, speed, and pitch, or import your own chapter recordings.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (_selectedIndex != null && _selectedIndex! < _files.length)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _files[_selectedIndex!]['label'] as String,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          if (_files.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _files.length,
                itemBuilder: (context, i) {
                  final isSelected = i == _selectedIndex;
                  return ListTile(
                    title: Text(_files[i]['label'] as String),
                    selected: isSelected,
                    onTap: () {
                      if (_busy) return;
                      setState(() => _selectedIndex = i);
                      unawaited(_run(_play));
                    },
                  );
                },
              ),
            ),
          if (_selectedIndex != null && _selectedIndex! < _files.length)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                children: [
                  Slider(
                    value: _position.clamp(
                      0.0,
                      _duration > 0 ? _duration : 1.0,
                    ),
                    max: _duration > 0 ? _duration : 1.0,
                    onChanged: (v) => setState(() => _position = v),
                    onChangeStart: (_) => setState(() => _seekDrag = true),
                    onChangeEnd: (v) async {
                      setState(() => _seekDrag = false);
                      await _run(
                        () =>
                            _channel.invokeMethod<void>('seek', {'seconds': v}),
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.skip_previous),
                        onPressed: _busy
                            ? null
                            : () => unawaited(_run(_previous)),
                      ),
                      IconButton(
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        onPressed: _busy
                            ? null
                            : () => unawaited(_run(_playing ? _pause : _play)),
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next),
                        onPressed: _busy ? null : () => unawaited(_run(_next)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Speed: ${_rate.toStringAsFixed(2)}×'),
                      Expanded(
                        child: Slider(
                          value: _rate,
                          min: 0.5,
                          max: 2.0,
                          divisions: 30,
                          onChanged: (v) => setState(() => _rate = v),
                          onChangeEnd: (v) async {
                            _rate = v;
                            await _run(() async {
                              await _channel.invokeMethod<void>('setRate', {
                                'rate': _rate,
                              });
                              await _saveSettings();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Pitch: $_pitchSemitones semitones'),
                      Expanded(
                        child: Slider(
                          value: _pitchSemitones.toDouble(),
                          min: -6.0,
                          max: 6.0,
                          divisions: 12,
                          onChanged: (v) =>
                              setState(() => _pitchSemitones = v.toInt()),
                          onChangeEnd: (v) async {
                            _pitchSemitones = v.toInt();
                            await _run(() async {
                              await _channel.invokeMethod<void>('setPitch', {
                                'pitch': _pitchSemitones.toDouble(),
                              });
                              await _saveSettings();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
