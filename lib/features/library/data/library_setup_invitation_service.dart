import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_database.dart';
import 'library_setup_state.dart';

/// Decides whether the one-time "Set Up My Library" invitation should be
/// shown. Read-only with respect to library content — it only ever counts
/// existing rows and reads/writes the small [LibrarySetupState] preference.
class LibrarySetupInvitationService {
  LibrarySetupInvitationService._();

  static final LibrarySetupInvitationService instance =
      LibrarySetupInvitationService._();

  /// True only when the user has neither completed nor explicitly skipped
  /// setup, and no readable book exists yet. Callers are responsible for
  /// only invoking this when no other setup/import/migration flow is
  /// already in progress (e.g. from the idle Entry screen).
  Future<bool> shouldShowInvitation() async {
    final state = await LocalSettingsStore.instance.loadLibrarySetupState();
    if (state != LibrarySetupState.notStarted) return false;
    return !await hasAnyReadableItem();
  }

  /// `library_items.source_type` values a real acquisition flow can
  /// actually produce. The shipped template `eLibrary.db` ships with a
  /// couple of baked-in reference rows (`source_type = 'egw_html_capture'`,
  /// not written by any current import path) so every fresh install would
  /// otherwise already "have a readable book" and the invitation could
  /// never appear. Scoping to real acquisition source types excludes only
  /// that pre-bundled reference content, never anything a user actually
  /// downloaded or imported.
  static const Set<String> _acquiredSourceTypes = <String>{
    'official_download',
    'pioneer_captured_html',
    'epub',
    'user_import',
    'pioneer_epub_import',
  };

  /// Cheap existence check — not a full [LibraryCatalogService.loadItems]
  /// scan. Mirrors the same "only needs_attention is unavailable" rule
  /// `libraryItemAvailability` already uses.
  Future<bool> hasAnyReadableItem() async {
    final db = await ELibraryDatabase.instance.database;
    final placeholders = List.filled(
      _acquiredSourceTypes.length,
      '?',
    ).join(', ');
    final rows = await db.rawQuery('''
      SELECT 1 FROM library_items
      WHERE deleted_at IS NULL
        AND COALESCE(is_missing, 0) = 0
        AND (index_status IS NULL OR LOWER(index_status) != 'needs_attention')
        AND LOWER(COALESCE(source_type, '')) IN ($placeholders)
      LIMIT 1
    ''', _acquiredSourceTypes.toList(growable: false));
    return rows.isNotEmpty;
  }

  Future<void> markCompleted() => LocalSettingsStore.instance
      .saveLibrarySetupState(LibrarySetupState.completed);

  Future<void> markSkipped() => LocalSettingsStore.instance
      .saveLibrarySetupState(LibrarySetupState.skipped);

  /// Restores the invitation (e.g. a future "reset" action in Advanced).
  Future<void> reset() => LocalSettingsStore.instance.resetLibrarySetupState();
}
