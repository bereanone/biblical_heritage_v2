import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/bundled_audio_setup.dart';
import 'package:studybible2/features/library/data/optional_book_companions.dart';

Map<String, dynamic> fixture() => {
  'packages': [
    for (var i = 0; i < 6; i++)
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
