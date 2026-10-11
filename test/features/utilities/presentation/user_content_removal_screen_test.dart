import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/user_content_removal_service.dart';
import 'package:studybible2/features/utilities/presentation/user_content_removal_screen.dart';

class FakeRemoval extends UserContentRemovalService {
  var removed = false;
  @override
  Future<UserContentRemovalPlan> preview(
    UserContentRemovalScope scope,
    bool backups,
  ) async => UserContentRemovalPlan(
    root: '/private/test',
    scope: scope,
    includeBackups: backups,
    files: {'/private/test/ePubs/book.epub': 100},
    fileBytes: 100,
    databaseBytes: 500,
    remoteFiles: 0,
    remoteBytes: 0,
    ownedRoots: ['/private/test'],
  );
  @override
  Future<int> remove(UserContentRemovalPlan plan) async {
    removed = true;
    return 100;
  }
}

void main() {
  testWidgets('preview and cancellation cannot remove data', (tester) async {
    final service = FakeRemoval();
    await tester.pumpWidget(
      MaterialApp(home: UserContentRemovalScreen(service: service)),
    );
    await tester.tap(find.text('Preview Removal'));
    await tester.pumpAndSettle();
    expect(service.removed, false);
    await tester.scrollUntilVisible(find.text('Review and Remove'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review and Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this data permanently?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.removed, false);
  });
}
