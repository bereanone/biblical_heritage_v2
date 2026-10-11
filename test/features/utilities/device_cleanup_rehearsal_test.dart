import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/utilities/data/user_content_removal_service.dart';

void main() {
  sqfliteFfiInit();
  final original = Platform.environment['STUDYBIBLE_CLEANUP_DB'];
  test(
    'actual Android library copy can be emptied and compacted',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'device-cleanup-copy-',
      );
      final copy = await File(original!).copy(p.join(temp.path, 'eLibrary.db'));
      final db = await databaseFactoryFfi.openDatabase(copy.path);
      try {
        final bytes = await copy.length();
        final items = (await db.rawQuery(
          'SELECT count(*) AS n FROM library_items',
        )).single['n'];
        await UserContentRemovalService.clearDatabase(
          db,
          UserContentRemovalScope.library,
        );
        expect(
          (await db.rawQuery(
            'SELECT count(*) AS n FROM library_items',
          )).single['n'],
          items,
        );
        expect(
          (await db.rawQuery(
            'SELECT count(*) AS n FROM library_text_blocks',
          )).single['n'],
          0,
        );
        expect(await copy.length(), lessThan(bytes));
        await UserContentRemovalService.clearDatabase(
          db,
          UserContentRemovalScope.allUserData,
        );
        expect(
          (await db.rawQuery(
            'SELECT count(*) AS n FROM library_items',
          )).single['n'],
          0,
        );
        expect(
          (await db.rawQuery('PRAGMA quick_check')).single.values.single,
          'ok',
        );
        print(
          'Device copy database: $bytes -> ${await copy.length()} bytes; original untouched.',
        );
      } finally {
        await db.close();
        await temp.delete(recursive: true);
      }
    },
    skip: original == null
        ? 'Set STUDYBIBLE_CLEANUP_DB to an offline backup.'
        : false,
  );
}
