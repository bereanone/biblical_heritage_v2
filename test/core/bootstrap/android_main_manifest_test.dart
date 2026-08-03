import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android release manifest grants internet access for book downloads',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.INTERNET"/>',
        ),
      );
    },
  );

  test('Android main activity is a single exported launcher entry', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".MainActivity"'));
    expect(manifest, contains('android:exported="true"'));
    expect(
      '<action android:name="android.intent.action.MAIN"/>'.allMatches(
        manifest,
      ),
      hasLength(1),
    );
    expect(
      '<category android:name="android.intent.category.LAUNCHER"/>'.allMatches(
        manifest,
      ),
      hasLength(1),
    );
  });

  test('Android launcher uses the public label and complete icon resources', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:label="Biblical Heritage #StudyBible"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher"'));

    for (final density in const <String>[
      'mdpi',
      'hdpi',
      'xhdpi',
      'xxhdpi',
      'xxxhdpi',
    ]) {
      expect(
        File(
          'android/app/src/main/res/mipmap-$density/ic_launcher.png',
        ).existsSync(),
        isTrue,
        reason: 'Missing $density launcher icon',
      );
      expect(
        File(
          'android/app/src/main/res/drawable-$density/ic_launcher_foreground.png',
        ).existsSync(),
        isTrue,
        reason: 'Missing $density adaptive foreground',
      );
    }
    expect(
      File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).existsSync(),
      isTrue,
    );
  });
}
