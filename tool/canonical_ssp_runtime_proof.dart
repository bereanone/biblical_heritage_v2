import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:studybible2/features/library/dev/canonical_ssp_runtime_proof.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final proofRoot = await Directory(
    '/private/tmp/canonical_ssp_runtime_proof',
  ).create(recursive: true);
  final materializedFixture = await proofRoot.createTemp(
    'canonical_ssp_bundled_fixture_',
  );
  const assets = <String>[
    'capture.html',
    'manifest.json',
    'manifest.pre-schema2-repair.json',
    'images/image_0001.png',
  ];
  for (final relativePath in assets) {
    final data = await rootBundle.load(
      'test/fixtures/elibrary/real_ssp/$relativePath',
    );
    final destination = File(p.join(materializedFixture.path, relativePath));
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
  final environment = await CanonicalSspRuntimeEnvironment.create(
    fixtureRoot: materializedFixture,
    temporaryParent: proofRoot,
  );
  runApp(CanonicalSspRuntimeProofApp(environment: environment));
}
