import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/bootstrap/library_root_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('studybible/library_root');

  tearDown(() {
    LibraryRootNative.debugUsesAndroidDocumentTree = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<AndroidLibraryScanReport?> runReport({
    required Map<String, Object?> response,
    bool force = false,
  }) async {
    LibraryRootNative.debugUsesAndroidDocumentTree = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'scanAndroidLibraryTree');
          expect(call.arguments, {'force': force});
          return response;
        });
    return LibraryRootNative.scanAndroidLibraryTree(force: force);
  }

  test('unchanged folders report no full inspection', () async {
    final report = await runReport(
      response: {
        'elapsedMs': 12,
        'changed': 0,
        'unchanged': 31,
        'removed': 0,
        'fileCount': 31,
        'fullScan': false,
      },
    );
    expect(report?.changed, 0);
    expect(report?.unchanged, 31);
    expect(report?.fullScan, isFalse);
  });

  test(
    'new or changed content is surfaced without hiding unchanged files',
    () async {
      final report = await runReport(
        response: {
          'changed': 1,
          'unchanged': 31,
          'removed': 0,
          'fileCount': 32,
          'fullScan': false,
        },
      );
      expect(report?.changed, 1);
      expect(report?.unchanged, 31);
    },
  );

  test('removed content is reported safely', () async {
    final report = await runReport(
      response: {
        'changed': 0,
        'unchanged': 31,
        'removed': 1,
        'fileCount': 31,
        'fullScan': false,
      },
    );
    expect(report?.removed, 1);
    expect(report?.fileCount, 31);
  });

  test('missing or invalid snapshot requests a safe full scan', () async {
    final report = await runReport(
      response: {
        'changed': 31,
        'unchanged': 0,
        'removed': 0,
        'fileCount': 31,
        'fullScan': true,
      },
    );
    expect(report?.fullScan, isTrue);
  });

  test(
    'manual rescan forwards force and performs complete verification',
    () async {
      final report = await runReport(
        force: true,
        response: {
          'changed': 31,
          'unchanged': 0,
          'removed': 0,
          'fileCount': 31,
          'fullScan': true,
        },
      );
      expect(report?.fullScan, isTrue);
      expect(report?.changed, 31);
    },
  );

  test(
    'interrupted scan error remains non-fatal to the caller index',
    () async {
      LibraryRootNative.debugUsesAndroidDocumentTree = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'library_tree_scan_failed',
              message: 'previous index remains available',
            );
          });
      await expectLater(
        LibraryRootNative.scanAndroidLibraryTree(),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
