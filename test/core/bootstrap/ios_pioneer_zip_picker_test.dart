import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS Pioneer ZIP picker accepts provider ZIP type variants', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate, contains('kind == "pioneerZip"'));
    expect(appDelegate, contains('[.zip, .archive, .data, .item]'));
    expect(appDelegate, contains('UTType(filenameExtension: "zip")'));
    expect(appDelegate, contains('"public.zip-archive"'));
    expect(appDelegate, contains('asCopy: true'));
    expect(appDelegate, contains('case importZipCopy'));
    expect(appDelegate, contains('hasSuffix(".zip")'));
    expect(
      appDelegate,
      contains('kind != "pioneerZip" && kind != "collection"'),
    );
  });
}
