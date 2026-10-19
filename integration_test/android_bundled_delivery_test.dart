import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/features/library/data/bundled_audio_setup.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android provisions core recordings from shared downloads', (tester) async {
    expect(Platform.isAndroid, isTrue);
    await tester.runAsync(() async {
      final db = await ELibraryDatabase.instance.database;
      final rows = await db.query('bundled_library_updates');
      expect(rows.length, 6);
      final setup = BundledAudioSetup.instance;
      setup.addListener(() { print('ANDROID_DELIVERY: ${setup.message} ${setup.progress}'); });
      await setup.ensure(sourceHashes: {});
      expect(setup.error, isNull);
      expect(setup.complete, isTrue);
      final manifest = jsonDecode(await rootBundle.loadString('assets/bundled_library/audio.json')) as Map;
      for (final raw in manifest['packages'] as List) {
        final spec = raw as Map;
        if (spec['requires_source_sha256'] != null) continue;
        final package = await RecordedLibraryAudioPackage.find(spec['title'] as String);
        expect(package, isNotNull, reason: 'Recording selection failed: ${spec['title']}');
        print('ANDROID_DELIVERY_SELECTED: ${spec['title']}');
      }
      final docs=await getApplicationDocumentsDirectory();
      final pointer=File('${docs.path}/elibrary_audio/bundled-current.json');
      expect(await pointer.exists(), isTrue);
      print('ANDROID_DELIVERY_PASS: six core packages selected; optional source excluded');
    });
  }, timeout: const Timeout(Duration(minutes: 30)));
}
