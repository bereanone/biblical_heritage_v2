import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';
import 'package:studybible2/core/app_info/store_update_notice.dart';

class TestOS extends UpgraderOS {
  TestOS(this.type);
  final UpgraderOSType type;
  @override
  UpgraderOSType get currentOSType => type;
}

class TestStore extends UpgraderStore {
  String? latest;
  int calls = 0;
  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required Version installedVersion,
    required String? country,
    required String? language,
  }) async {
    calls++;
    return UpgraderVersionInfo(
      installedVersion: installedVersion,
      appStoreVersion: latest == null ? null : Version.parse(latest!),
      appStoreListingURL: 'https://apps.apple.com/app/id6760154157',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'StudyBible',
      packageName: 'com.deanbowen.bibleAppMac',
      version: '2.0.5',
      buildNumber: '150',
      buildSignature: '',
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform automatically checks and offers a newer release', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final store = TestStore()..latest = '2.0.6';
      final upgrader = Upgrader(
        upgraderOS: TestOS(
          platform == TargetPlatform.iOS
              ? UpgraderOSType.ios
              : UpgraderOSType.android,
        ),
        storeController: UpgraderStoreController(
          oniOS: () => store,
          onAndroid: () => store,
        ),
      );
      await tester.runAsync(() => upgrader.initialize());
      await tester.pumpWidget(
        MaterialApp(
          home: StoreUpdateNotice(
            upgrader: upgrader,
            child: const Scaffold(body: Text('Bible reader')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.calls, 1);
      expect(find.text('UPDATE NOW'), findsOneWidget);
      expect(find.text('IGNORE'), findsNothing);
      await tester.tap(find.text('LATER'));
      await tester.pumpAndSettle();
      expect(find.text('Bible reader'), findsOneWidget);
      await tester.runAsync(
        () => upgrader.didChangeAppLifecycleState(AppLifecycleState.resumed),
      );
      await tester.pumpAndSettle();
      expect(store.calls, 2);
      expect(find.text('UPDATE NOW'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final latest in <String?>['2.0.5', '1.0.2', null]) {
    testWidgets(
      'no prompt for current, older or unavailable store version: $latest',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final store = TestStore()..latest = latest;
        final upgrader = Upgrader(
          upgraderOS: TestOS(UpgraderOSType.ios),
          storeController: UpgraderStoreController(oniOS: () => store),
        );
        await tester.runAsync(() => upgrader.initialize());
        await tester.pumpWidget(
          MaterialApp(
            home: StoreUpdateNotice(
              upgrader: upgrader,
              child: const Scaffold(body: Text('Bible reader')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('UPDATE NOW'), findsNothing);
        expect(find.text('Bible reader'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
