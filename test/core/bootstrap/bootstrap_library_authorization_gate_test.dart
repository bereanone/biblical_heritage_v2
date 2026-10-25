import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/core/bootstrap/bootstrap_gate.dart';
import 'package:studybible2/features/partners/data/ministry_enrollment_service.dart';
import 'package:studybible2/core/bootstrap/library_root_native.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('studybible/library_root');

  setUp(() {
    LibraryRootNative.debugUsesAndroidDocumentTree = true;
    LibraryRootService.instance.invalidateCachedSelection();
  });

  tearDown(() {
    LibraryRootNative.debugUsesAndroidDocumentTree = null;
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('clean Android install opens with its private library', (
    tester,
  ) async {
    var validationCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'validateAndroidLibraryTree');
          validationCalls += 1;
          return <String, Object?>{
            'authorized': true,
            'path': '/private/StudyBibleMirror_Private',
            'displayName': 'StudyBible2 private library',
            'persistedRead': true,
            'persistedWrite': true,
            'enumerates': true,
            'validFolder': true,
            'expectedMarkersFound': true,
            'authorizationState': 'privateStorage',
          };
        });

    await tester.pumpWidget(
      BootstrapGate(
        enrollmentService: MinistryEnrollmentService(
          read: () async => null,
          write: (_) async {},
          seed: (_) async {},
          loadInstallState: () async => <String, Object?>{},
          saveInstallState: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Library Access Required'), findsNothing);
    expect(find.text('Reconnect Existing StudyBible Folder'), findsNothing);
    expect(validationCalls, 1);
  });

  testWidgets('unavailable Android private storage stops at the recovery gate', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'validateAndroidLibraryTree');
          return <String, Object?>{
            'authorized': false,
            'persistedRead': false,
            'persistedWrite': false,
            'enumerates': false,
            'authorizationState': 'privateStorageUnavailable',
            'validationError':
                'App storage is unavailable. Free device space and try again.',
          };
        });

    await tester.pumpWidget(
      BootstrapGate(
        enrollmentService: MinistryEnrollmentService(
          read: () async => null,
          write: (_) async {},
          seed: (_) async {},
          loadInstallState: () async => <String, Object?>{},
          saveInstallState: (_) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Library Access Required'), findsOneWidget);
    expect(find.text('Reconnect Existing StudyBible Folder'), findsOneWidget);
  });
}
