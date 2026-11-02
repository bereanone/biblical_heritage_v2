import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:studybible2/features/library/data/library_catalog_service.dart';

void main() {
  late Directory root;
  const relative = 'Research/ManagedBundles/core/covers/daniel.png';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('managed-cover-');
    final cover = File(p.join(root.path, relative));
    await cover.parent.create(recursive: true);
    await cover.writeAsString('publisher artwork');
  });
  tearDown(() => root.delete(recursive: true));
  LibraryCatalogItem item(String cover) => LibraryCatalogItem.fromRow({
    'id': 'daniel',
    'title': 'The Story of Daniel the Prophet',
    'file_name': 'daniel.epub',
    'relative_path': 'daniel.epub',
    'cover_path': cover,
  }, rootPath: root.path);
  test('relative publisher cover resolves inside the current root', () {
    expect(item(relative).coverPath, p.join(root.path, relative));
  });
  test('publisher cover survives an iOS app container change', () {
    expect(
      item(
        '/var/mobile/Containers/Data/Application/OLD/Documents/BiblicalHeritage/v2/$relative',
      ).coverPath,
      p.join(root.path, relative),
    );
  });
  test('an existing explicit cover keeps priority', () async {
    final custom = File(p.join(root.path, 'custom.png'));
    await custom.writeAsString('chosen artwork');
    expect(item(custom.path).coverPath, custom.path);
  });
  test('Flutter asset covers keep their identity', () {
    expect(
      item('assets/library_covers/thumbs/DAR.png').coverPath,
      'assets/library_covers/thumbs/DAR.png',
    );
  });
  test('a relocated managed path cannot escape the library root', () async {
    final outside = File(
      p.join(root.parent.path, 'outside-cover-${p.basename(root.path)}.png'),
    );
    await outside.writeAsString('outside');
    try {
      expect(
        item(
          'Research/ManagedBundles/../../../${p.basename(outside.path)}',
        ).coverPath,
        isNull,
      );
    } finally {
      await outside.delete();
    }
  });
}
