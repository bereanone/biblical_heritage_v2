import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/purchases/data/android_purchase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/play-purchases');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final now = DateTime.now().toUtc();
  Map<String, Object?> state({
    bool paid = false,
    DateTime? end,
    String? outcome,
  }) => {
    'paid': paid,
    'legacy': false,
    'checkedAt': now.millisecondsSinceEpoch,
    'trialEndsAt': end?.millisecondsSinceEpoch,
    'price': r'$19.99',
    'trialAvailable': end == null,
    'outcome': outcome,
  };
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'new user remains locked; starting trial requires explicit action',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return state(
          end: call.method == 'startTrial'
              ? now.add(const Duration(days: 14))
              : null,
        );
      });
      final service = AndroidPurchaseService(channel: channel);
      await service.initialize();
      expect(service.access!.allows(now), false);
      expect(calls, ['initialize']);
      await service.startTrial();
      expect(service.access!.allows(now), true);
      expect(service.access!.allows(now.add(const Duration(days: 14))), false);
    },
  );
  test('cancelled and pending payments do not unlock expired trial', () async {
    var outcome = 'cancelled';
    messenger.setMockMethodCallHandler(
      channel,
      (_) async =>
          state(end: now.subtract(const Duration(days: 1)), outcome: outcome),
    );
    final service = AndroidPurchaseService(channel: channel);
    await service.purchase();
    expect(service.access!.allows(now), false);
    outcome = 'pending';
    await service.purchase();
    expect(service.access!.allows(now), false);
    expect(service.message, contains('awaiting approval'));
  });
  test(
    'verified purchase and restore unlock; refund refresh revokes',
    () async {
      var paid = true;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            state(paid: paid, end: now.subtract(const Duration(days: 1))),
      );
      final service = AndroidPurchaseService(channel: channel);
      await service.purchase();
      expect(service.access!.allows(now), true);
      await service.restore();
      expect(service.access!.allows(now), true);
      paid = false;
      await service.refresh();
      expect(service.access!.allows(now), false);
    },
  );
  test('store errors never grant new access', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    final service = AndroidPurchaseService(channel: channel);
    await service.purchase();
    expect(service.access, isNull);
    expect(service.message, isNotNull);
    expect(service.busy, false);
  });
  test('clock rollback cannot extend beyond previously checked expiry', () {
    final access = AndroidAccess(
      paid: false,
      legacy: false,
      checkedAt: now,
      trialEndsAt: now,
    );
    expect(access.allows(now.subtract(const Duration(days: 5))), false);
  });
  test(
    'saved ministry selection accompanies price query and purchase',
    () async {
      var ministry = 'adl';
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return state();
      });
      final service = AndroidPurchaseService(
        channel: channel,
        ministryId: () => ministry,
      );
      await service.initialize();
      await service.purchase();
      expect(calls.map((call) => call.arguments['ministryId']), ['adl', 'adl']);
      ministry = 'heritage_and_hope';
      await service.refresh();
      expect(calls.last.arguments['ministryId'], 'heritage_and_hope');
    },
  );
  test(
    'recovery outage warns without preventing explicit trial or paid restore',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          ...state(
            paid: call.method == 'restore',
            end: call.method == 'startTrial'
                ? now.add(const Duration(days: 14))
                : null,
          ),
          'price': null,
          'accessWarning':
              'Previous free access could not be checked. Try again before purchasing.',
        },
      );
      final service = AndroidPurchaseService(channel: channel);
      await service.initialize();
      expect(service.access!.allows(now), false);
      expect(service.price, isNull);
      expect(service.trialAvailable, true);
      expect(service.message, contains('Previous free access'));
      await service.startTrial();
      expect(service.access!.allows(now), true);
      await service.restore();
      expect(service.access!.paid, true);
      expect(service.message, contains('Previous free access'));
    },
  );
  test(
    'failed paid restore preserves recovery warning instead of claiming no entitlement',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          ...state(),
          'price': null,
          'accessWarning': 'Previous free access could not be checked.',
        },
      );
      final service = AndroidPurchaseService(channel: channel);
      await service.restore();
      expect(service.message, 'Previous free access could not be checked.');
      expect(service.access!.legacy, false);
    },
  );
}
