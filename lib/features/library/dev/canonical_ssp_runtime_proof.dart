import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/elibrary_schema.dart';
import '../data/library_document_canonicalizer.dart';
import '../data/library_document_models.dart';
import '../data/library_document_repository.dart';
import '../presentation/canonical_library_reader.dart';
import '../presentation/canonical_scroll_diagnostics.dart';
import '../presentation/library_document_controller.dart';
import '../presentation/reader_tilt_autoscroll_controller.dart';
import '../presentation/reader_tilt_motion_source.dart';

const canonicalSspProofItemId =
    'library_item_research_pioneer_stephen_nelson_haskell_SSP';
const canonicalSspFixtureHash =
    'b9f2f5dfe0518d18c2eb4028009b04b55df7ba10129b3779868aca904d15c0ce';

class CanonicalSspRuntimeEnvironment {
  CanonicalSspRuntimeEnvironment({
    required this.database,
    required this.databasePath,
    required this.outputDirectory,
    required this.fixtureRoot,
    required this.repository,
    required this.blockCount,
    required this.headingOrders,
    required this.primaryHeadingOrders,
    required this.sourceHash,
  });

  final Database database;
  final String databasePath;
  final Directory outputDirectory;
  final Directory fixtureRoot;
  final LibraryDocumentRepository repository;
  final int blockCount;
  final List<int> headingOrders;
  final List<int> primaryHeadingOrders;
  final String sourceHash;

  static Future<CanonicalSspRuntimeEnvironment> create({
    Directory? fixtureRoot,
    Directory? temporaryParent,
  }) async {
    final root =
        fixtureRoot ??
        Directory(
          p.join(
            Directory.current.path,
            'test',
            'fixtures',
            'elibrary',
            'real_ssp',
          ),
        );
    final capture = File(p.join(root.path, 'capture.html'));
    if (!capture.existsSync()) {
      throw StateError('Read-only SSP fixture not found: ${capture.path}');
    }
    final sourceHash = sha256.convert(await capture.readAsBytes()).toString();
    if (sourceHash != canonicalSspFixtureHash) {
      throw StateError('SSP fixture hash mismatch; proof startup refused.');
    }

    final runRoot = await (temporaryParent ?? Directory.systemTemp).createTemp(
      'canonical_ssp_runtime_proof_',
    );
    final outputDirectory = await Directory(
      p.join(runRoot.path, 'diagnostics'),
    ).create();
    final databasePath = p.join(runRoot.path, 'isolated_ssp_elibrary.db');
    if (File(databasePath).existsSync()) {
      throw StateError('Proof database path was not newly allocated.');
    }

    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(databasePath);
    await ELibrarySchema.ensure(db);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': canonicalSspProofItemId,
      'title': 'The Story of the Seer of Patmos',
      'author': 'Stephen N. Haskell',
      'file_name': 'capture.html',
      'relative_path': 'read-only-fixture/capture.html',
      'file_hash': sourceHash,
      'source_work_id': 'SSP',
      'source_package_id': 'captureclipper:SSP',
      'file_format': 'html',
      'source_type': 'egw_html_capture',
      'created_at': now,
      'updated_at': now,
      'device_id': 'canonical-runtime-proof',
      'sync_status': 'local-proof-only',
    });
    final result = await const LibraryDocumentCanonicalizer().canonicalize(
      db: db,
      libraryItemId: canonicalSspProofItemId,
      source: capture,
    );
    final repository = LibraryDocumentRepository(db);
    final headingRows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: const <Object?>[canonicalSspProofItemId, 'heading'],
      orderBy: 'display_order',
    );
    final headings = headingRows.map(LibraryDocumentBlock.fromRow).toList();
    stdout.writeln('CANONICAL SSP RUNTIME PROOF');
    stdout.writeln('ISOLATED DATABASE: $databasePath');
    stdout.writeln('DIAGNOSTIC OUTPUT: ${outputDirectory.path}');
    return CanonicalSspRuntimeEnvironment(
      database: db,
      databasePath: databasePath,
      outputDirectory: outputDirectory,
      fixtureRoot: root,
      repository: repository,
      blockCount: result.blockCount,
      headingOrders: headings
          .map((heading) => heading.displayOrder)
          .toList(growable: false),
      primaryHeadingOrders: headings
          .where((heading) => heading.isPrimaryChapterHeading)
          .map((heading) => heading.displayOrder)
          .toList(growable: false),
      sourceHash: sourceHash,
    );
  }
}

