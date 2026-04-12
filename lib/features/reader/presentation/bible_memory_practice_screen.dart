import 'package:flutter/material.dart';

import '../data/bible_memory_repository.dart';

class BibleMemoryPracticeScreen extends StatefulWidget {
  const BibleMemoryPracticeScreen({
    super.key,
    required this.memoryVerse,
    required this.repository,
  });

  final MemoryVerse memoryVerse;
  final BibleMemoryRepository repository;

  @override
  State<BibleMemoryPracticeScreen> createState() =>
      _BibleMemoryPracticeScreenState();
}

class _BibleMemoryPracticeScreenState extends State<BibleMemoryPracticeScreen> {
  static const List<int> _drillIntervals = <int>[5, 4, 3, 2, 1];

  final TextEditingController _letterController = TextEditingController();
  final FocusNode _letterFocus = FocusNode();

  late final List<_MemoryToken> _tokens;
  int _phase = 0;
  List<int> _targets = const <int>[];
  int _targetCursor = 0;
  int _strikeCount = 0;
  int _totalStrikes = 0;
  int _sessionMisses = 0;
  bool _saving = false;
  final Map<int, _TargetState> _status = <int, _TargetState>{};

  @override
  void initState() {
    super.initState();
    _tokens = _tokenize(widget.memoryVerse.verseText);
    _setPhase(0);
  }

  @override
  void dispose() {
    _letterController.dispose();
    _letterFocus.dispose();
    super.dispose();
  }

  List<_MemoryToken> _tokenize(String text) {
    final parts = RegExp(r'\S+')
        .allMatches(text)
        .map((match) => match.group(0) ?? '')
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    return parts.map((part) => _MemoryToken(raw: part)).toList(growable: false);
  }

  int get _currentInterval {
    if (_phase <= 0) return 0;
    return _drillIntervals[_phase - 1];
  }

  bool get _isFinalPhase => _phase == _drillIntervals.length;

