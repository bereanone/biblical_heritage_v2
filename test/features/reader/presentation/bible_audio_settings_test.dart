import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/theme/app_theme_mode.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controls.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/reader/presentation/bible_audio_settings.dart';
import 'package:studybible2/features/reader/presentation/bible_loop_announcement_settings.dart';
import 'package:studybible2/features/reader/presentation/viewer_mode_popup.dart';
import 'package:studybible2/features/reader/presentation/viewer_presentation_settings.dart';

class _Target implements ReaderAutoScrollTarget {
  @override
  bool get isAttached => true;
  @override
  bool scrollBy(double delta) => true;
}

void main() {
  testWidgets('audio setup preserves saved choices and pauses when disabled', (
    tester,
  ) async {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      driveFrames: false,
      narrationControlsPacing: true,
      preferences: const MacAutoscrollPreferences(
        audioEnabled: true,
        speechRate: 1.25,
        baseSpeed: 24,
        maximumStep: 3,
        lastNonzeroStep: 2,
        announceChapter: true,
      ),
    );
    addTearDown(controller.dispose);
    final saved = <MacAutoscrollPreferences>[];
    final announcements = <BibleLoopUnit, bool>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BibleAudioSettings(
            controller: controller,
            announcements: const BibleLoopAnnouncementSettings(
              book: false,
              chapter: true,
              verse: true,
            ),
            onPreferencesChanged: saved.add,
            onAnnouncementChanged: (unit, value) => announcements[unit] = value,
            onPronunciations: () {},
          ),
        ),
      ),
    );
    expect(saved, isEmpty);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('bible-audio-speed')))
          .value,
      1.25,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('bible-audio-announce-book')),
          )
          .value,
      isFalse,
    );
    controller.setSignedStep(1);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bible-audio-enabled')));
    await tester.pump();
    expect(controller.audioEnabled, isFalse);
    expect(controller.isScrolling, isFalse);
    expect(saved.last.speechRate, 1.25);
    expect(saved.last.baseSpeed, 24);
    expect(saved.last.maximumStep, 3);
    expect(saved.last.announceChapter, isTrue);
    await tester.tap(find.byKey(const ValueKey('bible-audio-enabled')));
    await tester.pump();
    expect(controller.audioEnabled, isTrue);
    expect(controller.isScrolling, isFalse);
    expect(announcements, isEmpty);
    await tester.tap(find.byKey(const ValueKey('bible-audio-announce-book')));
    await tester.pump();
    expect(announcements, {BibleLoopUnit.book: true});
    expect(saved.length, 2);
    expect(controller.announceChapter, isTrue);
    expect(
      find.textContaining('do not change the recorded Bible voice'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll-only dialog preserves hidden audio choices when saved', (
    tester,
  ) async {
    MacAutoscrollPreferences? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open scroll'),
              onPressed: () async =>
                  result = await showMacAutoscrollSettingsDialog(
                    context: context,
                    showAudioSettings: false,
                    initial: const MacAutoscrollPreferences(
                      audioEnabled: true,
                      speechRate: 1.3,
                      announceChapter: true,
                      announceVerseNumbers: true,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scroll'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mac-autoscroll-audio-toggle')),
      findsNothing,
    );
    expect(find.text('Narration'), findsNothing);
    expect(
      find.byKey(const ValueKey('mac-autoscroll-base-speed')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('mac-autoscroll-save')));
    await tester.pumpAndSettle();
    expect(result!.audioEnabled, isTrue);
    expect(result!.speechRate, 1.3);
    expect(result!.announceChapter, isTrue);
    expect(result!.announceVerseNumbers, isTrue);
  });

  testWidgets('gear audio entry works on a small screen without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Gear'),
              onPressed: () => showViewerModePopup(
                context,
                themeMode: AppThemeMode.sepia,
                onThemeChanged: (_) {},
                onOpenBibleMemory: () {},
                onOpenAudioSettings: () => opened++,
                onOpenInterlinearSettings: () {},
                onOpenColorSetup: () {},
                onApplyDefaultMarkup: () {},
                presentationAspectRatio: PresentationAspectRatioPreset.auto,
                onPresentationAspectRatioChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Gear'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Bible Audio Settings'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byType(Dialog), findsNothing);
  });
}