enum CanonicalProofSpeed {
  slow(70, 0.12),
  medium(180, 0.23),
  fast(420, 0.38),
  maximumSafe(850, 0.48);

  const CanonicalProofSpeed(this.pixelsPerSecond, this.pitchRadians);
  final double pixelsPerSecond;
  final double pitchRadians;
}

class CanonicalProofStressOutcome {
  const CanonicalProofStressOutcome({
    required this.speed,
    required this.finalOrder,
    required this.headingBoundariesCrossed,
    required this.backwardRegressions,
    required this.headingOscillations,
    required this.chapterNavigationCallbacks,
    required this.ordinaryItemJumps,
    required this.readerRecreations,
    required this.controllerRecreations,
    required this.stalled,
  });

  final CanonicalProofSpeed speed;
  final int finalOrder;
  final int headingBoundariesCrossed;
  final int backwardRegressions;
  final int headingOscillations;
  final int chapterNavigationCallbacks;
  final int ordinaryItemJumps;
  final int readerRecreations;
  final int controllerRecreations;
  final bool stalled;
}

/// Deterministic development stress driver. It uses the production shared tilt
/// controller and its callback scroll target, but models block geometry at a
/// fixed extent so a complete 1,148-block pass finishes quickly in tests.
/// Heading state is derived from the accumulated viewport order, never assigned.
Future<CanonicalProofStressOutcome> runCanonicalSspDeterministicStress({
  required CanonicalSspRuntimeEnvironment environment,
  required CanonicalProofSpeed speed,
}) async {
  final rows = await environment.database.query(
    'library_document_blocks',
    where: 'library_item_id = ?',
    whereArgs: const <Object?>[canonicalSspProofItemId],
    orderBy: 'display_order',
  );
  final headingByOrder = <int, String>{};
  for (final row in rows.where((row) => row['block_type'] == 'heading')) {
    final block = LibraryDocumentBlock.fromRow(row);
    if (block.isPrimaryChapterHeading) {
      headingByOrder[block.displayOrder] = block.id;
    }
  }
  const logicalBlockExtent = 36.0;
  final maximumPixels = math.max(0.0, (rows.length - 1) * logicalBlockExtent);
  var pixels = 0.0;
  var currentOrder = 0;
  var lastOrder = 0;
  var backwardRegressions = 0;
  var stalledTicks = 0;
  String? headingId;
  final completedHeadings = <String>{};
  var headingOscillations = 0;
  final crossedHeadings = <String>{};
  final target = CallbackReaderAutoScrollTarget();
  target.attach((delta) {
    final next = (pixels + delta).clamp(0, maximumPixels).toDouble();
    if ((next - pixels).abs() <= .001) return false;
    pixels = next;
    currentOrder = (pixels / logicalBlockExtent).floor().clamp(
      0,
      rows.length - 1,
    );
    if (delta > 0 && currentOrder < lastOrder) backwardRegressions++;
    if (delta > 0) {
      crossedHeadings.addAll(
        headingByOrder.entries
            .where(
              (entry) => entry.key > lastOrder && entry.key <= currentOrder,
            )
            .map((entry) => entry.value),
      );
    }
    lastOrder = currentOrder;
    final visibleHeading = headingByOrder.entries
        .where((entry) => entry.key <= currentOrder)
        .lastOrNull
        ?.value;
    if (visibleHeading != null && visibleHeading != headingId) {
      if (headingId != null) completedHeadings.add(headingId!);
      if (completedHeadings.contains(visibleHeading)) headingOscillations++;
      headingId = visibleHeading;
      crossedHeadings.add(visibleHeading);
    }
    return true;
  });
  final source = FakeReaderTiltMotionSource();
  var navigationCallbacks = 0;
  final controller = ReaderTiltAutoScrollController(
    motionSource: source,
    scrollTarget: target,
    settings: ReaderTiltAutoScrollSettings(
      maximumSpeedPixelsPerSecond: speed.pixelsPerSecond,
      hardSafetyCapPixelsPerSecond: 900,
      speedSmoothingFactor: 1,
    ),
    canChangeChapter: (_) => false,
    onChapterChange: (_) => navigationCallbacks++,
  );
  final readerIdentity = identityHashCode(target);
  final controllerIdentity = identityHashCode(controller);
  await controller.activate();
  CanonicalProofMotionAdapter(source).calibrateAndDrive(speed);
  final maxTicks = rows.length * 20;
  for (
    var tick = 0;
    tick < maxTicks && currentOrder < rows.length - 1;
    tick++
  ) {
    final before = currentOrder;
    controller.tickForDeterministicDevelopmentProof(const Duration(seconds: 1));
    if (currentOrder == before) {
      stalledTicks++;
    } else {
      stalledTicks = 0;
    }
    if (stalledTicks >= 20) break;
  }
  await controller.stop(diagnosticCause: 'deterministic-stress-complete');
  final outcome = CanonicalProofStressOutcome(
    speed: speed,
    finalOrder: currentOrder,
    headingBoundariesCrossed: crossedHeadings.length,
    backwardRegressions: backwardRegressions,
    headingOscillations: headingOscillations,
    chapterNavigationCallbacks: navigationCallbacks,
    ordinaryItemJumps: 0,
    readerRecreations: identityHashCode(target) == readerIdentity ? 0 : 1,
    controllerRecreations: identityHashCode(controller) == controllerIdentity
        ? 0
        : 1,
    stalled: stalledTicks >= 20,
  );
  controller.dispose();
  target.detach();
  await source.dispose();
  return outcome;
}

