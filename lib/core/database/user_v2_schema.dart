import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class UserV2Schema {
  UserV2Schema._();

  static Future<void> ensure(Database db, {required String deviceId}) async {
    await _retryOnLocked(() async {
      await _createCoreTables(db);
      await _createSyncTables(db);
      await _ensureLibraryLinkColumns(db);
      await _ensureLibraryNavigationColumns(db);
      await _ensureElibraryRefIndex(db);
      await _ensureLibraryTextBlocks(db);
      await _ensureElibraryMarkups(db);
      await _ensureTagTrashColumns(db);
      await _ensurePresentationPrepTables(db);
      await _seedDevicesTable(db, deviceId: deviceId);
      await _seedSyncState(db, deviceId: deviceId);
    });
  }

  // Retries fn up to 3 times with backoff when SQLite reports SQLITE_BUSY/LOCKED.
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

  static Future<void> _createCoreTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS prefs (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS highlight_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        name TEXT,
        color_hex TEXT,
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT,
        device_id TEXT,
        revision INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'pending',
        last_synced_at TEXT,
        change_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS highlights (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER,
        verse_ref TEXT,
        start_token INTEGER,
        end_token INTEGER,
        created_at TEXT,
        updated_at TEXT,
        deleted_at TEXT,
        device_id TEXT,
        revision INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'pending',
        last_synced_at TEXT,
        change_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hash_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        tag TEXT NOT NULL,
        verse_ref TEXT NOT NULL,
        book_number INTEGER NOT NULL,
        chapter_number INTEGER NOT NULL,
        verse_number INTEGER NOT NULL,
        token_number INTEGER,
        presentation_slide_region TEXT,
        created_at INTEGER NOT NULL,
        sort_order INTEGER,
        note_format_json TEXT,
        presentation_slide_number INTEGER,
        created_at_utc TEXT,
        updated_at_utc TEXT,
        deleted_at_utc TEXT,
        device_id TEXT,
        revision INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'pending',
        last_synced_at TEXT,
        change_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dollar_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        tag TEXT NOT NULL,
        verse_ref TEXT NOT NULL,
        book_number INTEGER NOT NULL,
        chapter_number INTEGER NOT NULL,
        verse_number INTEGER NOT NULL,
        token_number INTEGER,
        content_html TEXT NOT NULL,
        note_format_json TEXT,
        source_author TEXT,
        source_work_title TEXT,
        source_title_acronym TEXT,
        source_chapter_title TEXT,
        source_chapter_number TEXT,
        source_page_number TEXT,
        source_paragraph_number TEXT,
        source_year TEXT,
        created_at INTEGER NOT NULL,
        study_order INTEGER NOT NULL DEFAULT 0,
        created_at_utc TEXT,
        updated_at_utc TEXT,
        deleted_at_utc TEXT,
        device_id TEXT,
        revision INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'pending',
        last_synced_at TEXT,
        change_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS at_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        tag TEXT NOT NULL,
        verse_ref TEXT NOT NULL,
        book_number INTEGER NOT NULL,
        chapter_number INTEGER NOT NULL,
        verse_number INTEGER NOT NULL,
        token_number INTEGER,
        bible_text_html TEXT NOT NULL,
        commentary_html TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        created_at_utc TEXT,
        updated_at_utc TEXT,
        deleted_at_utc TEXT,
        device_id TEXT,
        revision INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'pending',
        last_synced_at TEXT,
        change_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        block_id INTEGER NOT NULL,
        ts INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS navigation_history (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        block_id INTEGER NOT NULL,
        book INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memory_verses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        verse_ref TEXT NOT NULL UNIQUE,
        book_number INTEGER NOT NULL,
        book_name TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        verse_text TEXT NOT NULL,
        review_step INTEGER NOT NULL DEFAULT 0,
        next_due_at INTEGER NOT NULL,
        last_result TEXT,
        total_reviews INTEGER NOT NULL DEFAULT 0,
        total_misses INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        end_chapter INTEGER NOT NULL DEFAULT 0,
        end_verse INTEGER NOT NULL DEFAULT 0,
        group_name TEXT
      )
    ''');
  }

  static Future<void> _createSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        platform TEXT,
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
      CREATE TABLE IF NOT EXISTS sync_state (
        id TEXT PRIMARY KEY,
        state_key TEXT NOT NULL UNIQUE,
        state_value TEXT,
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
      CREATE TABLE IF NOT EXISTS sync_changes (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT,
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
      CREATE TABLE IF NOT EXISTS tag_groups (
        id TEXT PRIMARY KEY,
        parent_group_id TEXT,
        tag_kind TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        source_device_name TEXT,
        legacy_group_id TEXT,
        legacy_item_id TEXT,
        legacy_import_package_id TEXT,
        imported_at TEXT,
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
      CREATE TABLE IF NOT EXISTS tag_items (
        id TEXT PRIMARY KEY,
        tag_group_id TEXT NOT NULL,
        tag_kind TEXT NOT NULL,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse_start INTEGER NOT NULL,
        verse_end INTEGER NOT NULL,
        reference_code TEXT,
        presentation_slide_number INTEGER,
        presentation_slide_region TEXT,
        note_text TEXT,
        note_format_json TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        source_device_name TEXT,
        legacy_group_id TEXT,
        legacy_item_id TEXT,
        legacy_import_package_id TEXT,
        imported_at TEXT,
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
      CREATE TABLE IF NOT EXISTS tag_item_media (
        id TEXT PRIMARY KEY,
        tag_item_id TEXT NOT NULL,
        media_type TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        caption TEXT,
        file_hash TEXT,
        source_work_id TEXT,
        source_package_id TEXT,
        file_size INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        source_device_name TEXT,
        legacy_group_id TEXT,
        legacy_item_id TEXT,
        legacy_import_package_id TEXT,
        imported_at TEXT,
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
      CREATE TABLE IF NOT EXISTS bookmarks (
        id TEXT PRIMARY KEY,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse_start INTEGER NOT NULL,
        verse_end INTEGER NOT NULL,
        label TEXT,
        anchor TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
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
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse_start INTEGER NOT NULL,
        verse_end INTEGER NOT NULL,
        note_text TEXT NOT NULL,
        title TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
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
      CREATE TABLE IF NOT EXISTS reading_history (
        id TEXT PRIMARY KEY,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse_start INTEGER NOT NULL,
        verse_end INTEGER NOT NULL,
        opened_at TEXT NOT NULL,
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
      CREATE TABLE IF NOT EXISTS search_history (
        id TEXT PRIMARY KEY,
        query_text TEXT NOT NULL,
        search_scope TEXT,
        searched_at TEXT NOT NULL,
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
      CREATE TABLE IF NOT EXISTS presentation_lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
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
      CREATE TABLE IF NOT EXISTS presentation_items (
        id TEXT PRIMARY KEY,
        presentation_list_id TEXT NOT NULL,
        item_type TEXT NOT NULL,
        item_text TEXT,
        reference_label TEXT,
        relative_path TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
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
      CREATE TABLE IF NOT EXISTS presentation_item_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_type TEXT NOT NULL,
        source_id TEXT NOT NULL,
        tag_id INTEGER NOT NULL,
        font_size_override REAL,
        alignment TEXT,
        layout TEXT,
        allow_scroll INTEGER NOT NULL DEFAULT 1,
        auto_fit INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        created_at TEXT,
        created_at_utc TEXT,
        updated_at_utc TEXT,
        deleted_at_utc TEXT,
        device_id TEXT,
        revision INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'pending',
        last_synced_at TEXT,
        change_id TEXT,
        UNIQUE(source_type, source_id, tag_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_migrations (
        migration_key TEXT PRIMARY KEY,
        from_version TEXT,
        to_version TEXT,
        started_at TEXT NOT NULL,
        completed_at TEXT,
        backup_path TEXT,
        status TEXT NOT NULL,
        error_message TEXT,
        source_device_name TEXT,
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
      CREATE TABLE IF NOT EXISTS legacy_unmapped_import (
        id TEXT PRIMARY KEY,
        source_table TEXT NOT NULL,
        source_device_name TEXT,
        legacy_group_id TEXT,
        legacy_item_id TEXT,
        legacy_import_package_id TEXT,
        imported_at TEXT,
        payload_json TEXT NOT NULL,
        reason TEXT,
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
  }

  static Future<void> _ensureLibraryLinkColumns(Database db) async {
    final linkColumns = await _tableColumns(db, 'library_links');
    await _addColumnIfMissing(
      db,
      'library_links',
      linkColumns,
      'original_reference_text',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_links',
      linkColumns,
      'confidence',
      'REAL',
    );
    await _addColumnIfMissing(
      db,
      'library_links',
      linkColumns,
      'parser_warning',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_links',
      linkColumns,
      'epub_href',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_links',
      linkColumns,
      'epub_cfi',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_links',
      linkColumns,
      'anchor_id',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_links',
      linkColumns,
      'spine_index',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'library_links',
      linkColumns,
      'paragraph_index',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'library_links',
      linkColumns,
      'full_paragraph',
      'TEXT',
    );

    final itemColumns = await _tableColumns(db, 'library_items');
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'source_work_id',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'source_package_id',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'modified_at',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'file_format',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'library_role',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'collection_name',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'cover_path',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'source_site',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'source_url',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'indexed_at',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'index_status',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'index_error',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'epub_href',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'epub_cfi',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'anchor_id',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'spine_index',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'library_items',
      itemColumns,
      'paragraph_index',
      'INTEGER',
    );
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
  }

  static Future<void> _ensureLibraryNavigationColumns(Database db) async {
    final navigationColumns = await _tableColumns(
      db,
      'library_navigation_items',
    );
    await _addColumnIfMissing(
      db,
      'library_navigation_items',
      navigationColumns,
      'content_kind',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'library_navigation_items',
      navigationColumns,
      'is_front_matter',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'library_navigation_items',
      navigationColumns,
      'is_body_start',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'library_navigation_items',
      navigationColumns,
      'body_order',
      'INTEGER',
    );
  }

  static Future<void> _ensureElibraryRefIndex(Database db) async {
    final existingTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='elibrary_ref_index'",
    );
    if (existingTables.isEmpty) {
      await db.execute('''
        CREATE TABLE elibrary_ref_index (
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
    }

    final existingIndexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_elibrary_ref_index_lookup'",
    );
    if (existingIndexes.isEmpty) {
      await db.execute('''
        CREATE INDEX idx_elibrary_ref_index_lookup
        ON elibrary_ref_index (library_item_id, href, paragraph_index)
      ''');
    }
  }

  static Future<void> _ensureLibraryTextBlocks(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_text_blocks (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        library_item_id      TEXT    NOT NULL,
        epub_href            TEXT    NOT NULL,
        spine_index          INTEGER,
        paragraph_index      INTEGER NOT NULL,
        paragraph_on_section INTEGER NOT NULL DEFAULT 1,
        section_title        TEXT,
        plain_text           TEXT    NOT NULL,
        created_at           TEXT    NOT NULL,
        updated_at           TEXT    NOT NULL,
        UNIQUE(library_item_id, epub_href, paragraph_index)
      )
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
  }

  static Future<void> _ensureElibraryMarkups(Database db) async {
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
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_elibrary_markups_item_href
      ON elibrary_markups (library_item_id, epub_href, deleted_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_elibrary_markups_item_type
      ON elibrary_markups (library_item_id, markup_type, deleted_at)
    ''');
  }

  static Future<void> _ensurePresentationPrepTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presentation_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        source_tag_id TEXT,
        source_tag_key TEXT,
        source_tag_name TEXT,
        default_display_target TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presentation_prep_slides (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        presentation_id INTEGER NOT NULL,
        slide_order INTEGER NOT NULL,
        title TEXT,
        top_header_text TEXT,
        bottom_footer_text TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presentation_prep_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        slide_id INTEGER NOT NULL,
        display_target TEXT NOT NULL,
        aspect_ratio_preset TEXT NOT NULL,
        aspect_ratio_value REAL NOT NULL,
        rows INTEGER NOT NULL,
        columns INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presentation_prep_zones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_id INTEGER NOT NULL,
        zone_key TEXT NOT NULL,
        zone_type TEXT NOT NULL,
        start_row INTEGER NOT NULL,
        start_column INTEGER NOT NULL,
        row_span INTEGER NOT NULL,
        column_span INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS presentation_prep_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        slide_id INTEGER NOT NULL,
        zone_key TEXT NOT NULL,
        item_order INTEGER NOT NULL,
        source_item_id TEXT,
        item_type TEXT,
        title_override TEXT,
        body_override TEXT,
        media_path TEXT,
        media_caption TEXT,
        style_overrides_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _ensureTagTrashColumns(Database db) async {
    final tagGroupColumns = await _tableColumns(db, 'tag_groups');
    await _addColumnIfMissing(
      db,
      'tag_groups',
      tagGroupColumns,
      'trashed_at',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'tag_groups',
      tagGroupColumns,
      'trashed_reason',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'tag_groups',
      tagGroupColumns,
      'original_parent_group_id',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'tag_groups',
      tagGroupColumns,
      'trash_batch_id',
      'TEXT',
    );

    final tagItemColumns = await _tableColumns(db, 'tag_items');
    await _addColumnIfMissing(
      db,
      'tag_items',
      tagItemColumns,
      'trashed_at',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'tag_items',
      tagItemColumns,
      'trashed_reason',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'tag_items',
      tagItemColumns,
      'original_tag_group_id',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'tag_items',
      tagItemColumns,
      'trash_batch_id',
      'TEXT',
    );

    final tagItemMediaColumns = await _tableColumns(db, 'tag_item_media');
    await _addColumnIfMissing(
      db,
      'tag_item_media',
      tagItemMediaColumns,
      'trashed_at',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'tag_item_media',
      tagItemMediaColumns,
      'trashed_reason',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'tag_item_media',
      tagItemMediaColumns,
      'trash_batch_id',
      'TEXT',
    );

    for (final legacyTable in ['hash_tags', 'dollar_tags', 'at_tags']) {
      final cols = await _tableColumns(db, legacyTable);
      await _addColumnIfMissing(
        db,
        legacyTable,
        cols,
        'trashed_at_utc',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        legacyTable,
        cols,
        'trashed_reason',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        legacyTable,
        cols,
        'original_category',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        legacyTable,
        cols,
        'trash_batch_id',
        'TEXT',
      );
    }
  }

  static Future<Set<String>> _tableColumns(
    Database db,
    String tableName,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    return rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String tableName,
    Set<String> columns,
    String name,
    String type,
  ) async {
    if (columns.contains(name)) return;
    await db.execute('ALTER TABLE $tableName ADD COLUMN $name $type');
    columns.add(name);
  }

  static Future<void> _seedDevicesTable(
    Database db, {
    required String deviceId,
  }) async {
    final now = _utcNow();
    await db.insert('devices', {
      'id': deviceId,
      'name': 'Current Device',
      'platform': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': deviceId,
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _seedSyncState(
    Database db, {
    required String deviceId,
  }) async {
    final now = _utcNow();
    await db.insert('sync_state', {
      'id': 'global',
      'state_key': 'global',
      'state_value': '{}',
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': deviceId,
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static String _utcNow() {
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    return iso.contains('.') ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z') : iso;
  }
}
