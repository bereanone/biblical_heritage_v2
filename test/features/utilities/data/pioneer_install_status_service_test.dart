import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/bootstrap/sandbox_bootstrap.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/pioneer_install_status_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';

Future<void> _installPathProviderMocks({
  required Directory supportDir,
  required Directory documentsDir,
}) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getApplicationSupportDirectory':
            return supportDir.path;
          case 'getApplicationDocumentsDirectory':
            return documentsDir.path;
          case 'getTemporaryDirectory':
            return supportDir.path;
          case 'getLibraryDirectory':
            return supportDir.path;
        }
        return supportDir.path;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'pioneer_status_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'pioneer_status_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'pioneer_status_root_',
    );
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    await LocalSettingsStore.instance.ensureDeviceId();
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await ELibraryDatabase.instance.close();
    if (supportDir.existsSync()) {
      await supportDir.delete(recursive: true);
    }
    if (documentsDir.existsSync()) {
      await documentsDir.delete(recursive: true);
    }
    if (libraryRootDir.existsSync()) {
      await libraryRootDir.delete(recursive: true);
    }
  });

  test('uses text-capture-first status labels', () {
    const catalogOnly = PioneerWorkInstallStatus(
      workId: 'catalog_only',
      hasLibraryRow: false,
      qualityState: PioneerInstalledQualityState.notInstalled,
      installedSourceSummary: null,
      installedSourceType: null,
      installedSourceSite: null,
      installedSourceUrl: null,
      textBlockCount: 0,
      navigationRowCount: 0,
      navigationRowsWithTextCount: 0,
      refRowCount: 0,
    );
    const installedText = PioneerWorkInstallStatus(
      workId: 'installed_text',
      hasLibraryRow: true,
      qualityState: PioneerInstalledQualityState.verified,
      installedSourceSummary: 'EGW copied range',
      installedSourceType: 'egw_copied_range',
      installedSourceSite: 'EGW Writings copied range',
      installedSourceUrl: null,
      textBlockCount: 42,
      navigationRowCount: 5,
      navigationRowsWithTextCount: 5,
      refRowCount: 42,
    );
    const oldBrokenEpub = PioneerWorkInstallStatus(
      workId: 'old_broken_epub',
      hasLibraryRow: true,
      qualityState: PioneerInstalledQualityState.badImport,
      installedSourceSummary: 'APLIB EPUB',
      installedSourceType: 'epub',
      installedSourceSite: 'APLIB',
      installedSourceUrl: null,
      textBlockCount: 0,
      navigationRowCount: 0,
      navigationRowsWithTextCount: 0,
      refRowCount: 0,
    );

    expect(catalogOnly.statusLabel, 'Available');
    expect(installedText.statusLabel, 'Installed — text');
    expect(oldBrokenEpub.statusLabel, 'Legacy import needs review');
  });

  test(
    'reports installed works and warns when a lower-quality source is selected',
    () async {
      final installedWork = PioneerSourceWork(
        id: 'daniel_and_the_revelation',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        sourceFamily: 'APLIB',
        title: 'Daniel and the Revelation',
        abbreviation: 'DAR',
        group: 'Pioneer Authors',
        subgroup: 'Prophecy',
        availability: PioneerSourceAvailability.available,
        verified: true,
        catalogImportable: true,
        sourceType: 'epub',
        sourceUrl: 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
        captureUrl: null,
        readerUrl: null,
        directFileUrl: null,
        directFileType: null,
        sourceLabel: 'APLIB',
        notes: null,
      );

      final lowerQualityWork = PioneerSourceWork(
        id: 'the_united_states_in_the_light_of_prophecy',
        authorId: 'uriah_smith',
        authorName: 'Uriah Smith',
        sourceFamily: 'Pioneer',
        title: 'The United States in the Light of Prophecy',
        abbreviation: 'USLP',
        group: 'Pioneer Authors',
        subgroup: 'Prophecy',
        availability: PioneerSourceAvailability.available,
        verified: true,
        catalogImportable: true,
        sourceType: 'html',
        sourceUrl: 'https://www.gutenberg.org/files/12364/12364-h/12364-h.htm',
        collectionUrl: null,
        captureUrl: null,
        readerUrl: null,
        directFileUrl: null,
        directFileType: null,
        sourceLabel: 'Project Gutenberg',
        notes: null,
        sourceCandidates: const [
          PioneerSourceCandidate(
            provider: 'gutenberg',
            sourceType: 'html',
            url: 'https://www.gutenberg.org/files/12364/12364-h/12364-h.htm',
            priority: 40,
            qualityTier: 'html',
            availability: PioneerSourceAvailability.available,
          ),
        ],
      );

      final db = await ELibraryDatabase.instance.database;
      final installedStableId =
          'library_item_research_pioneer_${installedWork.authorId}_${installedWork.id}';
      await db.insert('library_items', <String, Object?>{
        'id': installedStableId,
        'title': installedWork.title,
        'author': installedWork.authorName,
        'file_name': 'DAR.epub',
        'relative_path': 'ePubs/Research/Pioneer Authors/uriah_smith/DAR.epub',
        'file_hash': 'hash',
        'file_size': 1234,
        'mime_type': 'application/epub+zip',
        'file_format': 'epub',
        'folder_type': 'research',
        'library_role': 'research',
        'collection_name': 'Pioneer Authors',
        'source_site': 'adventaudio.org',
        'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        'source_type': 'official_download',
        'date_added': '2026-06-20T00:00:00Z',
        'created_at': '2026-06-20T00:00:00Z',
        'updated_at': '2026-06-20T00:00:00Z',
        'device_id': 'device-1',
        'index_status': 'indexed',
        'is_missing': 0,
        'revision': 1,
        'sync_status': 'pending',
      });
      await db.insert('library_text_blocks', <String, Object?>{
        'library_item_id': installedStableId,
        'epub_href': 'chapter_1.xhtml',
        'spine_index': 1,
        'paragraph_index': 1,
        'paragraph_on_section': 1,
        'section_title': 'Chapter 1',
        'plain_text':
            'This is the real body text for Daniel and the Revelation.',
        'created_at': '2026-06-20T00:00:00Z',
        'updated_at': '2026-06-20T00:00:00Z',
      });
      await db.insert('library_navigation_items', <String, Object?>{
        'id': '$installedStableId-nav-0',
        'library_item_id': installedStableId,
        'parent_id': null,
        'label': 'Chapter 1',
        'href': 'chapter_1.xhtml',
        'anchor_id': null,
        'spine_index': 1,
        'sort_order': 1,
        'depth': 0,
        'nav_type': 'toc',
        'content_kind': 'chapter',
        'is_front_matter': 0,
        'is_body_start': 1,
        'body_order': 1,
        'created_at': '2026-06-20T00:00:00Z',
        'updated_at': '2026-06-20T00:00:00Z',
        'device_id': 'device-1',
        'revision': 1,
        'sync_status': 'pending',
      });

      final status = await PioneerInstallStatusService.instance.inspectCatalog(
        PioneerSourceCatalog.fromJson({
          'authors': [
            {
              'author_id': 'uriah_smith',
              'author_name': 'Uriah Smith',
              'source_family': 'Pioneer',
              'works': [
                {
                  'work_id': installedWork.id,
                  'title': installedWork.title,
                  'abbreviation': installedWork.abbreviation,
                  'group': installedWork.group,
                  'subgroup': installedWork.subgroup,
                  'availability_status': 'available',
                  'source_type': 'epub',
                  'source_family': 'APLIB',
                  'source_url':
                      'https://adventaudio.org/files/ebooks/zip/Epub.zip',
                  'source_label': 'APLIB',
                  'verified': true,
                  'importable': true,
                  'source_candidates': [
                    {
                      'provider': 'aplib',
                      'source_type': 'epub',
                      'url':
                          'https://adventaudio.org/files/ebooks/zip/Epub.zip',
                      'priority': 10,
                      'quality_tier': 'epub',
                      'availability': 'available',
                    },
                  ],
                },
                {
                  'work_id': lowerQualityWork.id,
                  'title': lowerQualityWork.title,
                  'abbreviation': lowerQualityWork.abbreviation,
                  'group': lowerQualityWork.group,
                  'subgroup': lowerQualityWork.subgroup,
                  'availability_status': 'available',
                  'source_type': 'html',
                  'source_family': 'Pioneer',
                  'source_url':
                      'https://www.gutenberg.org/files/12364/12364-h/12364-h.htm',
                  'source_label': 'Project Gutenberg',
                  'verified': true,
                  'importable': true,
                  'source_candidates': [
                    {
                      'provider': 'gutenberg',
                      'source_type': 'html',
                      'url':
                          'https://www.gutenberg.org/files/12364/12364-h/12364-h.htm',
                      'priority': 40,
                      'quality_tier': 'html',
                      'availability': 'available',
                    },
                  ],
                },
              ],
            },
          ],
        }),
      );

      final installedStatus = status[installedWork.id];
      expect(installedStatus, isNotNull);
      expect(installedStatus!.statusLabel, 'Installed — verified');
      expect(installedStatus.isVerifiedInstalled, isTrue);
      expect(installedStatus.replacementWarningFor(installedWork), isNull);

      final lowerStatus = status[lowerQualityWork.id];
      expect(lowerStatus, isNotNull);
      expect(lowerStatus!.statusLabel, 'Available');
      expect(lowerStatus.isVerifiedInstalled, isFalse);
      expect(
        installedStatus.replacementWarningFor(lowerQualityWork),
        'An existing higher-quality import is already installed. This source will not replace it unless you explicitly choose Repair/Reimport.',
      );
    },
  );

  test(
    'classifies empty, wrapper-only, navigation-broken, and verified Pioneer rows',
    () async {
      final db = await ELibraryDatabase.instance.database;
      const now = '2026-06-21T00:00:00Z';
      final baseFields = <String, Object?>{
        'file_name': 'test.html',
        'relative_path': 'ePubs/Research/Pioneer Authors/uriah_smith/test.html',
        'file_hash': 'hash',
        'file_size': 1234,
        'mime_type': 'text/html',
        'file_format': 'html',
        'folder_type': 'research',
        'library_role': 'research',
        'collection_name': 'Pioneer Authors',
        'source_site': 'adventaudio.org',
        'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
        'source_type': 'epub',
        'created_at': now,
        'updated_at': now,
        'device_id': 'device-1',
        'index_status': 'indexed',
        'is_missing': 0,
        'revision': 1,
        'sync_status': 'pending',
      };

      Future<void> insertWork({
        required String id,
        required String title,
        required String author,
        required List<String> textBlocks,
        required List<Map<String, Object?>> navigationRows,
      }) async {
        await db.insert('library_items', {
          ...baseFields,
          'id': id,
          'title': title,
          'author': author,
          'file_name': '$id.html',
        });
        for (var i = 0; i < textBlocks.length; i += 1) {
          await db.insert('library_text_blocks', {
            'library_item_id': id,
            'epub_href': 'chapter_${i + 1}.xhtml',
            'spine_index': i + 1,
            'paragraph_index': 1,
            'paragraph_on_section': 1,
            'section_title': 'Section ${i + 1}',
            'plain_text': textBlocks[i],
            'created_at': now,
            'updated_at': now,
          });
        }
        for (var i = 0; i < navigationRows.length; i += 1) {
          await db.insert('library_navigation_items', {
            'id': '$id-nav-$i',
            'library_item_id': id,
            'parent_id': null,
            'label': navigationRows[i]['label'],
            'href': navigationRows[i]['href'],
            'anchor_id': null,
            'spine_index': i + 1,
            'sort_order': i + 1,
            'depth': 0,
            'nav_type': 'toc',
            'content_kind': 'chapter',
            'is_front_matter': navigationRows[i]['is_front_matter'] ?? 0,
            'is_body_start': navigationRows[i]['is_body_start'] ?? 0,
            'body_order': i + 1,
            'created_at': now,
            'updated_at': now,
            'device_id': 'device-1',
            'revision': 1,
            'sync_status': 'pending',
          });
        }
      }

      await insertWork(
        id: 'library_item_research_pioneer_uriah_smith_empty_work',
        title: 'Empty Work',
        author: 'Uriah Smith',
        textBlocks: const [],
        navigationRows: const [],
      );
      await insertWork(
        id: 'library_item_research_pioneer_uriah_smith_wrapper_only_work',
        title: 'Wrapper Only',
        author: 'Uriah Smith',
        textBlocks: const [
          '© 2016 Adventist Pioneer Library',
          'Originally published in 1896',
        ],
        navigationRows: const [
          {
            'label': 'Title Page',
            'href': 'chapter_1.xhtml',
            'is_body_start': 0,
          },
        ],
      );
      await insertWork(
        id: 'library_item_research_pioneer_uriah_smith_navigation_broken_work',
        title: 'Navigation Broken',
        author: 'Uriah Smith',
        textBlocks: const ['A real body paragraph that is not front matter.'],
        navigationRows: const [
          {'label': 'Chapter 1', 'href': 'missing.xhtml', 'is_body_start': 1},
        ],
      );
      await insertWork(
        id: 'library_item_research_pioneer_uriah_smith_verified_work',
        title: 'Verified Work',
        author: 'Uriah Smith',
        textBlocks: const [
          'Preface',
          'This is the real body text for the verified work.',
        ],
        navigationRows: const [
          {'label': 'Preface', 'href': 'chapter_1.xhtml', 'is_body_start': 1},
        ],
      );

      final catalog = PioneerSourceCatalog.fromJson({
        'authors': [
          {
            'author_id': 'uriah_smith',
            'author_name': 'Uriah Smith',
            'source_family': 'Pioneer',
            'works': [
              {
                'work_id': 'empty_work',
                'title': 'Empty Work',
                'abbreviation': 'EW',
                'group': 'Pioneer Authors',
                'subgroup': 'Prophecy',
                'availability_status': 'available',
                'source_type': 'epub',
                'source_family': 'APLIB',
                'source_url':
                    'https://adventaudio.org/files/ebooks/zip/Epub.zip',
                'source_label': 'APLIB',
                'verified': true,
                'importable': true,
              },
              {
                'work_id': 'wrapper_only_work',
                'title': 'Wrapper Only',
                'abbreviation': 'WOW',
                'group': 'Pioneer Authors',
                'subgroup': 'Prophecy',
                'availability_status': 'available',
                'source_type': 'epub',
                'source_family': 'APLIB',
                'source_url':
                    'https://adventaudio.org/files/ebooks/zip/Epub.zip',
                'source_label': 'APLIB',
                'verified': true,
                'importable': true,
              },
              {
                'work_id': 'navigation_broken_work',
                'title': 'Navigation Broken',
                'abbreviation': 'NB',
                'group': 'Pioneer Authors',
                'subgroup': 'Prophecy',
                'availability_status': 'available',
                'source_type': 'epub',
                'source_family': 'APLIB',
                'source_url':
                    'https://adventaudio.org/files/ebooks/zip/Epub.zip',
                'source_label': 'APLIB',
                'verified': true,
                'importable': true,
              },
              {
                'work_id': 'verified_work',
                'title': 'Verified Work',
                'abbreviation': 'VW',
                'group': 'Pioneer Authors',
                'subgroup': 'Prophecy',
                'availability_status': 'available',
                'source_type': 'epub',
                'source_family': 'APLIB',
                'source_url':
                    'https://adventaudio.org/files/ebooks/zip/Epub.zip',
                'source_label': 'APLIB',
                'verified': true,
                'importable': true,
              },
            ],
          },
        ],
      });

      final statuses = await PioneerInstallStatusService.instance
          .inspectCatalog(catalog);

      expect(statuses['empty_work']!.statusLabel, 'Legacy import needs review');
      expect(
        statuses['wrapper_only_work']!.statusLabel,
        'Legacy import needs review',
      );
      expect(
        statuses['navigation_broken_work']!.statusLabel,
        'Legacy import needs review',
      );
      expect(statuses['verified_work']!.statusLabel, 'Installed — verified');
      expect(statuses['verified_work']!.isVerifiedInstalled, isTrue);
    },
  );

  test('downgrades when chapter contents target lands mid-section', () async {
    final db = await ELibraryDatabase.instance.database;
    final now = '2026-06-21T00:00:00Z';
    const workId = 'toc_mismatch';
    const stableId = 'library_item_research_pioneer_uriah_smith_toc_mismatch';
    await db.insert('library_items', <String, Object?>{
      'id': stableId,
      'title': 'Chapter Target Mismatch',
      'author': 'Uriah Smith',
      'file_name': 'toc_mismatch.html',
      'relative_path':
          'ePubs/Research/Pioneer Authors/uriah_smith/toc_mismatch.html',
      'file_hash': 'hash',
      'file_size': 1234,
      'mime_type': 'text/html',
      'file_format': 'html',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'Pioneer Authors',
      'source_site': 'adventaudio.org',
      'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
      'source_type': 'epub',
      'date_added': now,
      'created_at': now,
      'updated_at': now,
      'device_id': 'device-1',
      'index_status': 'indexed',
      'is_missing': 0,
      'revision': 1,
      'sync_status': 'pending',
    });
    await db.insert('library_text_blocks', <String, Object?>{
      'library_item_id': stableId,
      'epub_href': 'OPS/chapter-5.xhtml',
      'spine_index': 5,
      'paragraph_index': 1,
      'paragraph_on_section': 1,
      'section_title': 'CHAPTER I',
      'plain_text': 'Although Daniel lived twenty-five hundred years ago.',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('library_navigation_items', <String, Object?>{
      'id': '$stableId-nav-0',
      'library_item_id': stableId,
      'parent_id': null,
      'label': 'CHAPTER I',
      'href': 'OPS/chapter-5.xhtml',
      'anchor_id': null,
      'spine_index': 5,
      'sort_order': 5,
      'depth': 0,
      'nav_type': 'toc',
      'content_kind': 'chapter',
      'is_front_matter': 0,
      'is_body_start': 0,
      'body_order': 5,
      'created_at': now,
      'updated_at': now,
      'device_id': 'device-1',
      'revision': 1,
      'sync_status': 'pending',
    });

    final catalog = PioneerSourceCatalog.fromJson({
      'authors': [
        {
          'author_id': 'uriah_smith',
          'author_name': 'Uriah Smith',
          'source_family': 'Pioneer',
          'works': [
            {
              'work_id': workId,
              'title': 'Chapter Target Mismatch',
              'abbreviation': 'CTM',
              'group': 'Pioneer Authors',
              'subgroup': 'Prophecy',
              'availability_status': 'available',
              'source_type': 'epub',
              'source_family': 'APLIB',
              'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
              'source_label': 'APLIB',
              'verified': true,
              'importable': true,
            },
          ],
        },
      ],
    });

    final statuses = await PioneerInstallStatusService.instance.inspectCatalog(
      catalog,
    );

    expect(statuses[workId]!.statusLabel, 'Legacy import needs review');
    expect(statuses[workId]!.isVerifiedInstalled, isFalse);
  });

  test('downgrades when visible Margin artifacts are present', () async {
    final db = await ELibraryDatabase.instance.database;
    final now = '2026-06-21T00:00:00Z';
    const workId = 'margin_artifact';
    const stableId =
        'library_item_research_pioneer_uriah_smith_margin_artifact';
    await db.insert('library_items', <String, Object?>{
      'id': stableId,
      'title': 'Margin Artifact',
      'author': 'Uriah Smith',
      'file_name': 'margin_artifact.html',
      'relative_path':
          'ePubs/Research/Pioneer Authors/uriah_smith/margin_artifact.html',
      'file_hash': 'hash',
      'file_size': 1234,
      'mime_type': 'text/html',
      'file_format': 'html',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'Pioneer Authors',
      'source_site': 'adventaudio.org',
      'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
      'source_type': 'epub',
      'date_added': now,
      'created_at': now,
      'updated_at': now,
      'device_id': 'device-1',
      'index_status': 'indexed',
      'is_missing': 0,
      'revision': 1,
      'sync_status': 'pending',
    });
    await db.insert('library_text_blocks', <String, Object?>{
      'library_item_id': stableId,
      'epub_href': 'OPS/chapter-5.xhtml',
      'spine_index': 5,
      'paragraph_index': 1,
      'paragraph_on_section': 1,
      'section_title': 'CHAPTER I',
      'plain_text': 'Israel was to send beams of 2 Margin light to the world.',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('library_navigation_items', <String, Object?>{
      'id': '$stableId-nav-0',
      'library_item_id': stableId,
      'parent_id': null,
      'label': 'CHAPTER I',
      'href': 'OPS/chapter-5.xhtml',
      'anchor_id': null,
      'spine_index': 5,
      'sort_order': 5,
      'depth': 0,
      'nav_type': 'toc',
      'content_kind': 'chapter',
      'is_front_matter': 0,
      'is_body_start': 1,
      'body_order': 1,
      'created_at': now,
      'updated_at': now,
      'device_id': 'device-1',
      'revision': 1,
      'sync_status': 'pending',
    });

    final catalog = PioneerSourceCatalog.fromJson({
      'authors': [
        {
          'author_id': 'uriah_smith',
          'author_name': 'Uriah Smith',
          'source_family': 'Pioneer',
          'works': [
            {
              'work_id': workId,
              'title': 'Margin Artifact',
              'abbreviation': 'MA',
              'group': 'Pioneer Authors',
              'subgroup': 'Prophecy',
              'availability_status': 'available',
              'source_type': 'epub',
              'source_family': 'APLIB',
              'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
              'source_label': 'APLIB',
              'verified': true,
              'importable': true,
            },
          ],
        },
      ],
    });

    final statuses = await PioneerInstallStatusService.instance.inspectCatalog(
      catalog,
    );

    expect(statuses[workId]!.statusLabel, 'Legacy import needs review');
    expect(statuses[workId]!.isVerifiedInstalled, isFalse);
  });

  test('does not write to user.db while inspecting install status', () async {
    await UserDatabase.instance.database;
    final userDbPath = await SandboxBootstrap.userDatabasePath();
    final userDbFile = File(userDbPath);
    final beforeStat = await userDbFile.stat();

    final catalog = PioneerSourceCatalog.fromJson({
      'authors': [
        {
          'author_id': 'uriah_smith',
          'author_name': 'Uriah Smith',
          'source_family': 'Pioneer',
          'works': [
            {
              'work_id': 'user_db_safety',
              'title': 'User DB Safety',
              'abbreviation': 'UDS',
              'group': 'Pioneer Authors',
              'subgroup': 'Prophecy',
              'availability_status': 'available',
              'source_type': 'epub',
              'source_family': 'APLIB',
              'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
              'source_label': 'APLIB',
              'verified': true,
              'importable': true,
            },
          ],
        },
      ],
    });

    await PioneerInstallStatusService.instance.inspectCatalog(catalog);

    final afterStat = await userDbFile.stat();
    expect(beforeStat.size, afterStat.size);
    expect(beforeStat.modified, afterStat.modified);
  });

  test('flags duplicate Pioneer rows as needs review', () async {
    final db = await ELibraryDatabase.instance.database;
    const now = '2026-06-21T00:00:00Z';
    final baseFields = <String, Object?>{
      'file_name': 'duplicate.html',
      'relative_path':
          'ePubs/Research/Pioneer Authors/uriah_smith/duplicate.html',
      'file_hash': 'hash',
      'file_size': 1234,
      'mime_type': 'text/html',
      'file_format': 'html',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'Pioneer Authors',
      'source_site': 'adventaudio.org',
      'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
      'source_type': 'epub',
      'created_at': now,
      'updated_at': now,
      'device_id': 'device-1',
      'index_status': 'indexed',
      'is_missing': 0,
      'revision': 1,
      'sync_status': 'pending',
    };

    Future<void> insertDuplicate({
      required String id,
      required String title,
    }) async {
      await db.insert('library_items', {
        ...baseFields,
        'id': id,
        'title': title,
        'author': 'Uriah Smith',
        'file_name': '$id.html',
      });
      await db.insert('library_text_blocks', {
        'library_item_id': id,
        'epub_href': 'chapter_1.xhtml',
        'spine_index': 1,
        'paragraph_index': 1,
        'paragraph_on_section': 1,
        'section_title': 'Chapter 1',
        'plain_text': 'This is the real body text for $title.',
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('library_navigation_items', {
        'id': '$id-nav-0',
        'library_item_id': id,
        'parent_id': null,
        'label': 'Chapter 1',
        'href': 'chapter_1.xhtml',
        'anchor_id': null,
        'spine_index': 1,
        'sort_order': 1,
        'depth': 0,
        'nav_type': 'toc',
        'content_kind': 'chapter',
        'is_front_matter': 0,
        'is_body_start': 1,
        'body_order': 1,
        'created_at': now,
        'updated_at': now,
        'device_id': 'device-1',
        'revision': 1,
        'sync_status': 'pending',
      });
    }

    await insertDuplicate(
      id: 'library_item_research_pioneer_uriah_smith_duplicate_one',
      title: 'Duplicate Pioneer Work',
    );
    await insertDuplicate(
      id: 'library_item_research_pioneer_uriah_smith_duplicate_two',
      title: 'Duplicate Pioneer Work',
    );

    final catalog = PioneerSourceCatalog.fromJson({
      'authors': [
        {
          'author_id': 'uriah_smith',
          'author_name': 'Uriah Smith',
          'source_family': 'Pioneer',
          'works': [
            {
              'work_id': 'duplicate_one',
              'title': 'Duplicate Pioneer Work',
              'abbreviation': 'DPW1',
              'group': 'Pioneer Authors',
              'subgroup': 'Prophecy',
              'availability_status': 'available',
              'source_type': 'epub',
              'source_family': 'APLIB',
              'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
              'source_label': 'APLIB',
              'verified': true,
              'importable': true,
            },
            {
              'work_id': 'duplicate_two',
              'title': 'Duplicate Pioneer Work',
              'abbreviation': 'DPW2',
              'group': 'Pioneer Authors',
              'subgroup': 'Prophecy',
              'availability_status': 'available',
              'source_type': 'epub',
              'source_family': 'APLIB',
              'source_url': 'https://adventaudio.org/files/ebooks/zip/Epub.zip',
              'source_label': 'APLIB',
              'verified': true,
              'importable': true,
            },
          ],
        },
      ],
    });

    final statuses = await PioneerInstallStatusService.instance.inspectCatalog(
      catalog,
    );

    expect(
      statuses['duplicate_one']!.statusLabel,
      'Legacy import needs review',
    );
    expect(
      statuses['duplicate_two']!.statusLabel,
      'Legacy import needs review',
    );
    expect(statuses['duplicate_one']!.isVerifiedInstalled, isFalse);
    expect(statuses['duplicate_two']!.isVerifiedInstalled, isFalse);
  });
}