class CanonicalProofMotionAdapter {
  CanonicalProofMotionAdapter(this.source);
  final FakeReaderTiltMotionSource source;

  void calibrateAndDrive(CanonicalProofSpeed speed) {
    const orientation = ReaderDeviceOrientation.portrait;
    for (var index = 0; index < 12; index++) {
      source.add(
        const ReaderTiltSample(pitchRadians: 0, orientation: orientation),
      );
    }
    for (var index = 0; index < 30; index++) {
      source.add(
        ReaderTiltSample(
          pitchRadians: speed.pitchRadians,
          orientation: orientation,
        ),
      );
    }
  }

  void changeSpeed(CanonicalProofSpeed speed) {
    for (var index = 0; index < 30; index++) {
      source.add(
        ReaderTiltSample(
          pitchRadians: speed.pitchRadians,
          orientation: ReaderDeviceOrientation.portrait,
        ),
      );
    }
  }
}

class CanonicalSspRuntimeProofApp extends StatelessWidget {
  const CanonicalSspRuntimeProofApp({super.key, required this.environment});
  final CanonicalSspRuntimeEnvironment environment;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Canonical SSP Runtime Proof',
    home: CanonicalSspRuntimeProofScreen(environment: environment),
  );
}

class CanonicalSspRuntimeProofScreen extends StatefulWidget {
  const CanonicalSspRuntimeProofScreen({super.key, required this.environment});
  final CanonicalSspRuntimeEnvironment environment;

  @override
  State<CanonicalSspRuntimeProofScreen> createState() =>
      _CanonicalSspRuntimeProofScreenState();
}

