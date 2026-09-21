import 'package:studybible2/core/audio/narration_media_session.dart';

/// Records what the session asked the OS to do.
class FakeNarrationMediaPlatform implements NarrationMediaPlatform {
  int begins = 0;
  int ends = 0;
  int activations = 0;
  bool activationSucceeds = true;
  final List<Map<String, Object?>> nowPlaying = [];
  final List<bool> buffering = [];

  Map<String, Object?>? get lastNowPlaying =>
      nowPlaying.isEmpty ? null : nowPlaying.last;
  bool get isBuffering => buffering.isNotEmpty && buffering.last;

  @override
  void listen(void Function(String event, Object? argument) handler) {}
  @override
  Future<void> begin() async => begins++;
  @override
  Future<void> end() async => ends++;
  @override
  Future<void> updateNowPlaying(Map<String, Object?> info) async =>
      nowPlaying.add(info);
  @override
  Future<void> setBuffering(bool value) async => buffering.add(value);
  @override
  Future<bool> activate() async {
    activations++;
    return activationSucceeds;
  }
}

NarrationMediaSession fakeSession(FakeNarrationMediaPlatform platform) =>
    NarrationMediaSession(
      platform: platform,
      supported: true,
      observeLifecycle: false,
    );
