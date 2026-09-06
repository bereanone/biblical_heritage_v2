import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'elibrary_legacy_item_id_migration.dart';
import 'elibrary_sdp_cleanup.dart';

class ELibrarySchema {
  ELibrarySchema._();

  static const currentVersion = 6;
  static const initialMigrationKey = 'phase_1_initial_schema';
  static const contributorsMigrationKey = 'phase_2_contributors';
  static const packageLineageMigrationKey = 'phase_3_package_lineage';
  static const storagePolicyMigrationKey = 'phase_4_epub_storage_policy';
  static const pioneerEpubProvenanceMigrationKey =
      'phase_5_pioneer_epub_provenance';
  static const researchIndexVersionMigrationKey =
      'phase_6_research_index_version';

  static Future<void> ensure(Database db) async {
    await _retryOnLocked(() async {
      await _createMigrationTable(db);
      await _createCoreTables(db);
      await _createCanonicalDocumentTables(db);
      await _createCanonicalStagingTables(db);
      await _createResearchIndexConversionTable(db);
      await _ensurePackageLineageColumns(db);
      await _ensureStoragePolicyColumns(db);
      await _ensurePioneerEpubProvenanceColumns(db);
      await _createIndexes(db);
      await _seedInitialMigration(db);
      await ELibraryBogusSdpCleanupService.instance.run(db);
      await ELibraryLegacyItemIdMigrationService.instance.run(db);
    });
  }

