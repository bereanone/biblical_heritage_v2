import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:studybible2/main.dart' as app;

/// Drives the real Bible Explorer "Read aloud" flow end to end on whatever
/// device this runs on: boots the actual app, navigates the way a user
/// would, taps the real button, and watches the narrator's own diagnostic
/// log (kokoro_mac_test_narrator.dart's recordDiagnostic) for genuine
/// engine/playback events rather than asserting on internal state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bible Explorer read-aloud: visible, tappable, engine speaks', (
    tester,
  ) async {
    final logFile = File(
      '${(await getTemporaryDirectory()).path}/narration-events.log',
    );
    if (await logFile.exists()) await logFile.delete();

    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // ignore: avoid_print
    print('STAGE entry_screen');

    final skip = find.text('Skip for Now');
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // ignore: avoid_print
      print('STAGE dismissed_setup_dialog');
    }

    final bibleExplorerButton = find.widgetWithText(
      ElevatedButton,
      'Bible Explorer',
    );
    expect(bibleExplorerButton, findsOneWidget);
    await tester.tap(bibleExplorerButton);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // ignore: avoid_print
    print('STAGE bible_explorer_open');

    final tiltSheetTitle = find.text('Tilt Auto-scroll Settings');
    // ignore: avoid_print
    print(
      'RESULT tiltSettingsSheetOpenByDefault=${tiltSheetTitle.evaluate().isNotEmpty}',
    );

    // BUTTON VISIBLE
    final readAloud = find.widgetWithText(TextButton, 'Read aloud');
    final visible = readAloud.evaluate().isNotEmpty;
    // ignore: avoid_print
    print('RESULT buttonVisible=$visible');
    expect(
      readAloud,
      findsOneWidget,
      reason: 'Read aloud button not found in rendered Bible Explorer layout',
    );

    // TAP HANDLED
    await tester.tap(readAloud);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final stillBootstrap = find
        .widgetWithText(TextButton, 'Read aloud')
        .evaluate()
        .isNotEmpty;
    // ignore: avoid_print
    print('RESULT tapHandled=${!stillBootstrap}');
    // ignore: avoid_print
    print(
      'RESULT playPauseRowShown=${find.text('Voice').evaluate().isNotEmpty}',
    );

    // ENGINE INIT / SPEECH GENERATED / PLAYBACK — give real wall-clock time
    // for first-run asset staging (~360MB) + native model load + synthesis.
    var sawPlay = false;
    var sawComplete = false;
    var sawPauseIcon = false;
    var sawErrorSnackbar = false;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byIcon(Icons.pause).evaluate().isNotEmpty) sawPauseIcon = true;
      if (find.textContaining('Speech stopped').evaluate().isNotEmpty ||
          find.textContaining('narration stopped').evaluate().isNotEmpty) {
        sawErrorSnackbar = true;
      }
      if (await logFile.exists()) {
        final content = await logFile.readAsString();
        if (content.contains(' play ')) sawPlay = true;
        if (content.contains(' complete ')) sawComplete = true;
      }
      if (sawComplete || sawErrorSnackbar) break;
    }
    // ignore: avoid_print
    print('RESULT sawPauseIcon=$sawPauseIcon');
    // ignore: avoid_print
    print('RESULT sawErrorSnackbar=$sawErrorSnackbar');
    // ignore: avoid_print
    print('RESULT sawPlayLogEntry=$sawPlay');
    // ignore: avoid_print
    print('RESULT sawCompleteLogEntry=$sawComplete');

    if (find.textContaining('Speech stopped').evaluate().isNotEmpty) {
      final errorText = tester
          .widgetList<Text>(find.textContaining('Speech stopped'))
          .map((t) => t.data)
          .join(' | ');
      // ignore: avoid_print
      print('RESULT errorMessage=$errorText');
    }

    if (await logFile.exists()) {
      final lines = await logFile.readAsLines();
      // ignore: avoid_print
      print('LOG_START');
      for (final l in lines) {
        // ignore: avoid_print
        print('LOG: $l');
      }
      // ignore: avoid_print
      print('LOG_END count=${lines.length}');
    } else {
      // ignore: avoid_print
      print('LOG_MISSING');
    }

    // ignore: avoid_print
    print(jsonEncode({'stage': 'done'}));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
