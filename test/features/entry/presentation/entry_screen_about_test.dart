import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/entry/presentation/entry_screen.dart';

void main() {
  testWidgets(
    'About dialog shows the package version, not a hard-coded string',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'Biblical Heritage',
        packageName: 'com.example.studybible2',
        version: '2.0.5',
        buildNumber: '2',
        buildSignature: '',
      );

      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: EntryScreen(
            themeMode: AppThemeMode.sepia,
            onThemeChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();

      expect(find.text('About'), findsWidgets);
      expect(
        find.textContaining('Biblical Heritage #StudyBible\nVersion 2.0.5'),
        findsOneWidget,
      );
      expect(find.textContaining('Version 2.0.5'), findsOneWidget);
      expect(find.textContaining('Version 2.0\n'), findsNothing);
    },
  );
}