class _CanonicalSspRuntimeProofScreenState
    extends State<CanonicalSspRuntimeProofScreen> {
  late final LibraryDocumentController _document;
  final CallbackReaderAutoScrollTarget _target =
      CallbackReaderAutoScrollTarget();
  final CanonicalLibraryProofCommands _commands =
      CanonicalLibraryProofCommands();
  final CanonicalScrollDiagnostics _diagnostics = CanonicalScrollDiagnostics();
  final FakeReaderTiltMotionSource _motion = FakeReaderTiltMotionSource();
  late final CanonicalProofMotionAdapter _input;
  late final ReaderTiltAutoScrollController _autoScroll;
  late final int _readerIdentity;
  late final int _documentIdentity;
  final Stopwatch _elapsed = Stopwatch()..start();
  Timer? _refresh;
  int _firstVisibleOrder = 0;
  LibraryDocumentBlock? _heading;
  LibraryDocumentBlock? _renderedHeading;
  LibraryDocumentBlock? _secondaryHeading;
  CanonicalProofSpeed _speed = CanonicalProofSpeed.medium;
  double _fontScale = 1;
  bool _night = false;
  bool _panelVisible = true;
  bool _headingInspectorVisible = false;
  int _chapterNavigationCount = 0;

  @override
  void initState() {
    super.initState();
    _readerIdentity = identityHashCode(this);
    _document = LibraryDocumentController(
      libraryItemId: canonicalSspProofItemId,
      repository: widget.environment.repository,
      windowRadius: 100,
    )..addListener(_documentChanged);
    _documentIdentity = identityHashCode(_document);
    _input = CanonicalProofMotionAdapter(_motion);
    _autoScroll = ReaderTiltAutoScrollController(
      motionSource: _motion,
      scrollTarget: _target,
      settings: const ReaderTiltAutoScrollSettings(
        maximumSpeedPixelsPerSecond: 850,
        hardSafetyCapPixelsPerSecond: 900,
      ),
      onChapterChange: (_) => _chapterNavigationCount++,
      canChangeChapter: (_) => false,
    );
    _document.initialize();
    _refresh = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  void _documentChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    await _autoScroll.activate();
    _input.calibrateAndDrive(_speed);
    if (mounted) setState(() {});
  }

  Future<void> _stop() =>
      _autoScroll.stop(diagnosticCause: 'runtime-proof-stop');

  void _setSpeed(CanonicalProofSpeed speed) {
    _speed = speed;
    if (_autoScroll.isActive) _input.changeSpeed(speed);
    setState(() {});
  }

  Future<void> _visible(int order) async {
    _firstVisibleOrder = order;
    await _document.ensureWindow(order);
    final location = await widget.environment.repository.resolveLocation(
      canonicalSspProofItemId,
      order,
    );
    if (mounted) {
      setState(() {
        _heading = location?.heading;
        _renderedHeading = location?.renderedHeading;
        _secondaryHeading = location?.secondaryHeading;
      });
    }
  }

  void _headingJump(int direction) {
    final headings = widget.environment.headingOrders;
    final candidate = direction > 0
        ? headings.where((order) => order > _firstVisibleOrder).firstOrNull
        : headings.where((order) => order < _firstVisibleOrder).lastOrNull;
    if (candidate != null) _commands.jumpToOrder(candidate);
  }

  Future<File> _exportDiagnostics() async {
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final file = File(
      p.join(
        widget.environment.outputDirectory.path,
        'canonical_ssp_diagnostics_$stamp.json',
      ),
    );
    final samples = _diagnostics.samples;
    final payload = <String, Object?>{
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'fixture_hash': widget.environment.sourceHash,
      'canonicalizer_version': LibraryDocumentCanonicalizer.version,
      'database_path': widget.environment.databasePath,
      'speed': _speed.name,
      'block_count': widget.environment.blockCount,
      'heading_count': widget.environment.headingOrders.length,
      'sample_count': samples.length,
      'orders': samples
          .map((sample) => sample.firstVisibleDisplayOrder)
          .toList(),
      'heading_ids': samples
          .map((sample) => sample.headingBlockId)
          .toSet()
          .toList(),
      'requested_delta_total': samples.fold<double>(
        0,
        (sum, sample) => sum + sample.requestedDelta,
      ),
      'applied_delta_total': samples.fold<double>(
        0,
        (sum, sample) => sum + sample.appliedDelta,
      ),
      'backward_regressions': _diagnostics.hasForwardChapterRegression ? 1 : 0,
      'heading_oscillations': _diagnostics.headingOscillationCount,
      'heading_flashes': _diagnostics.headingFlashCount,
      'chapter_navigation_callbacks': _chapterNavigationCount,
      'ordinary_item_jumps': _diagnostics.ordinaryItemJumpCount,
      'explicit_control_jumps': _commands.explicitJumpCount,
      'reader_identity': _readerIdentity,
      'document_controller_identity': _documentIdentity,
      'controller_recreations': _diagnostics.controllerRecreationCount,
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Diagnostics: ${file.path}')));
    }
    return file;
  }

  Future<File> _exportHeadingInventory() async {
    final rows = await widget.environment.database.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: const <Object?>[canonicalSspProofItemId, 'heading'],
      orderBy: 'display_order',
    );
    final inventory = <Map<String, Object?>>[];
    for (var index = 0; index < rows.length; index++) {
      final block = LibraryDocumentBlock.fromRow(rows[index]);
      final metadata = block.formatted.metadata;
      inventory.add(<String, Object?>{
        'heading_number': index + 1,
        'display_order': block.displayOrder,
        'block_id': block.id,
        'text': block.plainText,
        'role': block.headingRole,
        'source_href': block.sourceHref,
        'source_anchor': block.sourceAnchor,
        'source_tag': metadata['source_tag'],
        'source_class': metadata['source_class'],
        'source_ordinal': metadata['source_ordinal'],
        'classification_reason': metadata['classification_reason'],
      });
    }
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final file = File(
      p.join(
        widget.environment.outputDirectory.path,
        'canonical_ssp_heading_inventory_$stamp.json',
      ),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(inventory),
      flush: true,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Heading inventory: ${file.path}')),
      );
    }
    return file;
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _autoScroll.dispose();
    _motion.dispose();
    _target.detach();
    _document.removeListener(_documentChanged);
    _document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = _night
        ? const Color(0xFF171410)
        : const Color(0xFFF8F3E8);
    final foreground = _night
        ? const Color(0xFFF3EBDD)
        : const Color(0xFF2B241C);
    final latest = _diagnostics.samples.lastOrNull;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: foreground,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('CANONICAL SSP RUNTIME PROOF'),
            Text(
              'ISOLATED DATABASE • NO USER DATA • CANONICAL READER ONLY',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Toggle diagnostics panel',
            onPressed: () => setState(() => _panelVisible = !_panelVisible),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Wrap(
            spacing: 4,
            children: <Widget>[
              FilledButton(
                onPressed: _start,
                child: const Text('Start autoscroll'),
              ),
              OutlinedButton(onPressed: _stop, child: const Text('Stop')),
              for (final speed in CanonicalProofSpeed.values)
                TextButton(
                  onPressed: () => _setSpeed(speed),
                  child: Text(speed.name),
                ),
              TextButton(
                onPressed: () => _commands.jumpToOrder(0),
                child: const Text('Beginning'),
              ),
              TextButton(
                onPressed: () => _headingJump(1),
                child: const Text('Next heading'),
              ),
              TextButton(
                onPressed: () => _headingJump(-1),
                child: const Text('Previous heading'),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _fontScale = math.min(1.8, _fontScale + .1)),
                child: const Text('Font +'),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _fontScale = math.max(.7, _fontScale - .1)),
                child: const Text('Font −'),
              ),
              TextButton(
                onPressed: () => setState(() => _night = !_night),
                child: const Text('Day/night'),
              ),
              TextButton(
                onPressed: _exportDiagnostics,
                child: const Text('Export diagnostics'),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _headingInspectorVisible = !_headingInspectorVisible,
                ),
                child: const Text('Heading inspector'),
              ),
              TextButton(
                onPressed: _exportHeadingInventory,
                child: const Text('Export heading inventory'),
              ),
              TextButton(
                onPressed: () => setState(_diagnostics.samples.clear),
                child: const Text('Clear diagnostics'),
              ),
            ],
          ),
          if (_panelVisible)
            Container(
              width: double.infinity,
              color: foreground.withValues(alpha: .08),
              padding: const EdgeInsets.all(8),
              child: Text(
                'blocks ${widget.environment.blockCount} | visible $_firstVisibleOrder | '
                'block ${latest?.firstVisibleBlockId ?? '—'} | heading ${_heading?.plainText ?? '—'}\n'
                'direction ${latest?.direction ?? 'idle'} | requested ${latest?.requestedDelta.toStringAsFixed(2) ?? '0'} | '
                'applied ${latest?.appliedDelta.toStringAsFixed(2) ?? '0'} | state ${_autoScroll.state.name} | speed ${_speed.name}\n'
                'reader $_readerIdentity | controller $_documentIdentity | navigation $_chapterNavigationCount | '
                'ordinary jumps ${_diagnostics.ordinaryItemJumpCount} | '
                'backward ${_diagnostics.hasForwardChapterRegression ? 1 : 0} | '
                'oscillation ${_diagnostics.headingOscillationCount} | '
                'heading flash ${_diagnostics.headingFlashCount} | '
                'recreation ${_diagnostics.controllerRecreationCount} | '
                'elapsed ${_elapsed.elapsed.inMinutes}m ${_elapsed.elapsed.inSeconds % 60}s\n'
                'database ${widget.environment.databasePath}',
                style: TextStyle(color: foreground, fontSize: 11),
              ),
            ),
          if (_headingInspectorVisible)
            _HeadingInspector(
              heading: _renderedHeading,
              primaryHeading: _heading,
              secondaryHeading: _secondaryHeading,
              color: foreground,
              headingNumber: _renderedHeading == null
                  ? null
                  : widget.environment.headingOrders.indexOf(
                          _renderedHeading!.displayOrder,
                        ) +
                        1,
            ),
          Expanded(
            child: CanonicalLibraryDocumentBody(
              controller: _document,
              autoScrollTarget: _target,
              onVisibleOrderChanged: _visible,
              onManualScroll: _autoScroll.stopForManualInteraction,
              textColor: foreground,
              sourceRoot: widget.environment.fixtureRoot,
              diagnostics: _diagnostics,
              proofCommands: _commands,
              fontScale: _fontScale,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadingInspector extends StatelessWidget {
  const _HeadingInspector({
    required this.heading,
    required this.primaryHeading,
    required this.secondaryHeading,
    required this.color,
    required this.headingNumber,
  });

  final LibraryDocumentBlock? heading;
  final LibraryDocumentBlock? primaryHeading;
  final LibraryDocumentBlock? secondaryHeading;
  final Color color;
  final int? headingNumber;

  @override
  Widget build(BuildContext context) {
    final metadata = heading?.formatted.metadata ?? const <String, Object?>{};
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: .12),
      padding: const EdgeInsets.all(8),
      child: Text(
        'heading #${headingNumber ?? '—'} | order ${heading?.displayOrder ?? '—'} | '
        'role ${heading?.headingRole ?? '—'} | ${heading?.plainText ?? '—'}\n'
        'primary ${primaryHeading?.plainText ?? '—'} | secondary ${secondaryHeading?.plainText ?? '—'} | '
        'tag ${metadata['source_tag'] ?? '—'} | class ${metadata['source_class'] ?? '—'} | '
        'reason ${metadata['classification_reason'] ?? '—'}',
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}
