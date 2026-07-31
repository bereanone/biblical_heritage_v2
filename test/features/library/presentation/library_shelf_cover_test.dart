import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/library_screen.dart';

LibraryCatalogItem _item({
  required String id,
  required String title,
  required String author,
  String? coverPath,
}) {
  return LibraryCatalogItem.fromRow(<String, Object?>{
    'id': id,
    'title': title,
    'author': author,
    'file_name': '$id.epub',
    'relative_path': 'Pioneer/$id.epub',
    'cover_path': coverPath,
    'navigation_count': 1,
  });
}

Widget _coverHarness(LibraryCatalogItem item) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 140,
          height: 180,
          child: buildLibraryShelfCoverForTesting(item: item),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'missing-cover shelf card normalizes title and keeps author at bottom',
    (tester) async {
      final item = _item(
        id: 'adventist_world',
        title: '&quot;Adventist World&quot;',
        author: 'Pioneer Author',
      );

      await tester.pumpWidget(_coverHarness(item));

      expect(
        find.byKey(
          const ValueKey('library-metadata-fallback-cover-adventist_world'),
        ),
        findsOneWidget,
      );
      expect(find.text('Adventist World'), findsOneWidget);
      expect(find.textContaining('&quot;'), findsNothing);
      expect(find.text('Pioneer Author'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('library-fallback-cover-author')),
        findsOneWidget,
      );
      expect(find.text('AW'), findsNothing);
      expect(find.text('AY'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('real shelf cover artwork takes precedence', (tester) async {
    final item = _item(
      id: 'artwork_book',
      title: 'A Full Catalog Title',
      author: 'Catalog Author',
      coverPath: 'assets/icons/GoldLogo.png',
    );

    await tester.pumpWidget(_coverHarness(item));

    expect(
      find.byKey(const ValueKey('library-artwork-cover-artwork_book')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('library-metadata-fallback-cover-artwork_book'),
      ),
      findsNothing,
    );
    expect(find.text('A Full Catalog Title'), findsNothing);
    expect(find.text('Catalog Author'), findsNothing);
  });

  testWidgets('long missing-cover title remains bounded inside the cover', (
    tester,
  ) async {
    final item = _item(
      id: 'long_title',
      title: '&quot;Due Process of Law&quot; and The Divine Right of Dissent',
      author: 'A. T. Jones',
    );

    await tester.pumpWidget(_coverHarness(item));

    expect(
      find.text('"Due Process of Law" and The Divine Right of Dissent'),
      findsOneWidget,
    );
    final title = tester.widget<Text>(
      find.text('"Due Process of Law" and The Divine Right of Dissent'),
    );
    expect(title.maxLines, 6);
    expect(title.overflow, TextOverflow.clip);
    expect(tester.takeException(), isNull);
  });
}
