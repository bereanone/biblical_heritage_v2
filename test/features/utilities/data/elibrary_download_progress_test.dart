import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/data/elibrary_download_service.dart';

void main() {
  test('30. ELibraryDownloadProgress.phase is optional and backward compatible '
      '— existing call sites that never set it keep working', () {
    const progress = ELibraryDownloadProgress(
      currentCollection: 'EGW Books',
      collectionIndex: 1,
      collectionTotal: 1,
      discoveredCount: 10,
      downloadedCount: 3,
      skippedCount: 2,
      unavailableCount: 1,
      failedCount: 0,
      currentFile: 'en_1T.epub',
      elapsedSeconds: 4.2,
      statusMessage: 'Downloading EGW Books The Great Controversy (EPUB)',
    );

    expect(progress.phase, ELibraryDownloadPhase.downloadingItem);
    expect(progress.totalPlannedCount, 0);
    expect(progress.completedCount, 6);
  });

  test('31. every download phase — collection started, downloading, '
      'validating, and each terminal outcome — is a distinct, named phase '
      'a UI can render continuously', () {
    expect(ELibraryDownloadPhase.values, <ELibraryDownloadPhase>[
      ELibraryDownloadPhase.collectionStarted,
      ELibraryDownloadPhase.downloadingItem,
      ELibraryDownloadPhase.validatingItem,
      ELibraryDownloadPhase.itemDownloaded,
      ELibraryDownloadPhase.itemSkippedUnchanged,
      ELibraryDownloadPhase.itemUnavailable,
      ELibraryDownloadPhase.itemFailed,
    ]);
  });

  test('a determinate total lets a UI compute a real completion fraction', () {
    const progress = ELibraryDownloadProgress(
      currentCollection: 'EGW Books',
      collectionIndex: 1,
      collectionTotal: 3,
      discoveredCount: 40,
      downloadedCount: 18,
      skippedCount: 2,
      unavailableCount: 0,
      failedCount: 0,
      currentFile: 'en_2T.epub',
      elapsedSeconds: 12.0,
      statusMessage: 'Downloading EGW Books Testimonies Vol 2 (EPUB)',
      phase: ELibraryDownloadPhase.downloadingItem,
      totalPlannedCount: 40,
    );

    expect(progress.completedCount, 20);
    expect(progress.completedCount / progress.totalPlannedCount, 0.5);
  });
}
