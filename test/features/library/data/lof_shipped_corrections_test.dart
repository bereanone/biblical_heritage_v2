import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/lessons_reading_edition.dart';

void main() {
  test('shipped LOF selects the complete correction instead of old or October-only audio', () async {
    final index = jsonDecode(await File('assets/bundled_library/audio.json').readAsString()) as Map;
    final spec = (index['packages'] as List).cast<Map>().singleWhere((p) => p['id'] == 'lof');
    expect(spec['requires_source_sha256'], LessonsReadingEdition.sourceHash);
    expect(spec['sha256'], isNot('0af5dc8231546e908d873b17ec2110c1a9525a261d9ba988e6fc583a062b02d6'));
    expect(spec['sha256'], isNot('3327b452a7abc64777b6e1e239965eaa8e00bd82ab9c4a12afab828fc10ea6b9'));
    final members = (spec['files'] as List).cast<Map>();
    for (final member in members) {
      final bytes = await File(member['asset'] as String).readAsBytes();
      expect(bytes.length, member['bytes'], reason: member['name'] as String);
      expect(sha256.convert(bytes).toString(), member['sha256'], reason: member['name'] as String);
    }
    final descriptor = members.singleWhere((m) => m['name'] == 'audio-manifest.json');
    final manifest = jsonDecode(await File(descriptor['asset'] as String).readAsString()) as Map;
    expect(manifest['publisher_corrections'], contains('lof-all-dates-references-delivery-v4'));
    expect(manifest['timeline_migration']['to'], manifest['timeline_version']);
    final tracks = (manifest['tracks'] as List).cast<Map>();
    expect(tracks.expand((t) => t['cues'] as List).length, 699);
    expect(tracks[2]['sha256'], isNot('d1a3da7253a421200c1bdd38b21d09fe4a921c4bdbd32dc3a43ce506d6ca57fb'));
    expect(tracks.expand((t) => t['cues'] as List).cast<Map>().singleWhere((c) => c['source_cursor'] == '70')['text'],
      'Advent Review and Sabbath Herald, Nov. 29, 1898');
  });
}