  /// Tracks, per research-pipeline library item, which
  /// `CommentaryResearchLibraryService.researchIndexVersion` its stored
  /// `library_text_blocks`/`library_navigation_items` rows were built
  /// under -- the research-pipeline equivalent of
  /// `library_document_conversion.canonicalizer_version`. A missing row or
  /// a stored `index_version` below the current constant means those rows
  /// were built by parsing logic older than the constant's last bump (e.g.
  /// the `EpubInternalAnchorSectionSplitter` internal-anchor-splitting fix)
  /// and must be rebuilt, not treated as already up to date.
  static Future<void> _createResearchIndexConversionTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_research_index_conversion (
        library_item_id TEXT PRIMARY KEY,
        index_version INTEGER NOT NULL,
        indexed_at TEXT
      )
    ''');
  }

  static Future<void> _createCanonicalDocumentTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_document_conversion (
        library_item_id TEXT PRIMARY KEY,
        canonicalizer_version INTEGER NOT NULL,
        source_hash TEXT,
        status TEXT NOT NULL CHECK(status IN ('pending','converting','complete','failed')),
        completed_at TEXT,
        error_message TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_document_sections (
        id TEXT PRIMARY KEY,
        library_item_id TEXT NOT NULL,
        display_order INTEGER NOT NULL,
        title TEXT,
        source_href TEXT,
        content_hash TEXT,
        UNIQUE(library_item_id, display_order)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_document_blocks (
        id TEXT PRIMARY KEY,
        library_item_id TEXT NOT NULL,
        section_id TEXT NOT NULL,
        display_order INTEGER NOT NULL,
        block_type TEXT NOT NULL,
        plain_text TEXT,
        formatted_content TEXT,
        source_refcode TEXT,
        source_href TEXT,
        source_anchor TEXT,
        content_hash TEXT,
        UNIQUE(library_item_id, display_order)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_block_source_map (
        library_item_id TEXT NOT NULL,
        block_id TEXT NOT NULL,
        source_href TEXT,
        legacy_block_index INTEGER,
        legacy_paragraph_index INTEGER,
        source_anchor TEXT,
        PRIMARY KEY(library_item_id, block_id)
      )
    ''');
  }

  /// Additive staging area for the canonical document generation currently
  /// being built. A candidate generation is written here, validated, and
  /// only copied into the real `library_document_*` tables (replacing the
  /// prior generation) once validation passes. If validation fails, the
  /// real tables are left untouched so the prior usable generation stays
  /// readable, and the failure is recorded on the staging conversion row.
  static Future<void> _createCanonicalStagingTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_document_conversion_staging (
        library_item_id TEXT PRIMARY KEY,
        canonicalizer_version INTEGER NOT NULL,
        source_hash TEXT,
        status TEXT NOT NULL CHECK(status IN ('converting','failed')),
        created_at TEXT,
        error_message TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_document_sections_staging (
        id TEXT PRIMARY KEY,
        library_item_id TEXT NOT NULL,
        display_order INTEGER NOT NULL,
        title TEXT,
        source_href TEXT,
        content_hash TEXT,
        UNIQUE(library_item_id, display_order)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_document_blocks_staging (
        id TEXT PRIMARY KEY,
        library_item_id TEXT NOT NULL,
        section_id TEXT NOT NULL,
        display_order INTEGER NOT NULL,
        block_type TEXT NOT NULL,
        plain_text TEXT,
        formatted_content TEXT,
        source_refcode TEXT,
        source_href TEXT,
        source_anchor TEXT,
        content_hash TEXT,
        UNIQUE(library_item_id, display_order)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_block_source_map_staging (
        library_item_id TEXT NOT NULL,
        block_id TEXT NOT NULL,
        source_href TEXT,
        legacy_block_index INTEGER,
        legacy_paragraph_index INTEGER,
        source_anchor TEXT,
        PRIMARY KEY(library_item_id, block_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_blocks_staging_item_order ON library_document_blocks_staging(library_item_id, display_order)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_sections_staging_item_order ON library_document_sections_staging(library_item_id, display_order)',
    );
  }

  /// Nullable/idempotent columns backing the platform EPUB storage policy.
  /// `epub_storage_state` is 'present' until a validated canonical import
  /// allows the app-managed EPUB copy to be removed (`removed_after_index`).
  static Future<void> _ensureStoragePolicyColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(library_items)');
    final names = columns
        .map((row) => row['name']?.toString().toLowerCase())
        .whereType<String>()
        .toSet();
    if (!names.contains('epub_storage_state')) {
      await db.execute(
        "ALTER TABLE library_items ADD COLUMN epub_storage_state TEXT NOT NULL DEFAULT 'present'",
      );
    }
    if (!names.contains('epub_removed_at')) {
      await db.execute(
        'ALTER TABLE library_items ADD COLUMN epub_removed_at TEXT',
      );
    }
  }

  /// Nullable provenance columns for a raw Pioneer EPUB folder bulk import
  /// (`library_items.source_type = 'pioneer_epub_import'`): the source
  /// file's path relative to the user-selected external Pioneer folder (so
  /// re-scanning that folder can find the same row again) and a content
  /// fingerprint (SHA-256) of the external source file (so an unchanged
  /// source can be skipped on a later import run without re-reading and
  /// re-canonicalizing it). Never populated for any other source type.
  static Future<void> _ensurePioneerEpubProvenanceColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(library_items)');
    final names = columns
        .map((row) => row['name']?.toString().toLowerCase())
        .whereType<String>()
        .toSet();
    if (!names.contains('pioneer_source_relative_path')) {
      await db.execute(
        'ALTER TABLE library_items ADD COLUMN pioneer_source_relative_path TEXT',
      );
    }
    if (!names.contains('pioneer_source_fingerprint')) {
      await db.execute(
        'ALTER TABLE library_items ADD COLUMN pioneer_source_fingerprint TEXT',
      );
    }
  }

  static Future<int?> currentAppliedVersion(Database db) async {
    try {
      final rows = await db.rawQuery('''
        SELECT MAX(to_version) AS schema_version
        FROM elibrary_schema_migrations
        WHERE status = 'completed'
      ''');
      if (rows.isEmpty) return null;
      return (rows.first['schema_version'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<String> schemaStatus(Database db) async {
    final version = await currentAppliedVersion(db);
    if (version == null) {
      return 'schema metadata missing';
    }
    if (version < currentVersion) {
      return 'schema migration required (version $version)';
    }
    return 'ready (version $version)';
  }

  static Future<void> _retryOnLocked(Future<void> Function() fn) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await fn();
        return;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        final isLocked =
            msg.contains('database is locked') ||
            msg.contains('sqlite_busy') ||
            msg.contains('code 5') ||
            msg.contains('code 6');
        if (isLocked && attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        rethrow;
      }
    }
  }

  static Future<void> _createMigrationTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS elibrary_schema_migrations (
        migration_key TEXT PRIMARY KEY,
        from_version INTEGER,
        to_version INTEGER NOT NULL,
        applied_at TEXT NOT NULL,
        status TEXT NOT NULL,
        details TEXT
      )
    ''');
  }

  static Future<void> _createCoreTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS elibrary_install_estimates (
        collection_key TEXT NOT NULL,
        format TEXT NOT NULL,
        file_count INTEGER NOT NULL,
        total_size_bytes INTEGER,
        size_known INTEGER NOT NULL DEFAULT 0,
        last_checked_utc TEXT,
        source TEXT,
        PRIMARY KEY (collection_key, format)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_items (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT,
        file_name TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        file_hash TEXT,
        source_work_id TEXT,
        source_package_id TEXT,
        file_size INTEGER,
        modified_at TEXT,
        mime_type TEXT,
        file_format TEXT,
        folder_type TEXT,
        library_role TEXT,
        collection_name TEXT,
        source_site TEXT,
        source_url TEXT,
        cover_path TEXT,
        date_added TEXT,
        last_opened TEXT,
        source_type TEXT,
        indexed_at TEXT,
        index_status TEXT,
        index_error TEXT,
        epub_href TEXT,
        epub_cfi TEXT,
        anchor_id TEXT,
        spine_index INTEGER,
        paragraph_index INTEGER,
        is_missing INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        device_id TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        last_synced_at TEXT,
        change_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_links (
        id TEXT PRIMARY KEY,
        library_item_id TEXT NOT NULL,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse_start INTEGER NOT NULL,
        verse_end INTEGER NOT NULL,
        link_type TEXT,
        anchor TEXT,
        original_reference_text TEXT,
        confidence REAL,
        parser_warning TEXT,
        epub_href TEXT,
        epub_cfi TEXT,
        anchor_id TEXT,
        spine_index INTEGER,
        paragraph_index INTEGER,
        full_paragraph TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        device_id TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        last_synced_at TEXT,
        change_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_navigation_items (
        id TEXT PRIMARY KEY,
        library_item_id TEXT NOT NULL,
        parent_id TEXT,
        label TEXT NOT NULL,
        href TEXT,
        anchor_id TEXT,
        spine_index INTEGER,
        sort_order INTEGER,
        depth INTEGER,
        nav_type TEXT,
        content_kind TEXT,
        is_front_matter INTEGER NOT NULL DEFAULT 0,
        is_body_start INTEGER NOT NULL DEFAULT 0,
        body_order INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        device_id TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        last_synced_at TEXT,
        change_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_text_blocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        library_item_id TEXT NOT NULL,
        epub_href TEXT NOT NULL,
        spine_index INTEGER,
        paragraph_index INTEGER NOT NULL,
        paragraph_on_section INTEGER NOT NULL DEFAULT 1,
        section_title TEXT,
        plain_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(library_item_id, epub_href, paragraph_index)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS elibrary_ref_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        library_item_id TEXT NOT NULL,
        work_key TEXT,
        edition_key TEXT,
        edition_year INTEGER,
        book_title TEXT,
        book_abbrev TEXT NOT NULL,
        href TEXT NOT NULL,
        anchor_id TEXT,
        paragraph_index INTEGER NOT NULL,
        page_number INTEGER NOT NULL,
        paragraph_on_page INTEGER NOT NULL,
        ref_code TEXT NOT NULL,
        stable_ref TEXT NOT NULL,
        plain_text TEXT,
        text_hash TEXT,
        ref_source TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        UNIQUE(library_item_id, href, paragraph_index)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_contributors (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        full_name TEXT,
        sort_name TEXT,
        normalized_name TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_item_contributors (
        library_item_id TEXT NOT NULL,
        contributor_id TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'author',
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_primary INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        PRIMARY KEY (library_item_id, contributor_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS elibrary_markups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        library_item_id TEXT NOT NULL,
        epub_href TEXT NOT NULL,
        start_block_index INTEGER NOT NULL,
        start_char_offset INTEGER NOT NULL,
        end_block_index INTEGER NOT NULL,
        end_char_offset INTEGER NOT NULL,
        start_token_index INTEGER,
        end_token_index INTEGER,
        ref_start TEXT,
        ref_end TEXT,
        compact_ref TEXT,
        selected_text_snapshot TEXT NOT NULL,
        markup_type TEXT NOT NULL,
        color TEXT NOT NULL,
        note_text TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
  }

  static Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_library_links_lookup
      ON library_links (link_type, book_id, chapter, verse_start, verse_end)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_library_items_folder_path
      ON library_items (folder_type, relative_path)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_library_navigation_items_lookup
      ON library_navigation_items (library_item_id, sort_order, depth)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_library_text_blocks_item
      ON library_text_blocks (library_item_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_library_text_blocks_item_spine
      ON library_text_blocks (library_item_id, spine_index)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_library_text_blocks_item_href
      ON library_text_blocks (library_item_id, epub_href)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_elibrary_ref_index_lookup
      ON elibrary_ref_index (library_item_id, href, paragraph_index)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_elibrary_markups_item_href
      ON elibrary_markups (library_item_id, epub_href, deleted_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_elibrary_markups_item_type
      ON elibrary_markups (library_item_id, markup_type, deleted_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_library_item_contributors_item
      ON library_item_contributors (library_item_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_library_item_contributors_contributor
      ON library_item_contributors (contributor_id)
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_sections_item_order ON library_document_sections(library_item_id, display_order)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_blocks_item_order ON library_document_blocks(library_item_id, display_order)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_blocks_section_order ON library_document_blocks(section_id, display_order)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_blocks_source_href ON library_document_blocks(source_href)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_document_blocks_refcode ON library_document_blocks(source_refcode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_block_source_map_block ON library_block_source_map(block_id)',
    );
  }

  static Future<void> _ensurePackageLineageColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(library_items)');
    final names = columns
        .map((row) => row['name']?.toString().toLowerCase())
        .whereType<String>()
        .toSet();
    if (!names.contains('source_work_id')) {
      await db.execute(
        'ALTER TABLE library_items ADD COLUMN source_work_id TEXT',
      );
    }
    if (!names.contains('source_package_id')) {
      await db.execute(
        'ALTER TABLE library_items ADD COLUMN source_package_id TEXT',
      );
    }
  }

  static Future<void> _seedInitialMigration(Database db) async {
    final now = _utcNow();
    await db.insert('elibrary_schema_migrations', {
      'migration_key': initialMigrationKey,
      'from_version': 0,
      'to_version': currentVersion,
      'applied_at': now,
      'status': 'completed',
      'details': 'Initial eLibrary schema bootstrap.',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('elibrary_schema_migrations', {
      'migration_key': contributorsMigrationKey,
      'from_version': 1,
      'to_version': currentVersion,
      'applied_at': now,
      'status': 'completed',
      'details':
          'Added library_contributors and library_item_contributors tables.',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('elibrary_schema_migrations', {
      'migration_key': packageLineageMigrationKey,
      'from_version': 1,
      'to_version': currentVersion,
      'applied_at': now,
      'status': 'completed',
      'details':
          'Added nullable source_work_id and source_package_id to library_items.',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('elibrary_schema_migrations', {
      'migration_key': storagePolicyMigrationKey,
      'from_version': 3,
      'to_version': currentVersion,
      'applied_at': now,
      'status': 'completed',
      'details':
          'Added canonical document staging tables and library_items epub_storage_state/epub_removed_at columns.',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('elibrary_schema_migrations', {
      'migration_key': pioneerEpubProvenanceMigrationKey,
      'from_version': 4,
      'to_version': currentVersion,
      'applied_at': now,
      'status': 'completed',
      'details':
          'Added nullable pioneer_source_relative_path/pioneer_source_fingerprint to library_items for raw Pioneer EPUB folder bulk import.',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('elibrary_schema_migrations', {
      'migration_key': researchIndexVersionMigrationKey,
      'from_version': 5,
      'to_version': currentVersion,
      'applied_at': now,
      'status': 'completed',
      'details':
          'Added library_research_index_conversion to track which research-pipeline indexing logic version built each item\'s library_text_blocks/library_navigation_items rows.',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static String _utcNow() {
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    return iso.contains('.') ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z') : iso;
  }
}
