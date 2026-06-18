import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ELibrarySchema {
  ELibrarySchema._();

  static const currentVersion = 1;
  static const initialMigrationKey = 'phase_1_initial_schema';

  static Future<void> ensure(Database db) async {
    await _retryOnLocked(() async {
      await _createMigrationTable(db);
      await _createCoreTables(db);
      await _createIndexes(db);
      await _seedInitialMigration(db);
    });
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
  }

  static String _utcNow() {
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    return iso.contains('.') ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z') : iso;
  }
}
