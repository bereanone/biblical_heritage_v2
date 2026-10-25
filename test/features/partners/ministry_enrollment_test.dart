import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/partners/data/ministry_enrollment_service.dart';
import 'package:studybible2/features/partners/data/ministry_profile.dart';

void main() {
  String? saved;
  late DateTime clock;
  late List<String> seeded;
  MinistryEnrollmentService makeService() => MinistryEnrollmentService(
    read: () async => saved,
    write: (value) async => saved = value,
    seed: (profile) async => seeded.add(profile.id),
    now: () => clock,
  );
  setUp(() {
    saved = null;
    clock = DateTime.utc(2026, 10, 20);
    seeded = [];
  });

  test(
    'new installation requires one-time choice and records a fourteen-day trial',
    () async {
      final service = makeService();
      final state = await service.initialize(existingInstall: false);
      expect(state.setupCompleted, isFalse);
      expect(state.grandfathered, isFalse);
      expect(state.trialEndsUtc, DateTime.utc(2026, 11, 3));
    },
  );
  test(
    'existing installation keeps full access and default branding',
    () async {
      final state = await makeService().initialize(existingInstall: true);
      expect(state.setupCompleted, isTrue);
      expect(state.grandfathered, isTrue);
      expect(state.profile, MinistryProfile.biblicalHeritage);
    },
  );
  test(
    'ADL selection survives restart without resetting access or trial',
    () async {
      final service = makeService();
      await service.initialize(existingInstall: true);
      await service.select(MinistryProfile.adventDefenseLeague);
      clock = clock.add(const Duration(days: 30));
      final restored = await makeService().initialize(existingInstall: false);
      expect(restored.profile, MinistryProfile.adventDefenseLeague);
      expect(restored.ministryId, 'adl');
      expect(restored.profile!.unlockPriceUsdCents, 999);
      expect(restored.displayProfile, MinistryProfile.biblicalHeritage);
      expect(restored.displayProfile.artworkAsset, isNull);
      expect(restored.displayProfile.websiteUrl, 'https://biblicalheritage.net');
      expect(restored.setupCompleted, isTrue);
      expect(restored.grandfathered, isTrue);
      expect(restored.firstSeenUtc, DateTime.utc(2026, 10, 20));
    },
  );
  test(
    'skipping code is persisted and never re-prompts after an update',
    () async {
      final service = makeService();
      await service.initialize(existingInstall: false);
      await service.select(MinistryProfile.biblicalHeritage);
      final restored = await makeService().initialize(existingInstall: true);
      expect(restored.setupCompleted, isTrue);
      expect(restored.grandfathered, isFalse);
      expect(restored.profile, MinistryProfile.biblicalHeritage);
    },
  );
  test('switching branding preserves grandfathered access', () async {
    final service = makeService();
    await service.initialize(existingInstall: true);
    await service.select(MinistryProfile.adventDefenseLeague);
    final state = await service.select(MinistryProfile.biblicalHeritage);
    expect(state.grandfathered, isTrue);
    expect(state.setupCompleted, isTrue);
  });
  test('unknown saved ministry remains selected and retains access', () async {
    saved = jsonEncode(
      MinistryEnrollment(
        ministryId: 'future_ministry',
        setupCompleted: true,
        grandfathered: true,
        firstSeenUtc: clock,
      ).toJson(),
    );
    final restored = await makeService().initialize(existingInstall: false);
    expect(restored.ministryId, 'future_ministry');
    expect(restored.setupCompleted, isTrue);
    expect(restored.grandfathered, isTrue);
  });
  test(
    'malformed state is not silently replaced or converted to free access',
    () async {
      saved = '{broken';
      final service = makeService();
      await expectLater(
        service.initialize(existingInstall: true),
        throwsFormatException,
      );
      expect(saved, '{broken');
      expect(service.state.value, isNull);
    },
  );
  test('failed save leaves setup incomplete and can be retried', () async {
    var fail = false;
    final service = MinistryEnrollmentService(
      read: () async => saved,
      write: (value) async {
        if (fail) throw StateError('disk full');
        saved = value;
      },
      seed: (_) async {},
    );
    await service.initialize(existingInstall: false);
    fail = true;
    await expectLater(
      service.select(MinistryProfile.biblicalHeritage),
      throwsStateError,
    );
    expect(service.state.value!.setupCompleted, isFalse);
    fail = false;
    await service.select(MinistryProfile.biblicalHeritage);
    expect(service.state.value!.setupCompleted, isTrue);
  });
  test(
    'partner code is normalized and unavailable ministries are rejected',
    () {
      expect(
        MinistryProfile.forCode(' adl '),
        MinistryProfile.adventDefenseLeague,
      );
      expect(MinistryProfile.forCode(''), isNull);
      expect(MinistryProfile.forCode(' hh '), MinistryProfile.heritageAndHope);
      expect(MinistryProfile.forCode('HH'), MinistryProfile.heritageAndHope);
      expect(
        MinistryProfile.forCode('Biblical Hope'),
        MinistryProfile.heritageAndHope,
      );
      expect(MinistryProfile.adventDefenseLeague.starterTags, isEmpty);
    },
  );
  test(
    'known ministry content can be seeded on updates without setup reset',
    () async {
      final service = makeService();
      await service.initialize(existingInstall: false);
      await service.select(MinistryProfile.adventDefenseLeague);
      seeded.clear();
      final restored = await makeService().initialize(existingInstall: false);
      expect(seeded, ['adl']);
      expect(restored.setupCompleted, isTrue);
      expect(restored.grandfathered, isFalse);
    },
  );
  test(
    'a fresh install interrupted during library setup stays new after restart',
    () async {
      var install = <String, Object?>{};
      MinistryEnrollmentService withInstall() => MinistryEnrollmentService(
        read: () async => saved,
        write: (value) async => saved = value,
        seed: (_) async {},
        loadInstallState: () async => Map.of(install),
        saveInstallState: (value) async => install = value,
      );
      await withInstall().captureInstallBeforeBootstrap();
      install['device_id'] = 'created-by-bootstrap';
      install['startup_reviewed_version'] = 'new-version';
      final restarted = withInstall();
      await restarted.captureInstallBeforeBootstrap();
      final state = await restarted.initialize();
      expect(state.grandfathered, isFalse);
      expect(state.setupCompleted, isFalse);
    },
  );
  test(
    'legacy install origin survives upgrade retries and preserves other settings',
    () async {
      var install = <String, Object?>{
        'device_id': 'early-customer',
        'other': 42,
      };
      final service = MinistryEnrollmentService(
        read: () async => saved,
        write: (value) async => saved = value,
        seed: (_) async {},
        loadInstallState: () async => Map.of(install),
        saveInstallState: (value) async => install = value,
      );
      await service.captureInstallBeforeBootstrap();
      await service.captureInstallBeforeBootstrap();
      expect(install['other'], 42);
      expect((await service.initialize()).grandfathered, isTrue);
    },
  );
}
