// ignore_for_file: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';

/// Stands in for the audioplayers plugin, which has no native side under
/// `flutter test`. Screens that own a narrator create `AudioPlayer`s in
/// `initState`; without this the missing plugin fails the test.
void installFakeAudioplayers() {
  AudioplayersPlatformInterface.instance = _FakePlayerPlatform();
  GlobalAudioplayersPlatformInterface.instance = _FakeGlobalPlatform();
}

class _FakePlayerPlatform implements AudioplayersPlatformInterface {
  @override
  Stream<AudioEvent> getEventStream(String playerId) => const Stream.empty();

  @override
  Future<int?> getDuration(String playerId) async => null;

  @override
  Future<int?> getCurrentPosition(String playerId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakeGlobalPlatform implements GlobalAudioplayersPlatformInterface {
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
