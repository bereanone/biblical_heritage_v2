import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/bundled_audio_setup.dart';
import 'package:studybible2/features/library/data/optional_book_companions.dart';

Map<String, dynamic> fixture({int coreCount = 6}) => {
  'packages': [
    for (var i = 0; i < coreCount; i++)
      {
        'id': 'core$i',
        'sha256': 'hash$i',
        'url': 'https://example.invalid/$i',
        'title': 'Core $i',
      },
    {
      'id': 'optional',
      'sha256': 'optional-hash',
      'url': 'https://example.invalid/optional',
      'title': 'Optional',
      'requires_source_sha256': OptionalBookCompanions.worSource,
    },
  ],
};
void main() {
  test(
    'direct reader waits for its optional package when core setup is already running',
    () async {
      final coreGate = Completer<void>(), optionalGate = Completer<void>();
      final installed = <String>[];
      final setup = BundledAudioSetup.forTesting(
        loadManifest: () async => fixture(coreCount: 1),
        install: (package) async {
          if (package['id'] == 'core0') await coreGate.future;
          if (package['id'] == 'optional') await optionalGate.future;
          installed.add(package['id'] as String);
        },
      );
      addTearDown(setup.dispose);
      final core = setup.ensure();
      await Future<void>.delayed(Duration.zero);
      var ready = false;
      final book = setup
          .ensureForSource(OptionalBookCompanions.worSource)
          .then((_) => ready = true);
      coreGate.complete();
      await core;
      await Future<void>.delayed(Duration.zero);
      expect(ready, isFalse);
      expect(installed, ['core0']);
      optionalGate.complete();
      await book;
      expect(ready, isTrue);
      expect(installed, ['core0', 'optional']);
      expect(setup.complete, isTrue);
    },
  );

  test('included recordings support growing and smaller catalogs', () async {
    for (final count in [1, 7, 12]) {
      final installed = <String>[];
      final setup = BundledAudioSetup.forTesting(
        loadManifest: () async => fixture(coreCount: count),
        install: (p) async => installed.add(p['id'] as String),
      );
      await setup.ensure();
      expect(setup.error, isNull);
      expect(setup.complete, isTrue);
      expect(installed, [for (var i = 0; i < count; i++) 'core$i']);
      setup.dispose();
    }
  });
  test('duplicate package identities still fail manifest validation', () async {
    final setup = BundledAudioSetup.forTesting(
      loadManifest: () async => fixture(coreCount: 1)
        ..['packages'].add({
          'id': 'core0',
          'sha256': 'other',
          'url': 'https://example.invalid/duplicate',
          'title': 'Duplicate',
        }),
      install: (_) async => fail('Invalid manifest must not install'),
    );
    addTearDown(setup.dispose);
    await setup.ensure();
    expect(setup.error, isNotNull);
    expect(setup.complete, isFalse);
  });

  test('existing files verify without progress or ready banner', () async {
    final setup = BundledAudioSetup.forTesting(
      loadManifest: () async => fixture(),
      verifyInstalled: (_) async => true,
      install: (_) async => fail('Existing files must not download again'),
    );
    addTearDown(setup.dispose);
    setup.addListener(() => expect(setup.showProgress, isFalse));
    await setup.ensure();
    expect(setup.complete, isTrue);
    expect(setup.completedAt, isNull);
  });
  test('missing package displays progress and retry on failure', () async {
    final setup = BundledAudioSetup.forTesting(
      loadManifest: () async => fixture(),
      verifyInstalled: (_) async => false,
      install: (_) async => throw StateError('offline'),
    );
    addTearDown(setup.dispose);
    await setup.ensure();
    expect(setup.showProgress, isTrue);
    expect(setup.error, isNotNull);
  });
  test(
    'ready setup survives empty reload, unrelated catalog and navigation',
    () async {
      var manifests = 0;
      final installed = <String>[];
      final setup = BundledAudioSetup.forTesting(
        loadManifest: () async {
          manifests++;
          return fixture();
        },
        install: (p) async {
          installed.add(p['id'] as String);
        },
      );
      addTearDown(setup.dispose);
      await setup.ensure(sourceHashes: {'unrelated-one'});
      expect(setup.complete, isTrue);
      await setup.ensure(sourceHashes: {});
      await setup.ensure(sourceHashes: {'unrelated-two'});
      await setup.ensure(sourceHashes: {});
      expect(manifests, 1);
      expect(installed.length, 6);
      expect(setup.complete, isTrue);
    },
  );
  test(
    'new matching optional source installs only new package and stays ready',
    () async {
      final installed = <String>[];
      final setup = BundledAudioSetup.forTesting(
        loadManifest: () async => fixture(),
        install: (p) async {
          installed.add(p['id'] as String);
        },
      );
      addTearDown(setup.dispose);
      await setup.ensure(sourceHashes: {});
      await setup.ensure(sourceHashes: {OptionalBookCompanions.worSource});
      expect(installed.length, 7);
      expect(installed.last, 'optional');
      await setup.ensure(sourceHashes: {});
      await setup.ensure(sourceHashes: {OptionalBookCompanions.worSource});
      expect(installed.length, 7);
      expect(setup.complete, isTrue);
    },
  );
  test('corrected BRHC selects only the matching recorded edition', () async {
    final installed = <String>[];
    final setup = BundledAudioSetup.forTesting(
      loadManifest: () async => fixture()
        ..['packages'].add({
          'id': 'brhc1914',
          'sha256': 'brhc-hash',
          'title': 'Bible Readings for the Home Circle (1914)',
          'delivery': 'assets',
          'requires_source_sha256': OptionalBookCompanions.brhc1914Source,
        }),
      install: (package) async => installed.add(package['id'] as String),
    );
    addTearDown(setup.dispose);
    await setup.ensure(sourceHashes: {'older-brhc-edition'});
    expect(installed, isNot(contains('brhc1914')));
    await setup.ensure(sourceHashes: {OptionalBookCompanions.brhc1914Source});
    expect(installed.last, 'brhc1914');
    expect(installed.length, 7);
    await setup.ensure(sourceHashes: {});
    expect(installed.length, 7);
  });
  test('retry retains already verified packages after interruption', () async {
    final installed = <String>[];
    var fail = true;
    final setup = BundledAudioSetup.forTesting(
      loadManifest: () async => fixture(),
      install: (p) async {
        if (p['id'] == 'core2' && fail)
          throw StateError('connection interrupted');
        installed.add(p['id'] as String);
      },
    );
    addTearDown(setup.dispose);
    await setup.ensure(sourceHashes: {});
    expect(setup.error, isNotNull);
    expect(installed, ['core0', 'core1']);
    fail = false;
    await setup.ensure(sourceHashes: {});
    expect(setup.error, isNull);
    expect(setup.complete, isTrue);
    expect(installed.length, 6);
  });
}
