import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/elibrary_read_resolver.dart';
import '../../../core/theme/app_settings_service.dart';
import 'elibrary_folder_policy.dart';

enum EpubStoragePlatform { mobile, desktop }

enum EpubRetentionPreference { keep, removeAfterIndexing }

class EpubStoragePolicyDecision {
  const EpubStoragePolicyDecision({
    required this.shouldRemoveEpub,
    required this.reason,
  });

  final bool shouldRemoveEpub;
  final String reason;
}

/// Decides whether the app-managed EPUB copy of a book may be deleted once
/// its canonical database representation has been built and validated.
///
/// The policy never removes a file unless every one of these hold:
///  - the canonical import was actually validated (never remove on a failed
///    or skipped validation — see [LibraryDocumentImportValidator]),
///  - the path was positively identified as an app-managed download (never
///    CaptureClipper captures, external files, or anything of uncertain
///    provenance — see [ELibraryFolderPolicy.isManagedEgwFolderPath]),
///  - the resolved platform/preference combination actually calls for
///    removal (desktop defaults to keep; mobile defaults to save-space).
class EpubStoragePolicyService {
  EpubStoragePolicyService._();

  static final EpubStoragePolicyService instance = EpubStoragePolicyService._();

  static const _desktopRetentionKey = 'library.storage.desktop_epub_retention';
  static const _mobileRetentionKey = 'library.storage.mobile_epub_retention';

  EpubStoragePolicyDecision decide({
    required EpubStoragePlatform platform,
    required EpubRetentionPreference preference,
    required bool isPositivelyAppManaged,
    required bool validationPassed,
  }) {
    if (!validationPassed) {
      return const EpubStoragePolicyDecision(
        shouldRemoveEpub: false,
        reason: 'Canonical import was not validated; retaining source.',
      );
    }
    if (!isPositivelyAppManaged) {
      return const EpubStoragePolicyDecision(
        shouldRemoveEpub: false,
        reason:
            'EPUB path is not positively identified as an app-managed '
            'download; retaining source.',
      );
    }
    if (preference == EpubRetentionPreference.keep) {
      return const EpubStoragePolicyDecision(
        shouldRemoveEpub: false,
        reason: 'Retention preference is "keep".',
      );
    }
    return EpubStoragePolicyDecision(
      shouldRemoveEpub: true,
      reason:
          '${platform == EpubStoragePlatform.mobile ? 'Mobile' : 'Desktop'} '
          'retention preference is "remove after indexing".',
    );
  }

  Future<EpubRetentionPreference> loadDesktopEpubRetentionPreference() async {
    final value = await AppSettingsService.instance.loadRawSetting(
      _desktopRetentionKey,
    );
    return value == 'remove'
        ? EpubRetentionPreference.removeAfterIndexing
        : EpubRetentionPreference.keep;
  }

  Future<void> saveDesktopEpubRetentionPreference(
    EpubRetentionPreference preference,
  ) => AppSettingsService.instance.saveRawSetting(
    _desktopRetentionKey,
    preference == EpubRetentionPreference.removeAfterIndexing
        ? 'remove'
        : 'keep',
  );

  Future<EpubRetentionPreference> loadMobileEpubRetentionPreference() async {
    final value = await AppSettingsService.instance.loadRawSetting(
      _mobileRetentionKey,
    );
    return value == 'keep'
        ? EpubRetentionPreference.keep
        : EpubRetentionPreference.removeAfterIndexing;
  }

  Future<void> saveMobileEpubRetentionPreference(
    EpubRetentionPreference preference,
  ) => AppSettingsService.instance.saveRawSetting(
    _mobileRetentionKey,
    preference == EpubRetentionPreference.keep ? 'keep' : 'remove',
  );

  EpubStoragePlatform currentPlatform() => Platform.isMacOS
      ? EpubStoragePlatform.desktop
      : EpubStoragePlatform.mobile;

  Future<EpubRetentionPreference> currentPreference({
    EpubStoragePlatform? platform,
  }) async {
    final resolved = platform ?? currentPlatform();
    return resolved == EpubStoragePlatform.desktop
        ? loadDesktopEpubRetentionPreference()
        : loadMobileEpubRetentionPreference();
  }

  /// Applies the current platform/user storage policy to [epubFile] after a
  /// validated canonical import of [libraryItemId]. Only ever deletes a file
  /// positively identified as an app-managed download within [rootPath] (or
  /// recognized via [ELibraryFolderPolicy.isManagedEgwFolderPath] when
  /// [rootPath] is unavailable); on removal, records
  /// `library_items.epub_storage_state`/`epub_removed_at` but never touches
  /// `deleted_at`/`is_missing`, which remain reserved for user-initiated
  /// full removal.
  Future<EpubStoragePolicyDecision> applyPolicyAfterValidatedImport({
    required String libraryItemId,
    required File epubFile,
    String? rootPath,
    EpubStoragePlatform? platformOverride,
  }) async {
    final normalizedPath = p.normalize(epubFile.absolute.path);
    final isPositivelyAppManaged =
        ELibraryFolderPolicy.isManagedEgwFolderPath(normalizedPath) &&
        (rootPath == null ||
            rootPath.trim().isEmpty ||
            p.isWithin(p.normalize(rootPath.trim()), normalizedPath));

    final platform = platformOverride ?? currentPlatform();
    final preference = await currentPreference(platform: platform);
    final decision = decide(
      platform: platform,
      preference: preference,
      isPositivelyAppManaged: isPositivelyAppManaged,
      validationPassed: true,
    );

    if (!decision.shouldRemoveEpub) return decision;
    if (!await epubFile.exists()) return decision;

    await epubFile.delete();
    await _markEpubRemoved(libraryItemId);
    return decision;
  }

  Future<void> _markEpubRemoved(String libraryItemId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rowResult = await ELibraryReadResolver.instance
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.query(
            'library_items',
            columns: const <String>['id'],
            where: 'id = ?',
            whereArgs: <Object?>[libraryItemId],
            limit: 1,
          ),
          hasData: (rows) => rows.isNotEmpty,
        );
    if (rowResult.value.isEmpty) return;
    await rowResult.database.update(
      'library_items',
      <String, Object?>{
        'epub_storage_state': 'removed_after_index',
        'epub_removed_at': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: <Object?>[libraryItemId],
    );
  }
}
