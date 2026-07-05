import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/presentation/elibrary_setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hides the saved CaptureClipper bookmark token', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureClipperFolderDetails(
            loading: false,
            path:
                '/Users/deanbowen/Library/CloudStorage/OneDrive-Personal/CloudFiles',
            access: 'Saved',
            status: 'CaptureClipper folder ready.',
          ),
        ),
      ),
    );

    expect(find.textContaining('bookmark-token'), findsNothing);
    expect(
      find.text(
        'Folder path: /Users/deanbowen/Library/CloudStorage/OneDrive-Personal/CloudFiles',
      ),
      findsOneWidget,
    );
    expect(find.text('Folder access: Saved'), findsOneWidget);
    expect(find.text('CaptureClipper folder ready.'), findsOneWidget);
  });
}
