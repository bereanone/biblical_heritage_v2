import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/data/presentation/note_image_layout.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_item_settings_repository.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_models.dart';
import 'package:studybible2/features/reader/data/presentation/presentation_slide_settings.dart';

void main() {
  late Database db;
  late PresentationItemSettingsRepository repo;
  PresentationSlide slide(String id) => PresentationSlide(
    id: id,
    settingsKey: id,
    slideNumber: 1,
    layoutType: PresentationLayoutType.fullWidth,
  );
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE presentation_item_settings (id INTEGER PRIMARY KEY, source_type TEXT, source_id TEXT, tag_id INTEGER, font_size_override REAL, alignment TEXT, layout TEXT, allow_scroll INTEGER, auto_fit INTEGER, updated_at TEXT, UNIQUE(source_type, source_id, tag_id))',
    );
    repo = PresentationItemSettingsRepository.forDatabase(db);
  });
  tearDown(() async => db.close());
  test('image position and margin survive saving and reset without changing text', () async {
    const image = NoteImageLayout(rows: 4, columns: 4, row: 1, column: 0, rowSpan: 2, columnSpan: 2, textGap: 42);
    await repo.saveSlideSettingsForTag(tagFamily: '#', tag: 'images', slide: slide('one'),
      settings: const PresentationSlideSettings(elementFontSizes: {'body': 30}, imageLayouts: {'image': image}));
    var loaded = await repo.loadSlideSettingsForTag(tagFamily: '#', tag: 'images');
    expect(loaded['one']!.imageLayouts['image']!.toJson(), image.toJson());
    expect(loaded['one']!.elementFontSizes['body'], 30);
    await repo.saveSlideSettingsForTag(tagFamily: '#', tag: 'images', slide: slide('one'),
      settings: loaded['one']!.copyWith(imageLayouts: {}));
    loaded = await repo.loadSlideSettingsForTag(tagFamily: '#', tag: 'images');
    expect(loaded['one']!.imageLayouts, isEmpty);
    expect(loaded['one']!.elementFontSizes['body'], 30);
    await repo.saveSlideSettingsForTag(tagFamily: '#', tag: 'images', slide: slide('one'),
      settings: const PresentationSlideSettings(imageLayouts: {'image': image}));
    await repo.deleteSettingsForTag(tagFamily: '#', tag: 'images');
    expect(await repo.loadSlideSettingsForTag(tagFamily: '#', tag: 'images'), isEmpty);
  });

  test(
    'element overrides round-trip, reset independently and stay scoped to tag and slide',
    () async {
      for (final tag in ['first', 'other']) {
        for (final id in ['linked', 'neighbor']) {
          await repo.saveSlideSettingsForTag(
            tagFamily: '#',
            tag: tag,
            slide: slide(id),
            settings: const PresentationSlideSettings(
              fontSizeOverride: 28,
              elementFontSizes: {'body': 32, 'reference': 16},
            ),
          );
        }
      }
      var loaded = await repo.loadSlideSettingsForTag(
        tagFamily: '#',
        tag: 'first',
      );
      expect(loaded['linked']!.elementFontSizes, {'body': 32, 'reference': 16});
      await repo.saveSlideSettingsForTag(
        tagFamily: '#',
        tag: 'first',
        slide: slide('linked'),
        settings: loaded['linked']!.copyWith(elementFontSizes: {'body': 35}),
      );
      loaded = await repo.loadSlideSettingsForTag(tagFamily: '#', tag: 'first');
      expect(loaded['linked']!.elementFontSizes, {'body': 35});
      expect(loaded['neighbor']!.elementFontSizes, {
        'body': 32,
        'reference': 16,
      });
      final other = await repo.loadSlideSettingsForTag(
        tagFamily: '#',
        tag: 'other',
      );
      expect(other['linked']!.elementFontSizes, {'body': 32, 'reference': 16});
      await repo.deleteSettingsForTag(tagFamily: '#', tag: 'first');
      expect(
        await repo.loadSlideSettingsForTag(tagFamily: '#', tag: 'first'),
        isEmpty,
      );
      expect(
        await repo.loadSlideSettingsForTag(tagFamily: '#', tag: 'other'),
        hasLength(2),
      );
    },
  );
  test(
    'failed element save rolls back the whole slide and preserves original settings',
    () async {
      await repo.saveSlideSettingsForTag(
        tagFamily: '#',
        tag: 'test',
        slide: slide('linked'),
        settings: const PresentationSlideSettings(
          fontSizeOverride: 28,
          elementFontSizes: {'body': 32},
        ),
      );
      await db.execute(
        "CREATE TRIGGER reject_element BEFORE INSERT ON presentation_item_settings WHEN NEW.source_type = 'tag_slide_element' BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        repo.saveSlideSettingsForTag(
          tagFamily: '#',
          tag: 'test',
          slide: slide('linked'),
          settings: const PresentationSlideSettings(
            fontSizeOverride: 40,
            elementFontSizes: {'body': 45},
          ),
        ),
        throwsA(anything),
      );
      final restored = (await repo.loadSlideSettingsForTag(
        tagFamily: '#',
        tag: 'test',
      ))['linked']!;
      expect(restored.fontSizeOverride, 28);
      expect(restored.elementFontSizes, {'body': 32});
    },
  );
  test('alignment-only edits and justify round-trip without requiring a size override', () async {
    await repo.saveSlideSettingsForTag(tagFamily: '#', tag: 'align', slide: slide('linked'),
      settings: const PresentationSlideSettings(elementAlignments: {
        'heading': PresentationAlignmentPreference.center,
        'reference': PresentationAlignmentPreference.right,
        'passage': PresentationAlignmentPreference.justify,
      }));
    var settings = (await repo.loadSlideSettingsForTag(tagFamily: '#', tag: 'align'))['linked']!;
    expect(settings.elementFontSizes, isEmpty);
    expect(settings.elementAlignments, {
      'heading': PresentationAlignmentPreference.center,
      'reference': PresentationAlignmentPreference.right,
      'passage': PresentationAlignmentPreference.justify,
    });
    await repo.saveSlideSettingsForTag(tagFamily: '#', tag: 'align', slide: slide('linked'),
      settings: settings.copyWith(elementAlignments: {'passage': PresentationAlignmentPreference.left}));
    settings = (await repo.loadSlideSettingsForTag(tagFamily: '#', tag: 'align'))['linked']!;
    expect(settings.elementAlignments, {'passage': PresentationAlignmentPreference.left});
  });

}
