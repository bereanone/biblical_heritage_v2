import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:studybible2/features/library/dev/canonical_ssp_runtime_proof.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';

const _expectedHashes = <String, String>{
  'capture.html':
      'b9f2f5dfe0518d18c2eb4028009b04b55df7ba10129b3779868aca904d15c0ce',
  'manifest.json':
      '7deaadb231fcf7240866f1f79683eb3b2ac81a729bcdeacb73c5e21a834f50e9',
  'manifest.pre-schema2-repair.json':
      '554bb79c49f4ebf0633975820ddf3e96aee1e3975413f8cde13689c9c03f8663',
  'images/image_0001.png':
      '27a5e6e439094075c0eaab84ff3bb5ad7b923861f3af46b94ad3d816fa7c5154',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late Directory temporaryParent;
  late CanonicalSspRuntimeEnvironment environment;

  setUpAll(() async {
    fixture = Directory('test/fixtures/elibrary/real_ssp');
    temporaryParent = await Directory.systemTemp.createTemp(
      'canonical_ssp_phase3_test_parent_',
    );
    environment = await CanonicalSspRuntimeEnvironment.create(
      fixtureRoot: fixture,
      temporaryParent: temporaryParent,
    );
  });

  tearDownAll(() async {
    await environment.database.close();
    await temporaryParent.delete(recursive: true);
  });

  test(
    'standalone bootstrap creates a new isolated SSP-only database',
    () async {
      expect(environment.databasePath, startsWith(temporaryParent.path));
      expect(p.basename(environment.databasePath), 'isolated_ssp_elibrary.db');
      expect(File(environment.databasePath).existsSync(), isTrue);
      final items = await environment.database.query('library_items');
      expect(items, hasLength(1));
      expect(items.single['id'], canonicalSspProofItemId);
      expect(items.single['source_package_id'], 'captureclipper:SSP');
      expect(environment.blockCount, 1148);
      expect(environment.headingOrders, hasLength(34));
      expect(environment.primaryHeadingOrders, hasLength(24));
      expect(
        await environment.database.query('library_document_conversion'),
        hasLength(1),
      );
    },
  );

  test(
    'fixture hashes remain unchanged and production flag remains false',
    () async {
      for (final entry in _expectedHashes.entries) {
        final hash = sha256
            .convert(await File(p.join(fixture.path, entry.key)).readAsBytes())
            .toString();
        expect(hash, entry.value, reason: entry.key);
      }
      expect(useCanonicalLibraryReader, isFalse);
    },
  );

  for (final speed in <CanonicalProofSpeed>[
    CanonicalProofSpeed.slow,
    CanonicalProofSpeed.medium,
    CanonicalProofSpeed.fast,
  ]) {
    test(
      '${speed.name} shared-controller run reaches final SSP block cleanly',
      () async {
        final outcome = await runCanonicalSspDeterministicStress(
          environment: environment,
          speed: speed,
        );
        expect(outcome.finalOrder, environment.blockCount - 1);
        expect(
          outcome.headingBoundariesCrossed,
          environment.primaryHeadingOrders.length,
        );
        expect(outcome.backwardRegressions, 0);
        expect(outcome.headingOscillations, 0);
        expect(outcome.chapterNavigationCallbacks, 0);
        expect(outcome.ordinaryItemJumps, 0);
        expect(outcome.readerRecreations, 0);
        expect(outcome.controllerRecreations, 0);
        expect(outcome.stalled, isFalse);
      },
    );
  }

  test(
    '25 start/stop cycles leave no timer, drift, reset, or duplicate driver',
    () async {
      var pixels = 0.0;
      final target = CallbackReaderAutoScrollTarget()
        ..attach((delta) {
          pixels += delta;
          return true;
        });
      final source = FakeReaderTiltMotionSource();
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: target,
        settings: const ReaderTiltAutoScrollSettings(speedSmoothingFactor: 1),
      );
      final identity = identityHashCode(controller);
      for (var cycle = 0; cycle < 25; cycle++) {
        await controller.activate();
        CanonicalProofMotionAdapter(
          source,
        ).calibrateAndDrive(CanonicalProofSpeed.fast);
        controller.tick(elapsed: const Duration(milliseconds: 100));
        expect(controller.diagnosticHasFrameDriver, isTrue);
        await controller.stop(diagnosticCause: 'phase3-cycle-$cycle');
        final stoppedAt = pixels;
        controller.tick(elapsed: const Duration(seconds: 1));
        expect(pixels, stoppedAt);
        expect(controller.diagnosticHasFrameDriver, isFalse);
        expect(identityHashCode(controller), identity);
      }
      expect(source.startCount, 25);
      expect(source.stopCount, greaterThanOrEqualTo(25));
      controller.dispose();
      target.detach();
      await source.dispose();
    },
  );

  testWidgets(
    'runtime UI exposes safety labels and preserves reader through font/theme stress',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(
        CanonicalSspRuntimeProofApp(environment: environment),
      );
      await tester.pumpAndSettle();
      expect(find.text('CANONICAL SSP RUNTIME PROOF'), findsOneWidget);
      expect(
        find.text('ISOLATED DATABASE • NO USER DATA • CANONICAL READER ONLY'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('canonical-flat-list')), findsOneWidget);
      final initialList = tester.widget(
        find.byKey(const ValueKey('canonical-flat-list')),
      );
      for (var index = 0; index < 20; index++) {
        await tester.tap(find.text(index.isEven ? 'Font +' : 'Font −'));
        await tester.pump();
        await tester.tap(find.text('Day/night'));
        await tester.pump();
      }
      expect(
        identical(
          initialList.key,
          tester.widget(find.byKey(const ValueKey('canonical-flat-list'))).key,
        ),
        isTrue,
      );
      expect(find.textContaining('navigation 0'), findsOneWidget);
      expect(find.textContaining('ordinary jumps 0'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'idle/resume and diagnostic export retain the isolated document',
    (tester) async {
      await tester.pumpWidget(
        CanonicalSspRuntimeProofApp(environment: environment),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start autoscroll'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      String statusText() =>
          (find.textContaining('controller ').evaluate().single.widget as Text)
              .data!;
      final controllerBefore = RegExp(
        r'controller (\d+)',
      ).firstMatch(statusText())!.group(1);
      await tester.pump(const Duration(minutes: 5));
      await tester.tap(find.text('Start autoscroll'));
      await tester.pump(const Duration(seconds: 1));
      final controllerAfter = RegExp(
        r'controller (\d+)',
      ).firstMatch(statusText())!.group(1);
      expect(controllerAfter, controllerBefore);
      await tester.tap(find.text('Export diagnostics'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Stop'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        environment.outputDirectory.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.json'),
        ),
        isNotEmpty,
      );
    },
  );
}
