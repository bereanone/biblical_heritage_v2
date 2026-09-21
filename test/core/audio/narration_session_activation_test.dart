import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/narration_media_session.dart';

import 'fake_narration_media_platform.dart';

void main() {
  test('asks the platform to re-assert the audio session', () async {
    final platform = FakeNarrationMediaPlatform();
    final session = fakeSession(platform);

    expect(await session.activateAudioSession('speak'), isTrue);
    expect(await session.activateAudioSession('before-play'), isTrue);

    expect(platform.activations, 2);
  });

  test('reports a refusal instead of hiding it', () async {
    final platform = FakeNarrationMediaPlatform()..activationSucceeds = false;
    final session = fakeSession(platform);

    expect(await session.activateAudioSession('speak'), isFalse);
  });

  test('is a no-op where there is no native session', () async {
    final platform = FakeNarrationMediaPlatform();
    final session = NarrationMediaSession(
      platform: platform,
      supported: false,
      observeLifecycle: false,
    );

    expect(await session.activateAudioSession('speak'), isTrue);
    expect(platform.activations, 0);
  });
}
