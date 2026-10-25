import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'new $platform readers have audio enabled before saving a setting',
      () {
        expect(resolveStoredReaderAudioEnabled(null, platform), isTrue);
      },
    );
  }
  test(
    'saved Audio Off survives updates and repeated loads on every platform',
    () {
      for (final platform in TargetPlatform.values) {
        for (var load = 0; load < 3; load++) {
          expect(resolveStoredReaderAudioEnabled('false', platform), isFalse);
        }
      }
    },
  );
  test('saved Audio On remains enabled on every platform', () {
    for (final platform in TargetPlatform.values) {
      expect(resolveStoredReaderAudioEnabled('true', platform), isTrue);
    }
  });
  test('other platforms retain their current fresh-install default', () {
    for (final platform in TargetPlatform.values.where(
      (p) => p != TargetPlatform.android && p != TargetPlatform.iOS,
    )) {
      expect(resolveStoredReaderAudioEnabled(null, platform), isFalse);
    }
  });
  test('an invalid saved value does not enable narration', () {
    for (final platform in TargetPlatform.values) {
      for (final value in ['', 'invalid', 'TRUE']) {
        expect(resolveStoredReaderAudioEnabled(value, platform), isFalse);
      }
    }
  });
}
