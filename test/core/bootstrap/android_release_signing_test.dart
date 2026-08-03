import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release builds never fall back to the debug signing key', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(
      gradle,
      isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
    );
    expect(
      gradle,
      contains('signingConfig = signingConfigs.getByName("release")'),
    );
    expect(gradle, contains('rootProject.file("key.properties")'));
  });
}
