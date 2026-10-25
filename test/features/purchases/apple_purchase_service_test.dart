import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/purchases/data/apple_purchase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime.utc(2026, 10, 20);
  Map<String, Object?> snapshot({bool paid = false, bool legacy = false, DateTime? end}) => {
    'paid': paid, 'legacy': legacy, 'trialStarted': end != null,
    'checkedAt': start.millisecondsSinceEpoch,
    if (end != null) 'trialEndsAt': end.millisecondsSinceEpoch,
  };
  test('trial expires at exactly fourteen days and cannot roll back before checked time', () {
    final end = start.add(const Duration(days: 14));
    final access = AppleAccess.fromMap(snapshot(end: end));
    expect(access.allows(end.subtract(const Duration(milliseconds: 1))), isTrue);
    expect(access.allows(end), isFalse);
    final expired = AppleAccess.fromMap({...snapshot(end: end), 'checkedAt': end.millisecondsSinceEpoch});
    expect(expired.allows(start), isFalse);
  });
  test('permanent and early customer rights do not expire', () {
    expect(AppleAccess.fromMap(snapshot(paid: true)).allows(DateTime.utc(2100)), isTrue);
    expect(AppleAccess.fromMap(snapshot(legacy: true)).allows(DateTime.utc(2100)), isTrue);
    expect(AppleAccess.fromMap(snapshot()).allows(start), isFalse);
  });
  const channel = MethodChannel('test/purchase');
  late List<MethodCall> calls;
  late Map<String, Object?> current;
  late String outcome;
  late bool fail;
  late ApplePurchaseService service;
  setUp(() {
    calls = []; current = snapshot(); outcome = 'cancelled'; fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (fail) throw PlatformException(code: 'offline', message: 'Offline');
      switch (call.method) {
        case 'initialize': case 'refresh': case 'restore': return current;
        case 'products': return [
          {'id': ApplePurchaseService.unlockId, 'price': '₱1,290.00', 'name': 'Unlock'},
          {'id': ApplePurchaseService.trialId, 'price': 'Free', 'name': '14-day Trial'},
        ];
        case 'purchase': return {'outcome': outcome, if (outcome == 'purchased') 'access': current};
        case 'redeem': return null;
      }
      throw UnsupportedError(call.method);
    });
    service = ApplePurchaseService(channel: channel);
  });
  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test('uses localized store price and independent trial product', () async {
    await service.initialize(existingCustomer: false);
    expect(service.price, '₱1,290.00');
    expect(service.trialAvailable, isTrue);
    await service.purchase(trial: true);
    expect((calls.last.arguments as Map)['id'], ApplePurchaseService.trialId);
    expect(service.access!.allows(start), isFalse);
  });
  test('pending and cancelled purchases never unlock', () async {
    await service.initialize(existingCustomer: false);
    outcome = 'pending'; await service.purchase();
    expect(service.message, contains('awaiting approval'));
    expect(service.access!.paid, isFalse);
    outcome = 'cancelled'; await service.purchase();
    expect(service.access!.paid, isFalse);
  });
  test('verified purchase restores and revoked rights lock on refresh', () async {
    await service.initialize(existingCustomer: false);
    current = snapshot(paid: true); outcome = 'purchased';
    await service.purchase(); expect(service.access!.paid, isTrue);
    await service.restore(); expect(service.access!.paid, isTrue);
    current = snapshot(); await service.refresh();
    expect(service.access!.allows(start), isFalse);
  });
  test('store failures preserve existing verified access', () async {
    current = snapshot(paid: true);
    await service.initialize(existingCustomer: false);
    fail = true; await service.refresh();
    expect(service.access!.paid, isTrue);
    expect(service.message, 'Offline');
    expect(service.busy, isFalse);
  });
}
