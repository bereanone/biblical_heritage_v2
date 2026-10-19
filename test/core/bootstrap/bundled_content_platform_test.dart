import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/bootstrap/bundled_content_platform.dart';

void main() {
  test('mobile content setup supports iPhone and Android only', () {
    for (final platform in TargetPlatform.values) {
      expect(supportsBundledContent(platform),
          platform == TargetPlatform.iOS || platform == TargetPlatform.android,
          reason: platform.name);
    }
  });

  test('runtime uses the same policy as catalog and audio UI', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(bundledContentEnabled, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(bundledContentEnabled, isFalse);
  });
}
