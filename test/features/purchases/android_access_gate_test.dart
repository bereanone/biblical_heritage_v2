import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/purchases/data/android_purchase_service.dart';
import 'package:studybible2/features/purchases/presentation/android_access_gate.dart';

class FakePlay extends AndroidPurchaseService {
  FakePlay() {
    price = r'$19.99';
  }
  int purchases = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> purchase() async {
    purchases++;
  }

  void update({required bool paid, required DateTime end}) {
    access = AndroidAccess(
      paid: paid,
      legacy: false,
      checkedAt: DateTime.now().toUtc(),
      trialEndsAt: end,
    );
    notifyListeners();
  }
}

void main() {
  testWidgets('expiry blocks every route and Not now does not bypass gate', (
    tester,
  ) async {
    final service = FakePlay();
    final end = DateTime.now().toUtc().subtract(const Duration(days: 1));
    service.update(paid: false, end: end);
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidAccessGate(
          service: service,
          child: const Text('PRIVATE READER AND NOTES'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('PRIVATE READER AND NOTES'), findsNothing);
    expect(find.text('Your 14-day trial has ended'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.text('PRIVATE READER AND NOTES'), findsNothing);
    await tester.tap(find.textContaining('Purchase permanent access —'));
    await tester.pump();
    expect(service.purchases, 1);
    expect(find.text('PRIVATE READER AND NOTES'), findsNothing);
    service.update(paid: true, end: end);
    await tester.pump();
    expect(find.text('PRIVATE READER AND NOTES'), findsOneWidget);
    service.update(paid: false, end: end);
    await tester.pump();
    expect(find.text('PRIVATE READER AND NOTES'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
  testWidgets('trial expires while app remains open', (tester) async {
    final service = FakePlay();
    service.update(
      paid: false,
      end: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidAccessGate(
          service: service,
          child: const Text('PRIVATE READER AND NOTES'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('PRIVATE READER AND NOTES'), findsOneWidget);
    service.update(paid: false, end: DateTime.now().toUtc());
    await tester.pump();
    expect(find.text('PRIVATE READER AND NOTES'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });
}
