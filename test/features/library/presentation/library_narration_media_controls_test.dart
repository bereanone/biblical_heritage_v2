import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/narration_media_session.dart';
import 'package:studybible2/features/library/presentation/library_narration_media_controls.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';

import '../../../core/audio/fake_narration_media_platform.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';

class _Target implements ReaderAutoScrollTarget {
  @override
  bool get isAttached => true;

  @override
  bool scrollBy(double delta) => true;
}

void main() {
  late FakeNarrationMediaPlatform platform;
  late MacReaderAutoScrollController controller;
  late LibraryNarrationMediaControls media;
  var nexts = 0;
  var previouses = 0;

  setUp(() {
    platform = FakeNarrationMediaPlatform();
    nexts = 0;
    previouses = 0;
    controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      preferences: const MacAutoscrollPreferences(audioEnabled: true),
      narrationControlsPacing: true,
      driveFrames: false,
    );
    media = LibraryNarrationMediaControls(
      autoscroll: controller,
      title: 'Daniel and Revelation',
      author: 'Uriah Smith',
      next: () => nexts++,
      previous: () => previouses++,
      session: fakeSession(platform),
    );
  });

  tearDown(() {
    media.dispose();
    controller.dispose();
  });

  test('no lease is taken until narration actually starts', () {
    expect(platform.begins, 0);
    expect(media.keepsSpeakingInBackground, isFalse);
  });

  test('starting narration takes the lock screen and shows the book', () {
    controller.toggle();
    controller.setSignedStep(1);
    expect(platform.begins, 1);
    expect(platform.lastNowPlaying?['title'], 'Daniel and Revelation');
    expect(platform.lastNowPlaying?['subtitle'], 'Uriah Smith');
    expect(platform.lastNowPlaying?['playing'], true);
    // Leaving the screen must not stop narration that is speaking.
    expect(media.keepsSpeakingInBackground, isTrue);
  });

  test('pausing keeps the lease so the lock screen can resume, but is not '
      'kept alive in the background', () {
    controller.toggle();
    controller.setSignedStep(1);
    controller.stopForManualInteraction();
    expect(platform.ends, 0);
    expect(platform.lastNowPlaying?['playing'], false);
    expect(media.keepsSpeakingInBackground, isFalse);
  });

  test('turning narration off releases the lock screen', () {
    controller.toggle();
    controller.setSignedStep(1);
    controller.updatePreferences(const MacAutoscrollPreferences());
    expect(platform.ends, 1);
  });

  test('reader lifecycle handlers keep only speaking, supported narration '
      'alive in the background', () {
    final supported = fakeSession(platform);
    final unsupported = NarrationMediaSession(
      platform: platform,
      supported: false,
      observeLifecycle: false,
    );
    // Not narrating yet: the reader may stop it as usual.
    expect(
      librarySpeechSurvivesBackground(controller, session: supported),
      isFalse,
    );
    controller.toggle();
    controller.setSignedStep(1);
    expect(
      librarySpeechSurvivesBackground(controller, session: supported),
      isTrue,
    );
    // Off iOS nothing lets it continue, so the reader still stops it.
    expect(
      librarySpeechSurvivesBackground(controller, session: unsupported),
      isFalse,
    );
    controller.stopForManualInteraction();
    expect(
      librarySpeechSurvivesBackground(controller, session: supported),
      isFalse,
    );
  });
}
