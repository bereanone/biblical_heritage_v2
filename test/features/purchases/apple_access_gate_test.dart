import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:studybible2/core/theme/app_theme.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/partners/data/ministry_enrollment_service.dart';
import 'package:studybible2/features/partners/data/ministry_profile.dart';
import 'package:studybible2/features/purchases/data/apple_purchase_service.dart';
import 'package:studybible2/features/purchases/presentation/apple_access_gate.dart';

class _IsolatedPaths extends PathProviderPlatform {
  _IsolatedPaths(this.root);
  final String root;
  @override Future<String> getApplicationSupportPath() async => '$root/support';
  @override Future<String> getApplicationDocumentsPath() async => '$root/documents';
  @override Future<String> getTemporaryPath() async => '$root/temporary';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('new user gate, expired trial and purchase preserve access boundaries', (tester) async {
    final originalPaths = PathProviderPlatform.instance;
    final scratch = Directory.systemTemp.createTempSync('studybible-payment-ui-');
    PathProviderPlatform.instance = _IsolatedPaths(scratch.path);
    const channel = MethodChannel('test/isolated-payment-ui');
    final now = DateTime.now().toUtc();
    bool paid = false;
    Map<String, Object?> snapshot() => {
      'paid': paid, 'legacy': false, 'trialStarted': false,
      'checkedAt': now.millisecondsSinceEpoch,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initialize': case 'refresh': case 'restore': return snapshot();
        case 'products': return [
          {'id': ApplePurchaseService.unlockId, 'price': r'$19.99', 'name': 'Permanent unlock'},
          {'id': ApplePurchaseService.trialId, 'price': 'Free', 'name': '14-day Trial'},
        ];
        case 'purchase': paid = true; return {'outcome': 'purchased', 'access': snapshot()};
      }
      return null;
    });
    final service = ApplePurchaseService(channel: channel);
    try {
      await tester.runAsync(() async {
        final roboto = FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
        final playfair = FontLoader('PlayfairDisplay')
          ..addFont(rootBundle.load('assets/fonts/PlayfairDisplay-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/PlayfairDisplay-Bold.ttf'));
        await roboto.load();
        await playfair.load();
        final enrollment = MinistryEnrollment(
          ministryId: MinistryProfile.biblicalHeritage.id,
          setupCompleted: true, grandfathered: false, firstSeenUtc: now,
        );
        await AppSettingsService.instance.saveRawSetting(
          MinistryEnrollmentService.settingKey, jsonEncode(enrollment.toJson()));
      });
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3;
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(AppThemeMode.sepia),
        home: AppleAccessGate(service: service, child: const Scaffold(body: Text('StudyBible content'))),
      )));
      await tester.runAsync(() async {
        for (var n = 0; n < 100 && service.access == null; n++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Welcome to StudyBible'), findsOneWidget);
      expect(find.text('Start 14-day Trial — Free'), findsOneWidget);
      expect(find.text(r'Permanent unlock — $19.99'), findsOneWidget);
      expect(find.text('StudyBible content'), findsNothing);
      expect(tester.takeException(), isNull);
      Future<void> capture(String name) async {
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
      await tester.runAsync(() => capture('studybible-real-trial-gate-review'));
      service.access = AppleAccess(paid: false, legacy: false, trialStarted: true,
        checkedAt: now, trialEndsAt: now.subtract(const Duration(seconds: 1)));
      service.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Your 14-day trial has ended'), findsOneWidget);
      expect(find.text('Start 14-day Trial — Free'), findsNothing);
      expect(find.text('StudyBible content'), findsNothing);
      await tester.runAsync(() => capture('studybible-real-expired-gate-review'));
      await tester.tap(find.text(r'Permanent unlock — $19.99'));
      await tester.pumpAndSettle();
      expect(find.text('StudyBible content'), findsOneWidget);
      service.access = AppleAccess(paid: false, legacy: false, trialStarted: false, checkedAt: now);
      service.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('StudyBible content'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
      await tester.runAsync(() => UserDatabase.instance.close());
      PathProviderPlatform.instance = originalPaths;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      // Keep the isolated files for test evidence; never touch a real library.
    }
  });
}