  void _setPhase(int phase) {
    _phase = phase;
    _targets = _buildTargetsForInterval(_currentInterval);
    _targetCursor = 0;
    _strikeCount = 0;
    _status
      ..clear()
      ..addEntries(_targets.map((index) => MapEntry(index, _TargetState.pending)));
    if (_phase > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FocusScope.of(context).requestFocus(_letterFocus);
        }
      });
    }
    setState(() {});
  }

  List<int> _buildTargetsForInterval(int interval) {
    if (interval <= 0) return const <int>[];
    if (interval == 1) {
      return List<int>.generate(_tokens.length, (index) => index)
          .where((index) => _tokens[index].isTargetable)
          .toList(growable: false);
    }
    final targets = <int>[];
    var ordinal = 0;
    for (var index = 0; index < _tokens.length; index++) {
      if (!_tokens[index].isTargetable) continue;
      ordinal += 1;
      if (ordinal % interval == 0) {
        targets.add(index);
      }
    }
    return targets;
  }

  int? get _currentTargetIndex {
    if (_targetCursor >= _targets.length) return null;
    return _targets[_targetCursor];
  }

  bool get _stageComplete => _phase > 0 && _targetCursor >= _targets.length;

  String _maskedWord(String raw) {
    if (_currentInterval == 1) {
      return '____';
    }
    final letters = raw.replaceAll(RegExp(r'[^A-Za-z]'), '');
    final length = letters.isEmpty ? 3 : letters.length.clamp(3, 9);
    return '_' * length;
  }

  void _handleLetterInput(String value) {
    if (_phase == 0 || _stageComplete) return;
    final input = RegExp(r'[A-Za-z]').firstMatch(value)?.group(0);
    if (input == null) {
      _letterController.clear();
      return;
    }
    final targetIndex = _currentTargetIndex;
    if (targetIndex == null) return;
    final expected = _tokens[targetIndex].firstLetter;

    if (input.toLowerCase() == expected) {
      _status[targetIndex] = _TargetState.correct;
      _targetCursor += 1;
      _strikeCount = 0;
    } else {
      _strikeCount += 1;
      _totalStrikes += 1;
      if (_strikeCount >= 3) {
        _status[targetIndex] = _TargetState.missed;
        _targetCursor += 1;
        _strikeCount = 0;
        _sessionMisses += 1;
      }
    }
    _letterController.clear();
    setState(() {});
  }

  Future<void> _finishSession() async {
    if (_saving) return;
    setState(() => _saving = true);
    final passed = _totalStrikes <= 3;
    await widget.repository.markReviewCompleted(
      verse: widget.memoryVerse,
      passed: passed,
      totalStrikes: _totalStrikes,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _ordinal(int value) {
    if (value >= 11 && value <= 13) return '${value}th';
    switch (value % 10) {
      case 1:
        return '${value}st';
      case 2:
        return '${value}nd';
      case 3:
        return '${value}rd';
      default:
        return '${value}th';
    }
  }

  Widget _buildToken(BuildContext context, int index) {
    final token = _tokens[index];
    if (_phase == 0 || !_status.containsKey(index)) {
      return Text(
        '${token.raw} ',
        style: const TextStyle(fontSize: 28, height: 1.2),
      );
    }

    final state = _status[index]!;
    final isCurrent = _currentTargetIndex == index;
    switch (state) {
      case _TargetState.correct:
        return Text(
          '${token.raw} ',
          style: const TextStyle(
            fontSize: 28,
            height: 1.2,
            color: Colors.green,
            fontWeight: FontWeight.w700,
          ),
        );
      case _TargetState.missed:
        return Container(
          margin: const EdgeInsets.only(right: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            token.raw,
            style: const TextStyle(
              fontSize: 28,
              height: 1.2,
              color: Colors.red,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      case _TargetState.pending:
        return Container(
          margin: const EdgeInsets.only(right: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(
              color: isCurrent ? Colors.orange : Colors.transparent,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _maskedWord(token.raw),
            style: TextStyle(
              fontSize: 28,
              height: 1.2,
              letterSpacing: 1.2,
              color: isCurrent
                  ? Colors.orange.shade700
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    String stageTitle;
    if (_phase == 0) {
      stageTitle = 'Stage 1: Full Verse';
    } else {
      final interval = _currentInterval;
      if (interval == 1) {
        stageTitle = 'Stage ${_phase + 1}: Hide All Words (No Visual Hints)';
      } else {
        stageTitle = 'Stage ${_phase + 1}: Guess Every ${_ordinal(interval)} Word';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.memoryVerse.reference),
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stageTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text('Misses this session: $_sessionMisses'),
                    const SizedBox(height: 2),
                    Text(
                      'Total strikes: $_totalStrikes / 3 (must be 3 or fewer to advance cadence)',
                    ),
                    if (_phase > 0 && !_stageComplete) ...[
                      const SizedBox(height: 2),
                      Text('Current strikes: $_strikeCount / 3'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  children: List<Widget>.generate(
                    _tokens.length,
                    (index) => _buildToken(context, index),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_phase == 0)
              FilledButton(
                onPressed: () => _setPhase(1),
                child: const Text('Start Drill (Every 5th Word)'),
              )
            else if (_stageComplete) ...[
              Text(
                _isFinalPhase
                    ? (_totalStrikes <= 3
                        ? 'Session passed. Ready to advance cadence.'
                        : 'Session complete, but strikes exceeded 3. Cadence will not advance.')
                    : 'Stage ${_phase + 1} complete.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (!_isFinalPhase)
                FilledButton(
                  onPressed: () => _setPhase(_phase + 1),
                  child: Text(
                    _phase + 1 < _drillIntervals.length &&
                            _drillIntervals[_phase] > 1
                        ? 'Next Stage (Every ${_ordinal(_drillIntervals[_phase])} Word)'
                        : 'Next Stage (No Hints)',
                  ),
                )
              else
                FilledButton(
                  onPressed: _saving ? null : _finishSession,
                  child: Text(_saving ? 'Saving...' : 'Finish Review'),
                ),
            ] else
              TextField(
                controller: _letterController,
                focusNode: _letterFocus,
                autofocus: true,
                maxLength: 1,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                onChanged: _handleLetterInput,
                decoration: const InputDecoration(
                  labelText: 'Type first letter of next hidden word',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MemoryToken {
  _MemoryToken({required this.raw}) : firstLetter = _firstLetter(raw);

  final String raw;
  final String firstLetter;

  bool get isTargetable => firstLetter.isNotEmpty;

  static String _firstLetter(String value) {
    final match = RegExp(r'[A-Za-z]').firstMatch(value);
    return (match?.group(0) ?? '').toLowerCase();
  }
}

enum _TargetState { pending, correct, missed }
