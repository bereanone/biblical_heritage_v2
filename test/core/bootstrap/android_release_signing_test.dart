import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release signing requires explicit opt-in for the test key', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(
      gradle,
      isNot(contains('signingConfig = signingConfigs.getByName("debug")')),
    );
    expect(gradle, contains('if (testBedDebugSigning) "debug" else "release"'));
    expect(
      gradle,
      contains(
        'providers.gradleProperty("testBedDebugSigning").orNull == "true"',
      ),
    );
    expect(gradle, contains('rootProject.file("key.properties")'));
  });
}
