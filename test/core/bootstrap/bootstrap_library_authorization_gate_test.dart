import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/core/bootstrap/bootstrap_gate.dart';
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

  testWidgets(
    'clean install without persisted permission stops at one recovery gate',
    (tester) async {
      var validationCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'validateAndroidLibraryTree');
            validationCalls += 1;
            return <String, Object?>{
              'authorized': false,
              'persistedRead': false,
              'persistedWrite': false,
              'enumerates': false,
              'authorizationState': 'libraryRootAuthorizationMissing',
              'validationError': 'No saved Android document-tree URI.',
            };
          });

      await tester.pumpWidget(const BootstrapGate());
      await tester.pump();
      await tester.pump();

      expect(find.text('Library Access Required'), findsOneWidget);
      expect(find.text('Reconnect Existing StudyBible Folder'), findsOneWidget);
      expect(find.textContaining('not been deleted'), findsOneWidget);
      expect(validationCalls, 1);
    },
  );
}
