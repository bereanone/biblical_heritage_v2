import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/library_root_native.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/user_database.dart';
import '../../library/data/library_catalog_service.dart';
import '../../library/presentation/import_pioneer_library_screen.dart';
import '../../reader/data/commentary_research_library_service.dart';
import '../data/elibrary_file_management_service.dart';
import '../data/elibrary_duplicate_cleanup_service.dart';
import '../data/elibrary_install_estimate_repository.dart';
import '../data/elibrary_migration_service.dart';
import '../data/elibrary_download_service.dart';
import '../data/elibrary_storage_policy.dart';
import '../data/pioneer_book_package_import_service.dart';
import '../data/pioneer_study_collection_service.dart';
import '../data/pioneer_captured_html_import_availability_service.dart';
import '../data/pioneer_captured_html_import_folder_service.dart';
import '../data/pioneer_epub_collection_service.dart';
import '../data/pioneer_source_catalog.dart';
import '../data/pioneer_text_import_service.dart';
import 'library_indexing_prompt_dialogs.dart';
import 'study_collection_import_dialog.dart';
import 'pioneer_captured_html_import_dialogs.dart';
import 'pioneer_captured_html_import_review_screen.dart';
import 'library_root_setup_screen.dart';

const _sourceCleanupDeferredMessage =
    'Future-facing cleanup policy: imported works stay in eLibrary.db and only downloaded source files are eligible for removal.';

enum _ELibraryRunCompletionStatus {
  cleanSuccess,
  completedWithWarnings,
  failedOrIncomplete,
}

bool isUsableLibraryRootSelection(LibraryRootSelection? selection) {
  return selection?.path?.trim().isNotEmpty == true &&
      selection?.exists == true;
}

String formatELibraryBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = -1;
  do {
    value /= 1024;
    unitIndex += 1;
  } while (value >= 1024 && unitIndex < units.length - 1);
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
}

String libraryStorageStatusText(LibraryRootSelection? selection) {
  return isUsableLibraryRootSelection(selection)
      ? '✓ Library is ready'
      : 'Library storage needs attention';
}

String libraryStorageHelperText(LibraryRootSelection? selection) {
  return isUsableLibraryRootSelection(selection)
      ? 'Downloaded and imported books are stored in the app\'s library.'
      : 'Open Manage Storage to choose or repair the library location.';
}

class CaptureClipperFolderDetails extends StatelessWidget {
  const CaptureClipperFolderDetails({
    super.key,
    required this.loading,
    required this.path,
    required this.access,
    required this.status,
  });

  final bool loading;
  final String? path;
  final String? access;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget pathLine(String label, String? value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SelectableText('$label: ${value ?? "(not set)"}'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading)
          const LinearProgressIndicator()
        else ...[
          pathLine('Folder path', path),
          pathLine('Folder access', access),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(
              status!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class CaptureClipperImportButton extends StatelessWidget {
  const CaptureClipperImportButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String? label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = label;
    if (text == null) {
      return const SizedBox.shrink();
    }
    return FilledButton(onPressed: busy ? null : onPressed, child: Text(text));
  }
}

class CaptureClipperPackageImportControls extends StatelessWidget {
  const CaptureClipperPackageImportControls({
    super.key,
    required this.busy,
    required this.onImportPackage,
    this.onTestBroadPicker,
  });

  final bool busy;
  final VoidCallback onImportPackage;
  final VoidCallback? onTestBroadPicker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton(
          onPressed: busy ? null : onImportPackage,
          child: const Text('Import Book Package'),
        ),
        const SizedBox(height: 8),
        Text(
          'Select one .studybook or .studycollection file from OneDrive, iCloud Drive, '
          'Google Drive, or On My iPad. StudyBible2 copies and unpacks it '
          'locally. Your cloud file is not changed.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (onTestBroadPicker != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : onTestBroadPicker,
            child: const Text('Test Broad Any File Picker'),
          ),
          const SizedBox(height: 4),
          Text(
            'Diagnostic only: opens the same broad public.item picker, shows '
            'the selected filename/path, and imports nothing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class CaptureClipperFileImportControls extends StatelessWidget {
  const CaptureClipperFileImportControls({
    super.key,
    required this.busy,
    required this.onPickHtmlFiles,
    required this.onPickRelatedFiles,
  });

  final bool busy;
  final VoidCallback onPickHtmlFiles;
  final VoidCallback onPickRelatedFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose one or more CaptureClipper book packages from OneDrive. '
          'StudyBible2 will import new or updated books and leave the originals unchanged.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: busy ? null : onPickHtmlFiles,
              child: const Text('Import Captured Books'),
            ),
            OutlinedButton(
              onPressed: busy ? null : onPickRelatedFiles,
              child: const Text('Add Related Book Files'),
            ),
          ],
        ),
      ],
    );
  }
}

class CloudFilesFolderPickerControls extends StatelessWidget {
  const CloudFilesFolderPickerControls({
    super.key,
    required this.busy,
    required this.isLegacy,
    required this.showHtmlFallback,
    required this.onChangeFolder,
    required this.onResetFolder,
    required this.onPickScannedHtmlFile,
  });

  final bool busy;
  final bool isLegacy;
  final bool showHtmlFallback;
  final VoidCallback onChangeFolder;
  final VoidCallback onResetFolder;
  final VoidCallback onPickScannedHtmlFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLegacy) ...[
          Text(
            'The app Documents folder is a legacy fallback, not the CloudFiles folder. '
            'Choose or reset it to point at OneDrive/CloudFiles.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (showHtmlFallback) ...[
          Text(
            'Use "Change Import Location" for iCloud Drive, On My iPad, '
            'and other providers that allow folder access. If OneDrive '
            'appears faded here, use "Import Captured Books" from OneDrive '
            'above instead.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: busy ? null : onChangeFolder,
              child: const Text('Change Import Location'),
            ),
            OutlinedButton(
              onPressed: busy ? null : onResetFolder,
              child: const Text('Reset Import Location'),
            ),
            if (showHtmlFallback)
              OutlinedButton(
                onPressed: busy ? null : onPickScannedHtmlFile,
                child: const Text('Pick Scanned HTML File'),
              ),
          ],
        ),
      ],
    );
  }
}

class ELibraryStorageSection extends StatelessWidget {
  const ELibraryStorageSection({
    super.key,
    required this.statusLabel,
    required this.helperText,
    required this.disableActions,
    required this.onManageStorage,
    required this.onIndexNewChangedBooks,
    required this.onRefreshStatus,
    required this.manualIndexing,
    required this.manualIndexStatus,
    required this.manualIndexCompleted,
    required this.manualIndexTotal,
    required this.manualIndexCurrentTitle,
  });

  final String statusLabel;
  final String helperText;
  final bool disableActions;
  final VoidCallback onManageStorage;
  final VoidCallback onIndexNewChangedBooks;
  final VoidCallback onRefreshStatus;
  final bool manualIndexing;
  final String? manualIndexStatus;
  final int manualIndexCompleted;
  final int manualIndexTotal;
  final String? manualIndexCurrentTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Library Storage', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              statusLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              helperText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: disableActions ? null : onManageStorage,
                  child: const Text('Manage Storage'),
                ),
                OutlinedButton(
                  onPressed: disableActions ? null : onIndexNewChangedBooks,
                  child: Text(
                    manualIndexing
                        ? 'Indexing new/changed books...'
                        : 'Index New/Changed Books',
                  ),
                ),
                OutlinedButton(
                  onPressed: disableActions ? null : onRefreshStatus,
                  child: const Text('Refresh Status'),
                ),
              ],
            ),
            if (manualIndexing) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: manualIndexTotal > 0
                    ? manualIndexCompleted / manualIndexTotal
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                manualIndexTotal > 0
                    ? 'Indexing $manualIndexCompleted of $manualIndexTotal'
                    : 'Indexing new/changed books...',
              ),
              if (manualIndexCurrentTitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Current: $manualIndexCurrentTitle',
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
            if (manualIndexStatus != null) ...[
              const SizedBox(height: 8),
              Text(manualIndexStatus!),
            ],
          ],
        ),
      ),
    );
  }
}

class CaptureClipperImportsSection extends StatelessWidget {
  const CaptureClipperImportsSection({
    super.key,
    required this.statusLabel,
    required this.helperText,
    required this.disableActions,
    required this.onCheckForNewBooks,
    required this.onImportBookPackage,
    required this.onImportCapturedBooks,
    required this.onChangeImportLocation,
    required this.isIOS,
    this.isAndroid = false,
    this.onDownloadPioneerBooks,
    this.lastCheckedLabel,
  });

  final String statusLabel;
  final String helperText;
  final bool disableActions;
  final VoidCallback onCheckForNewBooks;
  final VoidCallback onImportBookPackage;
  final VoidCallback onImportCapturedBooks;
  final VoidCallback onChangeImportLocation;
  final bool isIOS;
  final bool isAndroid;
  final VoidCallback? onDownloadPioneerBooks;
  final String? lastCheckedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pioneer Books', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              statusLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isIOS
                  ? 'Import the Pioneer Library from a folder you already have, or choose a book package from OneDrive, iCloud Drive, or another Files location. StudyBible copies it locally so it remains available offline.'
                  : isAndroid
                  ? 'Import the Pioneer Library from a folder you already have, or choose Pioneers.studycollection or a .studybook package from Files or cloud storage. Imported packages are copied into StudyBible2 storage.'
                  : 'Import the Pioneer Library from a folder you already have, or choose Pioneers.studycollection from the Collections folder in your cloud storage. StudyBible2 shows what will change before importing.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (lastCheckedLabel != null) ...[
              const SizedBox(height: 8),
              Text(lastCheckedLabel!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (isIOS) ...[
                  FilledButton.icon(
                    onPressed: disableActions ? null : onDownloadPioneerBooks,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Import Pioneer Library'),
                  ),
                  OutlinedButton(
                    onPressed: disableActions ? null : onImportBookPackage,
                    child: const Text('Import StudyBible Book'),
                  ),
                  OutlinedButton(
                    onPressed: disableActions ? null : onImportCapturedBooks,
                    child: const Text('Import CaptureClipper Files'),
                  ),
                ] else if (isAndroid) ...[
                  FilledButton.icon(
                    onPressed: disableActions ? null : onDownloadPioneerBooks,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Import Pioneer Library'),
                  ),
                  OutlinedButton(
                    onPressed: disableActions ? null : onCheckForNewBooks,
                    child: const Text('Import Pioneer Collection'),
                  ),
                  OutlinedButton(
                    onPressed: disableActions ? null : onImportBookPackage,
                    child: const Text('Import One Pioneer Book'),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed: disableActions ? null : onCheckForNewBooks,
                    child: const Text('Check for New Books'),
                  ),
                  OutlinedButton.icon(
                    onPressed: disableActions ? null : onDownloadPioneerBooks,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Import Pioneer Library'),
                  ),
                  OutlinedButton(
                    onPressed: disableActions ? null : onImportBookPackage,
                    child: const Text('Import One Book Package'),
                  ),
                  OutlinedButton(
                    onPressed: disableActions ? null : onChangeImportLocation,
                    child: const Text('Choose CloudFiles Folder'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ELibrarySetupAdvancedSection extends StatelessWidget {
  const ELibrarySetupAdvancedSection({
    super.key,
    required this.selection,
    required this.captureFolderPath,
    required this.captureFolderAccess,
    required this.captureFolderStatus,
    required this.captureImportReport,
    required this.loadingCaptureFolder,
    required this.loadingCaptureImportAvailability,
    required this.storagePolicyLabel,
    required this.onImportConfiguredFolder,
    required this.onResetImportLocation,
    required this.onRepairBrokenItems,
    required this.onReviewImports,
    required this.onClearImportLocation,
    required this.onTestBroadAnyFilePicker,
    required this.onPickScannedHtmlFile,
    required this.setupReportPath,
    required this.indexReportPath,
    required this.storageMaintenanceWidget,
    required this.isIOS,
  });

  final LibraryRootSelection? selection;
  final String? captureFolderPath;
  final String? captureFolderAccess;
  final String? captureFolderStatus;
  final PioneerCapturedHtmlAvailableImportReport? captureImportReport;
  final bool loadingCaptureFolder;
  final bool loadingCaptureImportAvailability;
  final String storagePolicyLabel;
  final VoidCallback onImportConfiguredFolder;
  final VoidCallback onResetImportLocation;
  final VoidCallback onRepairBrokenItems;
  final VoidCallback onReviewImports;
  final VoidCallback onClearImportLocation;
  final VoidCallback onTestBroadAnyFilePicker;
  final VoidCallback onPickScannedHtmlFile;
  final String? setupReportPath;
  final String? indexReportPath;
  final Widget storageMaintenanceWidget;
  final bool isIOS;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rootPath = selection?.path?.trim();
    final rootAccess = selection?.bookmark?.trim();
    final captureReadyCount = captureImportReport?.availableCount ?? 0;
    Widget sectionHeading(String title) {
      return Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      );
    }

    Widget detailField(String label, String? value) {
      final normalizedValue = value?.trim().isNotEmpty == true
          ? value!.trim()
          : '(not set)';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              normalizedValue,
              textAlign: TextAlign.left,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return Card(
      child: ExpansionTile(
        title: Text(
          'Advanced',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          'Technical details and troubleshooting only',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const SizedBox(height: 8),
          sectionHeading('Library Diagnostics'),
          const SizedBox(height: 6),
          detailField('Library path', rootPath),
          detailField('Root source', selection?.sourceLabel),
          detailField('Root state', selection?.statusLabel),
          detailField(
            'Access status',
            rootAccess == null || rootAccess.isEmpty
                ? 'No bookmark saved'
                : 'Bookmark saved',
          ),
          detailField('Cleanup policy', storagePolicyLabel),
          const SizedBox(height: 12),
          sectionHeading('CaptureClipper Diagnostics'),
          const SizedBox(height: 6),
          if (!isIOS) detailField('Import path', captureFolderPath),
          if (!isIOS) detailField('Folder access', captureFolderAccess),
          detailField('Import folder status', captureFolderStatus),
          detailField(
            'Available imports',
            loadingCaptureImportAvailability
                ? 'Loading...'
                : captureImportReport == null
                ? 'No availability report'
                : '$captureReadyCount ready folder(s)',
          ),
          const SizedBox(height: 12),
          sectionHeading('Maintenance'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              if (!isIOS)
                CaptureClipperImportButton(
                  label: captureReadyCount > 0 ? 'Import Ready Books' : null,
                  busy: loadingCaptureFolder,
                  onPressed: onImportConfiguredFolder,
                ),
              if (!isIOS)
                OutlinedButton(
                  onPressed: loadingCaptureFolder
                      ? null
                      : onResetImportLocation,
                  child: const Text('Reset Import Location'),
                ),
              OutlinedButton(
                onPressed: loadingCaptureFolder ? null : onRepairBrokenItems,
                child: const Text('Repair Broken CaptureClipper Items'),
              ),
              if (!isIOS)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton(
                      onPressed: loadingCaptureFolder
                          ? null
                          : onClearImportLocation,
                      child: const Text('Clear Saved Import Location'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Forgets the saved import location. It does not delete source files.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              TextButton(
                onPressed: loadingCaptureFolder ? null : onReviewImports,
                child: const Text('Review Imports'),
              ),
            ],
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 6),
            sectionHeading('Developer Tools'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (!isIOS)
                  OutlinedButton(
                    onPressed: loadingCaptureFolder
                        ? null
                        : onTestBroadAnyFilePicker,
                    child: const Text('Test Broad Any File Picker'),
                  ),
                if (!isIOS)
                  OutlinedButton(
                    onPressed: loadingCaptureFolder
                        ? null
                        : onPickScannedHtmlFile,
                    child: const Text('Pick Scanned HTML File'),
                  ),
              ],
            ),
          ],
          if (setupReportPath != null || indexReportPath != null) ...[
            const SizedBox(height: 8),
            sectionHeading('Diagnostic Reports'),
            const SizedBox(height: 6),
            if (setupReportPath != null) SelectableText(setupReportPath!),
            if (indexReportPath != null) ...[
              const SizedBox(height: 6),
              SelectableText(indexReportPath!),
            ],
          ],
          const SizedBox(height: 16),
          storageMaintenanceWidget,
          const SizedBox(height: 16),
          sectionHeading('Folder Layout'),
          const SizedBox(height: 6),
          detailField('EGW EPUBs', 'LibraryRoot/ePubs/EGW/'),
          detailField('EGW PDFs', 'LibraryRoot/PDFs/EGW/'),
          Text(
            'The setup screen uses the simplified EGW folder layout.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

const _installCollectionsDisclosureText =
    'Books are downloaded directly from the official EGW Writings website into your eLibrary. Please follow the source website\'s terms and do not redistribute downloaded files.';

const _collectionTitles = <String>[
  'EGW Books',
  'EGW Devotionals',
  'EGW Commentaries',
  'EGW Miscellaneous',
  'EGW Pamphlets',
  'EGW Periodicals',
  'EGW Manuscript Releases',
];

bool _isMeaningfulCollectionEstimateText(String text) {
  final normalized = text.trim();
  return normalized.isNotEmpty &&
      normalized != '0 files found • size unknown' &&
      normalized != 'file count not cached yet • size unknown';
}

String _displaySelectedDownloadSummary(String summary) {
  if (summary == 'Selected download: 0 files found • size unknown' ||
      summary ==
          'Selected download: file count not cached yet • size unknown') {
    return 'No collections selected';
  }
  return summary;
}

class ELibraryInstallCollectionsSection extends StatelessWidget {
  const ELibraryInstallCollectionsSection({
    super.key,
    required this.running,
    required this.selectionWarning,
    required this.installBooks,
    required this.installDevotionals,
    required this.installCommentaries,
    required this.installMiscCollections,
    required this.installPamphlets,
    required this.installPeriodicals,
    required this.installManuscriptReleases,
    required this.installEpub,
    required this.installPdf,
    required this.collectionEstimateLines,
    required this.selectedDownloadSummary,
    required this.onSelectAllCollectionsAndFormats,
    required this.onClearAllSelections,
    required this.onSetPresetEpubOnly,
    required this.onSetPresetPdfOnly,
    required this.onSetPresetBoth,
    required this.onStartSetup,
    required this.onCancel,
    required this.onBooksChanged,
    required this.onDevotionalsChanged,
    required this.onCommentariesChanged,
    required this.onMiscCollectionsChanged,
    required this.onPamphletsChanged,
    required this.onPeriodicalsChanged,
    required this.onManuscriptReleasesChanged,
    required this.onEpubChanged,
    required this.onPdfChanged,
  });

  final bool running;
  final String? selectionWarning;
  final bool installBooks;
  final bool installDevotionals;
  final bool installCommentaries;
  final bool installMiscCollections;
  final bool installPamphlets;
  final bool installPeriodicals;
  final bool installManuscriptReleases;
  final bool installEpub;
  final bool installPdf;
  final List<String> collectionEstimateLines;
  final String selectedDownloadSummary;
  final VoidCallback onSelectAllCollectionsAndFormats;
  final VoidCallback onClearAllSelections;
  final VoidCallback onSetPresetEpubOnly;
  final VoidCallback onSetPresetPdfOnly;
  final VoidCallback onSetPresetBoth;
  final VoidCallback onStartSetup;
  final VoidCallback onCancel;
  final ValueChanged<bool?> onBooksChanged;
  final ValueChanged<bool?> onDevotionalsChanged;
  final ValueChanged<bool?> onCommentariesChanged;
  final ValueChanged<bool?> onMiscCollectionsChanged;
  final ValueChanged<bool?> onPamphletsChanged;
  final ValueChanged<bool?> onPeriodicalsChanged;
  final ValueChanged<bool?> onManuscriptReleasesChanged;
  final ValueChanged<bool?> onEpubChanged;
  final ValueChanged<bool?> onPdfChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String estimateLine(int index) => collectionEstimateLines[index];
    String collectionTitle(int index) => _collectionTitles[index];
    String? collectionEstimateText(int index) {
      final estimate = estimateLine(index);
      return _isMeaningfulCollectionEstimateText(estimate) ? estimate : null;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Install eLibrary Collections',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Choose your eLibrary collections and formats, then use Install Selected to begin. The selection buttons only change checkmarks; they do not start a download.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionChip(
                  label: const Text('Select All Collections + All File Types'),
                  onPressed: running ? null : onSelectAllCollectionsAndFormats,
                ),
                ActionChip(
                  label: const Text('Clear All'),
                  onPressed: running ? null : onClearAllSelections,
                ),
                ActionChip(
                  label: const Text('EPUB Only'),
                  onPressed: running ? null : onSetPresetEpubOnly,
                ),
                ActionChip(
                  label: const Text('PDF Only'),
                  onPressed: running ? null : onSetPresetPdfOnly,
                ),
                ActionChip(
                  label: const Text('EPUB + PDF'),
                  onPressed: running ? null : onSetPresetBoth,
                ),
              ],
            ),
            if (selectionWarning != null) ...[
              const SizedBox(height: 12),
              Text(
                selectionWarning!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.trailing,
              value: installBooks,
              onChanged: running ? null : onBooksChanged,
              title: Text(collectionTitle(0)),
              subtitle: collectionEstimateText(0) == null
                  ? null
                  : Text(
                      collectionEstimateText(0)!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.trailing,
              value: installDevotionals,
              onChanged: running ? null : onDevotionalsChanged,
              title: Text(collectionTitle(1)),
              subtitle: collectionEstimateText(1) == null
                  ? null
                  : Text(
                      collectionEstimateText(1)!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.trailing,
              value: installCommentaries,
              onChanged: running ? null : onCommentariesChanged,
              title: Text(collectionTitle(2)),
              subtitle: collectionEstimateText(2) == null
                  ? null
                  : Text(
                      collectionEstimateText(2)!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.trailing,
              value: installMiscCollections,
              onChanged: running ? null : onMiscCollectionsChanged,
              title: Text(collectionTitle(3)),
              subtitle: collectionEstimateText(3) == null
                  ? null
                  : Text(
                      collectionEstimateText(3)!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.trailing,
              value: installPamphlets,
              onChanged: running ? null : onPamphletsChanged,
              title: Text(collectionTitle(4)),
              subtitle: collectionEstimateText(4) == null
                  ? null
                  : Text(
                      collectionEstimateText(4)!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.trailing,
              value: installPeriodicals,
              onChanged: running ? null : onPeriodicalsChanged,
              title: Text(collectionTitle(5)),
              subtitle: collectionEstimateText(5) == null
                  ? null
                  : Text(
                      collectionEstimateText(5)!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.trailing,
              value: installManuscriptReleases,
              onChanged: running ? null : onManuscriptReleasesChanged,
              title: Text(collectionTitle(6)),
              subtitle: collectionEstimateText(6) == null
                  ? null
                  : Text(
                      collectionEstimateText(6)!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Text(
              _displaySelectedDownloadSummary(selectedDownloadSummary),
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Divider(height: 24),
            CheckboxListTile(
              value: installEpub,
              onChanged: running ? null : onEpubChanged,
              title: const Text('EPUB'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: installPdf,
              onChanged: running ? null : onPdfChanged,
              title: const Text('PDF'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Text(
              _installCollectionsDisclosureText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: running ? null : onStartSetup,
                  child: const Text('Install Selected'),
                ),
                OutlinedButton(
                  onPressed: running ? onCancel : null,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DownloadedFileMaintenanceSection extends StatelessWidget {
  const DownloadedFileMaintenanceSection({
    super.key,
    required this.loadingStorageSummary,
    required this.storageSummary,
    required this.running,
    required this.removingFiles,
    required this.canRemoveFiles,
    required this.onRemoveSelected,
    required this.onRemoveEpubs,
    required this.onRemovePdfs,
    required this.onRemoveAll,
  });

  final bool loadingStorageSummary;
  final ELibraryStorageSummary? storageSummary;
  final bool running;
  final bool removingFiles;
  final bool canRemoveFiles;
  final VoidCallback onRemoveSelected;
  final VoidCallback onRemoveEpubs;
  final VoidCallback onRemovePdfs;
  final VoidCallback onRemoveAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloaded File Maintenance',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Review or remove downloaded eLibrary files. Your tags, notes, highlights, bookmarks, and saved presentations are not removed.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (loadingStorageSummary)
              const LinearProgressIndicator()
            else if (storageSummary != null) ...[
              Text(
                'Downloaded library files: '
                '${storageSummary!.epubCount} EPUB '
                '(${formatELibraryBytes(storageSummary!.epubSizeBytes)}), '
                '${storageSummary!.pdfCount} PDF '
                '(${formatELibraryBytes(storageSummary!.pdfSizeBytes)}), '
                'total ${storageSummary!.totalCount} files '
                '(${formatELibraryBytes(storageSummary!.totalSizeBytes)}).',
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: (running || removingFiles || !canRemoveFiles)
                      ? null
                      : onRemoveSelected,
                  child: const Text('Remove Selected'),
                ),
                OutlinedButton(
                  onPressed: (running || removingFiles || !canRemoveFiles)
                      ? null
                      : onRemoveEpubs,
                  child: const Text('Remove EPUBs'),
                ),
                OutlinedButton(
                  onPressed: (running || removingFiles || !canRemoveFiles)
                      ? null
                      : onRemovePdfs,
                  child: const Text('Remove PDFs'),
                ),
                FilledButton.tonal(
                  onPressed: (running || removingFiles || !canRemoveFiles)
                      ? null
                      : onRemoveAll,
                  child: const Text('Remove All Downloaded Library Files'),
                ),
              ],
            ),
            if (removingFiles) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class ELibrarySetupScreen extends StatefulWidget {
  const ELibrarySetupScreen({super.key});

  @override
  State<ELibrarySetupScreen> createState() => _ELibrarySetupScreenState();
}

class _ELibrarySetupScreenState extends State<ELibrarySetupScreen> {
  LibraryRootSelection? _selection;
  bool _loading = true;
  bool _loadingStorageSummary = true;
  bool _running = false;
  bool _indexing = false;
  bool _removingFiles = false;
  bool _cancelRequested = false;
  bool _installBooks = false;
  bool _installDevotionals = false;
  bool _installCommentaries = false;
  bool _installMiscCollections = false;
  bool _installPamphlets = false;
  bool _installPeriodicals = false;
  bool _installManuscriptReleases = false;
  bool _installEpub = false;
  bool _installPdf = false;
  bool _refreshingEstimateCache = false;
  bool _loadingCaptureFolder = true;
  bool _loadingCaptureImportAvailability = true;
  bool _captureFolderBusy = false;
  bool _captureFolderIsLegacy = false;
  ELibraryStoragePolicy _storagePolicy = ELibraryStoragePolicy.saveSpace;
  Map<String, Map<String, ELibraryInstallEstimateRecord>>
  _estimateCacheByCollection =
      <String, Map<String, ELibraryInstallEstimateRecord>>{};
  ELibraryDownloadProgress? _progress;
  ELibraryDownloadReport? _downloadReport;
  LegacyELibraryMigrationReport? _migrationReport;
  ELibraryDuplicateCleanupReport? _cleanupReport;
  String? _setupReportPath;
  String? _indexReportPath;
  String? _setupStatusMessage;
  String? _selectionWarning;
  ELibraryStorageSummary? _storageSummary;
  String? _error;
  String? _errorDetails;
  int _indexedCount = 0;
  int _indexingErrors = 0;
  bool _manualIndexing = false;
  Future<({int indexed, int skipped, int failed})>? _manualIndexFuture;
  String? _manualIndexStatus;
  int _manualIndexCompleted = 0;
  int _manualIndexTotal = 0;
  String? _manualIndexCurrentTitle;
  String? _captureFolderPath;
  String? _captureFolderAccess;
  String? _captureFolderStatus;
  String? _lastCollectionCheckLabel;
  PioneerCapturedHtmlAvailableImportReport? _captureImportReport;
  int _pendingIndexCount = 0;
  List<LibraryNeedsAttentionEntry> _needsAttentionItems =
      const <LibraryNeedsAttentionEntry>[];
  final LibraryIndexingPromptGate _indexPromptGate =
      LibraryIndexingPromptGate();

  @override
  void initState() {
    super.initState();
    _load();
    _loadEstimateCache();
    _loadCaptureFolderState();
    _loadCollectionCheckMetadata();
    _refreshPendingIndexCount(promptIfNeeded: true);
    _refreshNeedsAttentionItems();
  }

  Future<void> _loadCollectionCheckMetadata() async {
    final data = await LocalSettingsStore.instance.loadPioneerCollectionCheck();
    if (!mounted || data.isEmpty) return;
    final title = data['title']?.trim().isNotEmpty == true
        ? data['title']!.trim()
        : 'Pioneers';
    final checked = DateTime.tryParse(data['checkedAt'] ?? '');
    final when =
        checked != null &&
            DateTime.now().difference(checked.toLocal()).inDays == 0
        ? 'Today'
        : 'Previously';
    setState(() => _lastCollectionCheckLabel = 'Last checked:\n$title\n$when');
  }

  @override
  void dispose() {
    _cancelRequested = true;
    super.dispose();
  }

  Future<void> _load() async {
    final selection = await LibraryRootService.instance.loadSelection();
    final storagePolicy = await LocalSettingsStore.instance
        .loadELibraryStoragePolicy();
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _storagePolicy = storagePolicy;
      _loading = false;
    });
    await _loadStorageSummary();
  }

  Future<void> _loadStorageSummary() async {
    if (!mounted) return;
    setState(() => _loadingStorageSummary = true);
    try {
      final summary = await ELibraryFileManagementService.instance
          .computeDownloadedStorageSummary(rootPath: _selection?.path);
      if (!mounted) return;
      setState(() => _storageSummary = summary);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _storageSummary = const ELibraryStorageSummary(
          epubCount: 0,
          epubSizeBytes: 0,
          pdfCount: 0,
          pdfSizeBytes: 0,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loadingStorageSummary = false);
      }
    }
  }

  Future<void> _loadEstimateCache() async {
    try {
      final cache = await ELibraryInstallEstimateRepository.instance
          .loadByCollectionAndFormat();
      if (!mounted) {
        return;
      }
      setState(() {
        _estimateCacheByCollection = cache;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _estimateCacheByCollection =
            <String, Map<String, ELibraryInstallEstimateRecord>>{};
      });
    }
  }

  Future<void> _loadCaptureFolderState() async {
    setState(() => _loadingCaptureFolder = true);
    try {
      final path = await LocalSettingsStore.instance
          .loadPioneerCapturedHtmlFolderPath();
      final bookmark = await LocalSettingsStore.instance
          .loadPioneerCapturedHtmlFolderBookmark();
      final defaultAppRoot = await LibraryRootService.instance
          .defaultAppLibraryRootPath();
      final isLegacy =
          path != null &&
          LibraryRootService.isDefaultAppDocumentsPath(
            candidatePath: path,
            defaultAppRootPath: defaultAppRoot,
          );
      if (!mounted) return;
      setState(() {
        _captureFolderPath = path;
        _captureFolderIsLegacy = isLegacy;
        _captureFolderAccess = path == null
            ? null
            : bookmark == null
            ? 'Not saved'
            : 'Saved';
        _captureFolderStatus = path == null
            ? 'No CloudFiles folder configured.'
            : isLegacy
            ? 'Legacy app Documents folder detected. Choose the OneDrive/CloudFiles folder.'
            : 'CloudFiles folder ready: ${p.basename(path)}';
      });
      await _loadCaptureImportAvailability();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _captureFolderPath = null;
        _captureFolderAccess = null;
        _captureFolderIsLegacy = false;
        _captureFolderStatus = 'Failed to load CloudFiles folder: $error';
        _captureImportReport = null;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingCaptureFolder = false);
      }
    }
  }

  Future<void> _refreshPendingIndexCount({bool promptIfNeeded = false}) async {
    int count;
    try {
      count = await LibraryCatalogService.instance.countUnindexedManagedItems();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _pendingIndexCount = count);
    if (promptIfNeeded) {
      await _maybeShowIndexingPrompt();
    }
  }

  Future<void> _refreshNeedsAttentionItems() async {
    List<LibraryCatalogItem> items;
    try {
      items = await LibraryCatalogService.instance
          .listNeedsAttentionManagedItems();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _needsAttentionItems = items
          .map(
            (item) => LibraryNeedsAttentionEntry(
              title: item.displayTitle,
              fileName: item.fileName,
              reason: item.indexError,
            ),
          )
          .toList(growable: false);
    });
  }

  Future<void> _maybeShowIndexingPrompt() async {
    if (!mounted || !_indexPromptGate.shouldPrompt(_pendingIndexCount)) {
      return;
    }
    final action = await showLibraryIndexingPromptDialog(
      context,
      pendingCount: _pendingIndexCount,
    );
    if (!mounted || action != LibraryIndexingPromptAction.indexNow) {
      return;
    }
    await _runManualIndex();
  }

  Future<void> _loadCaptureImportAvailability() async {
    if (!mounted) return;
    setState(() => _loadingCaptureImportAvailability = true);
    try {
      final report = await PioneerCapturedHtmlImportAvailabilityService.instance
          .refresh();
      if (!mounted) return;
      setState(() => _captureImportReport = report);
    } catch (_) {
      if (!mounted) return;
      setState(() => _captureImportReport = null);
    } finally {
      if (mounted) {
        setState(() => _loadingCaptureImportAvailability = false);
      }
    }
  }

  Future<void> _chooseCaptureFolder({bool resetFirst = false}) async {
    if (_captureFolderBusy) return;
    setState(() => _captureFolderBusy = true);
    try {
      if (resetFirst) {
        debugPrint('CloudFiles folder reset requested before picker open.');
        await LocalSettingsStore.instance.clearPioneerCapturedHtmlFolder();
        await _loadCaptureFolderState();
      }
      debugPrint('Requesting native CloudFiles folder picker.');
      final result = await LibraryRootNative.pickFolder();
      if (result == null) {
        debugPrint('CloudFiles folder picker cancelled or unavailable.');
        if (resetFirst) {
          if (!mounted) return;
          setState(() {
            _captureFolderStatus =
                'CloudFiles folder cleared. Picker cancelled.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CloudFiles folder picker cancelled.'),
            ),
          );
        }
        return;
      }
      final defaultAppRoot = await LibraryRootService.instance
          .defaultAppLibraryRootPath();
      final isLegacy = LibraryRootService.isDefaultAppDocumentsPath(
        candidatePath: result.path,
        defaultAppRootPath: defaultAppRoot,
      );
      if (isLegacy) {
        debugPrint(
          'Rejected CloudFiles folder selection because it points at the app Documents folder: ${result.path}',
        );
        if (!mounted) return;
        setState(() {
          _captureFolderIsLegacy = true;
          _captureFolderStatus =
              'The app Documents folder cannot be used as the CloudFiles folder.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The app Documents folder cannot be used as the CloudFiles folder.',
            ),
          ),
        );
        return;
      }
      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: result.path,
        bookmark: result.bookmark,
      );
      await _loadCaptureFolderState();
      if (!mounted) return;
      final folderName = p.basename(result.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CloudFiles folder saved: $folderName')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = 'CloudFiles folder picker failed: $error';
      setState(() => _captureFolderStatus = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  Future<void> _pickScannedHtmlFile() async {
    if (_captureFolderBusy) return;
    setState(() => _captureFolderBusy = true);
    try {
      debugPrint('Requesting native CloudFiles scanned HTML file picker.');
      final result = await LibraryRootNative.pickScannedHtmlFile();
      if (result == null) {
        debugPrint(
          'CloudFiles scanned HTML file picker cancelled or unavailable.',
        );
        return;
      }
      final defaultAppRoot = await LibraryRootService.instance
          .defaultAppLibraryRootPath();
      final isLegacy = LibraryRootService.isDefaultAppDocumentsPath(
        candidatePath: result.path,
        defaultAppRootPath: defaultAppRoot,
      );
      if (isLegacy) {
        debugPrint(
          'Rejected CloudFiles scanned HTML file selection because it points at the app Documents folder: ${result.path}',
        );
        if (!mounted) return;
        setState(() {
          _captureFolderIsLegacy = true;
          _captureFolderStatus =
              'The app Documents folder cannot be used as the CloudFiles folder.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The app Documents folder cannot be used as the CloudFiles folder.',
            ),
          ),
        );
        return;
      }
      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: result.path,
        bookmark: result.bookmark,
      );
      await _loadCaptureFolderState();
      if (!mounted) return;
      final folderName = p.basename(result.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CloudFiles folder saved from HTML file: $folderName'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      const message =
          'OneDrive did not grant folder access. This is a OneDrive limitation. Use "Import Captured Books" to copy the files into StudyBible2 app storage instead.';
      debugPrint('CloudFiles scanned HTML file picker failed: $error');
      setState(() => _captureFolderStatus = '$message\n\n$error');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$message $error')));
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  Future<void> _checkForNewBooks({String? selectedPath}) async {
    if (_captureFolderBusy && selectedPath == null) return;
    setState(() => _captureFolderBusy = true);
    try {
      String? path = selectedPath;
      while (path == null) {
        try {
          path = await LibraryRootNative.pickStudyCollection();
        } on FormatException {
          if (!mounted || !await _showWrongCollectionFileDialog()) return;
        }
        if (path == null) break;
      }
      if (path == null) {
        debugPrint('CaptureClipper book package picker cancelled.');
        if (!mounted) return;
        setState(() {
          _captureFolderStatus = 'No Pioneer file was selected.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Pioneer file was selected.')),
        );
        return;
      }
      final results = <PioneerBookPackageImportResult>[];
      final failures = <String>[];
      var selectedNew = 0;
      var selectedUpdates = 0;
      var alreadyCurrent = 0;
      var directlyImported = 0;
      for (final path in [path]) {
        try {
          if (p.extension(path).toLowerCase() == '.studycollection') {
            final service = const PioneerStudyCollectionService();
            final inventory = await service.compareWithLocal(
              await service.inspect(path),
            );
            await LocalSettingsStore.instance.savePioneerCollectionCheck(
              filename: p.basename(path),
              collectionId: inventory.collectionId,
              title: inventory.collectionId,
              checkedAt: DateTime.now(),
            );
            if (mounted) {
              setState(
                () => _lastCollectionCheckLabel =
                    'Last checked:\n${inventory.collectionId}\nToday',
              );
            }
            if (!mounted) return;
            final selected = await showStudyCollectionImportDialog(
              context,
              inventory,
            );
            if (selected == null || selected.isEmpty) continue;
            selectedNew += inventory.books
                .where(
                  (book) =>
                      selected.contains(book.workId) &&
                      book.status == StudyCollectionBookStatus.newBook,
                )
                .length;
            selectedUpdates += inventory.books
                .where(
                  (book) =>
                      selected.contains(book.workId) &&
                      book.status == StudyCollectionBookStatus.update,
                )
                .length;
            alreadyCurrent += inventory.books
                .where(
                  (book) => book.status == StudyCollectionBookStatus.current,
                )
                .length;
            final batch = await service.importSelectedItems(path, selected);
            results.addAll(batch.studybookResults);
            directlyImported +=
                batch.epubResults.where((result) => result.isImported).length +
                batch.pdfWorkIds.length;
          }
        } catch (error) {
          failures.add('${p.basename(path)}: $error');
        }
      }
      final importReport = results.isEmpty
          ? null
          : await PioneerCapturedHtmlImportFolderService.instance
                .importConfiguredCloudFolder(
                  selectedFolderPaths: results.map(
                    (result) => result.destinationFolderPath,
                  ),
                );
      if (!mounted) return;
      final importedCount =
          (importReport?.importedCount ?? 0) + directlyImported;
      final message = failures.isEmpty
          ? selectedNew + selectedUpdates > 0
                ? '${selectedNew == 0 ? '' : '$selectedNew new book${selectedNew == 1 ? '' : 's'} imported\n'}${selectedUpdates == 0 ? '' : '$selectedUpdates book${selectedUpdates == 1 ? '' : 's'} updated\n'}$alreadyCurrent already current'
                : 'Imported and indexed $importedCount book${importedCount == 1 ? '' : 's'}.'
          : '$importedCount book${importedCount == 1 ? '' : 's'} imported and indexed. ${failures.length} package${failures.length == 1 ? '' : 's'} need attention.\n${failures.join('\n')}';
      final messenger = ScaffoldMessenger.of(context);
      await _loadCaptureFolderState();
      if (!mounted) return;
      setState(() => _captureFolderStatus = message);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      debugPrint('Pioneer collection import failed: $error');
      final message = switch (error) {
        FormatException(:final message) => message,
        PlatformException() =>
          'The selected Pioneer file could not be read. Try choosing it again from Files.',
        _ =>
          'The Pioneer collection could not be imported. The selected collection may be invalid.',
      };
      setState(() => _captureFolderStatus = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  Future<bool> _showWrongCollectionFileDialog() async {
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose the Pioneer collection'),
        content: const Text(
          'That is an individual book package. Choose Pioneers.studycollection to check the full collection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose Again'),
          ),
        ],
      ),
    );
    return action == true;
  }

  Future<void> _importOneBookPackage() async {
    if (_captureFolderBusy) return;
    setState(() => _captureFolderBusy = true);
    try {
      final path = await LibraryRootNative.pickPioneerPackage();
      if (path == null) {
        if (!mounted) return;
        const message = 'No Pioneer file was selected.';
        setState(() => _captureFolderStatus = message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(message)));
        return;
      }
      if (p.extension(path).toLowerCase() == '.studycollection') {
        await _checkForNewBooks(selectedPath: path);
        return;
      }
      if (p.extension(path).toLowerCase() == '.epub') {
        final catalog = await PioneerSourceCatalog.load();
        final work =
            matchPioneerWorkForLocalEpub(catalog, path) ??
            await loadPioneerWorkFromFolderFile(path);
        if (work == null) {
          throw PioneerBookPackageImportException(
            'The selected EPUB could not be matched to a Pioneer catalog '
            'title and was not discovered in the Pioneers source folder.',
          );
        }
        final importResult = await PioneerTextImportService.instance
            .importLocalEpubFile(
              work: work,
              filePath: path,
              overwriteExisting: true,
            );
        final importedItem = await LibraryCatalogService.instance.loadItemById(
          importResult.libraryItemId,
        );
        if (importedItem == null) {
          throw PioneerBookPackageImportException(
            '${p.basename(path)} was parsed, but its library item could not '
            'be refreshed.',
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported “${importedItem.displayTitle}”.')),
        );
        await _loadCaptureFolderState();
        return;
      }
      final result = await PioneerBookPackageImportService.instance
          .importPackage(path, setAsConfiguredFolder: false);
      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder(
            selectedFolderPaths: [result.destinationFolderPath],
            existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
          );
      late final String libraryItemId;
      late final String importedTitle;
      if (report.entries.isNotEmpty) {
        final entry = report.entries.firstWhere(
          (entry) =>
              p.normalize(entry.folderPath).toLowerCase() ==
              p.normalize(result.destinationFolderPath).toLowerCase(),
          orElse: () => report.entries.first,
        );
        if (!entry.imported || entry.libraryItemId?.trim().isEmpty != false) {
          throw PioneerBookPackageImportException(
            '${p.basename(path)} could not be added to the library: '
            '${entry.reason?.trim().isNotEmpty == true ? entry.reason : 'the importer did not create a library item.'}',
          );
        }
        libraryItemId = entry.libraryItemId!.trim();
        importedTitle = entry.title;
      } else {
        // Some valid recovered packages contain ordinary chapter/paragraph
        // HTML rather than EGW-style paragraph reference codes. The
        // reference-preserving CaptureClipper scanner intentionally rejects
        // those files, so fall back to the general captured-HTML importer
        // after the package manifest and declared HTML file have already been
        // validated by PioneerBookPackageImportService.
        final fallbackReport = await PioneerCapturedHtmlImportFolderService
            .instance
            .scanFolder(
              folderPath: result.destinationFolderPath,
              importFiles: true,
              existingImportPolicy:
                  PioneerExistingImportPolicy.overwriteExisting,
            );
        final candidates = fallbackReport.files
            .where((file) => file.libraryItemId?.trim().isNotEmpty == true)
            .toList(growable: false);
        if (candidates.isEmpty) {
          final reason = fallbackReport.files
              .map((file) => file.reason?.trim() ?? '')
              .where((value) => value.isNotEmpty)
              .join(' ');
          throw PioneerBookPackageImportException(
            '${p.basename(path)} was extracted, but its HTML could not be '
            'added to the library'
            '${reason.isEmpty ? '.' : ': $reason'}',
          );
        }
        final entry = candidates.first;
        libraryItemId = entry.libraryItemId!.trim();
        importedTitle = entry.title;
      }
      final importedItem = await LibraryCatalogService.instance.loadItemById(
        libraryItemId,
      );
      if (importedItem == null) {
        throw PioneerBookPackageImportException(
          '${p.basename(path)} reported success, but its library item could '
          'not be refreshed.',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imported “$importedTitle”.')));
      await _loadCaptureFolderState();
    } catch (error) {
      if (!mounted) return;
      debugPrint('Pioneer book package import failed: $error');
      final message = switch (error) {
        FormatException(:final message) => message,
        PlatformException(:final message, :final details) =>
          'The selected Pioneer file could not be read'
              '${message != null && message.isNotEmpty ? ': $message' : ''}'
              '${details != null && details.toString().isNotEmpty ? ' ($details)' : ''}.',
        PioneerBookPackageImportException(:final message) => message,
        _ => 'The Pioneer book could not be imported.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _captureFolderBusy = false);
    }
  }

  Future<void> _testBroadAnyFilePicker() async {
    if (_captureFolderBusy) return;
    setState(() => _captureFolderBusy = true);
    try {
      final pickedPaths = await LibraryRootNative.pickImportFiles(
        kind: 'package',
      );
      if (!mounted) return;
      if (pickedPaths == null || pickedPaths.isEmpty) {
        const message =
            'Broad picker test: selection cancelled or no file returned. '
            'Nothing was imported.';
        setState(() => _captureFolderStatus = message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(message)));
        return;
      }
      final pickedPath = pickedPaths.first;
      final message =
          'Broad picker test selected: ${p.basename(pickedPath)}\n'
          'Path: $pickedPath\n'
          'Nothing was imported.';
      setState(() => _captureFolderStatus = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      final message = 'Broad picker test failed: $error';
      setState(() => _captureFolderStatus = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  // Retained for reusable non-iOS/manual file workflows outside the normal card.
  // ignore: unused_element
  Future<void> _importPickedCaptureClipperFiles({
    bool relatedFilesOnly = false,
  }) async {
    if (_captureFolderBusy) return;
    setState(() => _captureFolderBusy = true);
    try {
      if (!relatedFilesOnly) {
        final pickedFolders = await LibraryRootNative.pickImportFolders();
        if (pickedFolders == null || pickedFolders.isEmpty) return;
        final service = PioneerCapturedHtmlImportFolderService.instance;
        final copyResult = await service
            .copyPickedBooksParentIntoManagedImportFolder(pickedFolders.single);
        final report = await service.importConfiguredCloudFolder();
        if (!mounted) return;
        final parts = <String>[];
        if (report.importedCount > 0) {
          parts.add('${report.importedCount} new books imported');
        }
        if (report.repairedCount > 0) {
          parts.add('${report.repairedCount} books updated');
        }
        if (report.healthySkippedCount > 0) {
          parts.add('${report.healthySkippedCount} already current');
        }
        if (report.failedCount > 0 || report.invalidCount > 0) {
          parts.add(
            '${report.failedCount + report.invalidCount} need attention',
          );
        }
        if (copyResult.conflictPackageNames.isNotEmpty) {
          parts.add(
            '${copyResult.conflictPackageNames.length} package conflicts need attention',
          );
        }
        if (copyResult.invalidPackageNames.isNotEmpty) {
          parts.add(
            '${copyResult.invalidPackageNames.length} invalid packages need attention',
          );
        }
        final message = parts.isEmpty
            ? 'No CaptureClipper books needed importing.'
            : '${parts.join('. ')}. The OneDrive originals were unchanged.';
        await _loadCaptureFolderState();
        if (!mounted) return;
        setState(() => _captureFolderStatus = message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      final kind = 'assets';
      debugPrint('Requesting CaptureClipper file import picker (kind=$kind).');
      final pickedPaths = await LibraryRootNative.pickImportFiles(kind: kind);
      if (pickedPaths == null || pickedPaths.isEmpty) {
        debugPrint('CaptureClipper file import picker cancelled.');
        if (!mounted) return;
        setState(() {
          _captureFolderStatus =
              'File selection cancelled. Nothing was imported.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File selection cancelled.')),
        );
        return;
      }
      final result = await PioneerCapturedHtmlImportFolderService.instance
          .copyPickedFilesIntoManagedImportFolder(
            pickedPaths,
            setAsConfiguredFolder: false,
          );
      final importReport = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder(
            selectedFolderPaths: [result.destinationFolderPath],
          );
      if (!mounted) return;
      final copied = result.copiedFilePaths.length;
      final failed = result.failedSourcePaths.length;
      final buffer = StringBuffer(
        'Copied $copied file${copied == 1 ? '' : 's'} into app storage and '
        'imported ${importReport.importedCount + importReport.repairedCount} '
        'book${importReport.importedCount + importReport.repairedCount == 1 ? '' : 's'} '
        '(${p.basename(result.destinationFolderPath)}).',
      );
      if (failed > 0) {
        buffer.write(
          ' $failed file${failed == 1 ? '' : 's'} could not be copied.',
        );
      }
      if (result.missingAssetReferences.isNotEmpty) {
        buffer.write(
          ' The HTML file was copied, but iOS did not grant access to '
          'related image/resource files. Use "Add Related Book Files" to '
          'select all related files, or select the full exported book '
          'folder if available.',
        );
      }
      final message = buffer.toString();
      final messenger = ScaffoldMessenger.of(context);
      await _loadCaptureFolderState();
      if (!mounted) return;
      setState(() => _captureFolderStatus = message);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      final message = 'CaptureClipper file import failed: $error';
      debugPrint(message);
      setState(() => _captureFolderStatus = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  Future<void> _clearCaptureFolder() async {
    if (_captureFolderBusy) return;
    setState(() => _captureFolderBusy = true);
    try {
      await LocalSettingsStore.instance.clearPioneerCapturedHtmlFolder();
      await _loadCaptureFolderState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CaptureClipper folder cleared.')),
      );
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  Future<void> _importCaptureFolder({bool repairExistingItems = false}) async {
    if (_captureFolderBusy) return;
    setState(() {
      _captureFolderBusy = true;
      _captureFolderStatus = repairExistingItems
          ? 'Repairing CaptureClipper cloud folders...'
          : 'Scanning CaptureClipper cloud folders...';
    });
    try {
      final report = repairExistingItems
          ? await PioneerCapturedHtmlImportFolderService.instance
                .repairBrokenCaptureClipperItems()
          : await PioneerCapturedHtmlImportFolderService.instance
                .importConfiguredCloudFolder(
                  existingImportPolicy:
                      PioneerExistingImportPolicy.skipExisting,
                );
      if (!mounted) return;
      final summary = report.rootPath.trim().isEmpty
          ? (repairExistingItems
                ? 'Repair attempted on stored CaptureClipper items.'
                : 'No CaptureClipper folder is configured.')
          : 'Imported ${report.importedCount}, repaired ${report.repairedCount}, '
                'skipped ${report.healthySkippedCount}, invalid ${report.invalidCount}, '
                'failed ${report.failedCount}.';
      setState(() => _captureFolderStatus = summary);
      final messenger = ScaffoldMessenger.of(context);
      await _loadCaptureImportAvailability();
      messenger.showSnackBar(SnackBar(content: Text(summary)));
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _captureFolderStatus = 'CaptureClipper import failed: $error',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CaptureClipper import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  Future<void> _reviewCaptureFolderImports() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PioneerCapturedHtmlImportReviewScreen(),
      ),
    );
    if (!mounted) return;
    await _loadCaptureFolderState();
  }

  Future<void> _promptCaptureImports() async {
    final report = _captureImportReport;
    if (report == null || !report.hasAvailableImports) {
      return;
    }

    final selectedImports = await showCaptureClipperImportChooserDialog(
      context,
      report,
    );
    if (!mounted || selectedImports == null || selectedImports.isEmpty) {
      return;
    }

    final result = await PioneerCapturedHtmlImportFolderService.instance
        .importConfiguredCloudFolder(
          selectedFolderPaths: selectedImports.map((item) => item.folderPath),
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _loadCaptureFolderState();
    final imported = result.importedCount;
    final firstEntry = result.entries.isEmpty ? null : result.entries.first;
    final entryLabel = firstEntry == null
        ? 'CaptureClipper'
        : '${firstEntry.folderName} — ${firstEntry.title}';
    final reason = firstEntry?.archiveError?.trim().isNotEmpty == true
        ? firstEntry!.archiveError!.trim()
        : firstEntry?.reason?.trim().isNotEmpty == true
        ? firstEntry!.reason!.trim()
        : null;
    final message = imported == 0
        ? reason == null
              ? 'No CaptureClipper books were imported.'
              : 'No CaptureClipper books were imported. $entryLabel: $reason'
        : 'Imported $imported CaptureClipper book${imported == 1 ? '' : 's'}.';
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshEstimateCache() async {
    if (_refreshingEstimateCache) return;
    setState(() => _refreshingEstimateCache = true);
    try {
      await ELibraryDownloadService.instance
          .refreshProductionCollectionEstimates();
      await _loadStorageSummary();
      await _loadCaptureFolderState();
      await _refreshPendingIndexCount();
      await _refreshNeedsAttentionItems();
      await _loadEstimateCache();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Status refreshed.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Status refresh failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _refreshingEstimateCache = false);
      }
    }
  }

  Future<({int indexed, int skipped, int failed})> _runManualIndex({
    String? rootPathOverride,
  }) async {
    final running = _manualIndexFuture;
    if (running != null) return running;
    final operation = _performManualIndex(rootPathOverride: rootPathOverride);
    _manualIndexFuture = operation;
    try {
      return await operation;
    } finally {
      _manualIndexFuture = null;
    }
  }

  Future<({int indexed, int skipped, int failed})> _performManualIndex({
    String? rootPathOverride,
  }) async {
    setState(() {
      _manualIndexing = true;
      _manualIndexStatus = 'Discovering retained EPUB files...';
      _manualIndexCompleted = 0;
      _manualIndexTotal = 0;
      _manualIndexCurrentTitle = null;
    });
    try {
      final rootPath = rootPathOverride?.trim().isNotEmpty == true
          ? p.normalize(rootPathOverride!.trim())
          : await LibraryRootService.instance.accessibleLibraryRootPath();
      if (rootPath == null || rootPath.trim().isEmpty) {
        setState(() {
          _manualIndexStatus =
              'No files indexed: the app-managed Library Root is unavailable.';
        });
        return (indexed: 0, skipped: 0, failed: 1);
      }
      if (!Directory(rootPath).existsSync()) {
        setState(() {
          _manualIndexStatus =
              'No files indexed: the expected app-managed root is inaccessible.';
        });
        return (indexed: 0, skipped: 0, failed: 1);
      }

      await LibraryCatalogService.instance.refreshManagedItemsFromDisk(
        rootPathOverride: rootPath,
      );
      final candidates = await LibraryCatalogService.instance
          .listUnindexedManagedItems();
      if (!mounted) {
        return (indexed: 0, skipped: 0, failed: 0);
      }
      if (candidates.isEmpty) {
        setState(() {
          _manualIndexStatus =
              'No indexing candidates: all discovered EPUB files are already indexed.';
        });
        await _refreshPendingIndexCount();
        await _refreshNeedsAttentionItems();
        return (indexed: 0, skipped: 0, failed: 0);
      }

      final failures = <String>[];
      setState(() {
        _manualIndexStatus =
            'Indexing ${candidates.length} new/changed books...';
        _manualIndexTotal = candidates.length;
      });
      final result = await CommentaryResearchLibraryService.instance
          .indexLocalCatalogedEpubs(
            rootPathOverride: rootPath,
            onProgress: (completed, total, currentTitle) {
              if (!mounted) return;
              setState(() {
                _manualIndexCompleted = completed;
                _manualIndexTotal = total;
                _manualIndexCurrentTitle = currentTitle;
              });
            },
            onFailure: (fileName, error) {
              failures.add('$fileName: $error');
            },
          );
      if (!mounted) {
        return (indexed: 0, skipped: 0, failed: 0);
      }
      String status;
      if (result.indexed == 0 && result.skipped == 0 && result.failed == 0) {
        status =
            'No files indexed: ${candidates.length} candidates produced no work.';
      } else {
        status =
            'Indexing complete — ${result.indexed} indexed, ${result.skipped} skipped, ${result.failed} failed';
        if (failures.isNotEmpty) {
          status = '$status. First failure: ${failures.first}';
        }
      }
      final remaining = await LibraryCatalogService.instance
          .countUnindexedManagedItems();
      status =
          '$status. ${remaining == 0 ? 'No books remain to index.' : '$remaining book${remaining == 1 ? '' : 's'} remain to index.'}';
      setState(() {
        _manualIndexStatus = status;
        _pendingIndexCount = remaining;
      });
      await _refreshNeedsAttentionItems();
      return result;
    } catch (error) {
      if (!mounted) {
        return (indexed: 0, skipped: 0, failed: 0);
      }
      setState(() => _manualIndexStatus = 'Indexing failed: $error');
      return (indexed: 0, skipped: 0, failed: 1);
    } finally {
      if (mounted) setState(() => _manualIndexing = false);
    }
  }

  Future<void> _chooseRoot() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LibraryRootSetupScreen()),
    );
    if (!mounted) return;
    await _load();
  }

  void _clearSelectionWarning() {
    _selectionWarning = null;
  }

  void _selectAllCollectionsAndFormats() {
    setState(() {
      _installBooks = true;
      _installDevotionals = true;
      _installCommentaries = true;
      _installMiscCollections = true;
      _installPamphlets = true;
      _installPeriodicals = true;
      _installManuscriptReleases = true;
      _installEpub = true;
      _installPdf = true;
      _clearSelectionWarning();
    });
  }

  void _setPresetEpubOnly() {
    setState(() {
      _installEpub = true;
      _installPdf = false;
      _clearSelectionWarning();
    });
  }

  void _setPresetPdfOnly() {
    setState(() {
      _installEpub = false;
      _installPdf = true;
      _clearSelectionWarning();
    });
  }

  void _setPresetBoth() {
    setState(() {
      _installEpub = true;
      _installPdf = true;
      _clearSelectionWarning();
    });
  }

  void _clearAllSelections() {
    setState(() {
      _installBooks = false;
      _installDevotionals = false;
      _installCommentaries = false;
      _installMiscCollections = false;
      _installPamphlets = false;
      _installPeriodicals = false;
      _installManuscriptReleases = false;
      _installEpub = false;
      _installPdf = false;
      _clearSelectionWarning();
    });
  }

  Set<String> _selectedCollectionNames() {
    final selections = <String>{};
    if (_installBooks) selections.add('EGW Books');
    if (_installDevotionals) selections.add('EGW Devotionals');
    if (_installCommentaries) selections.add('EGW Commentaries');
    if (_installMiscCollections) selections.add('EGW Misc Collections');
    if (_installPamphlets) selections.add('EGW Pamphlets');
    if (_installPeriodicals) selections.add('EGW Periodicals');
    if (_installManuscriptReleases) {
      selections.add('EGW Manuscript Releases');
    }
    return selections;
  }

  Set<ELibraryManagedDownloadFormat> _selectedFormats() {
    final formats = <ELibraryManagedDownloadFormat>{};
    if (_installEpub) {
      formats.add(ELibraryManagedDownloadFormat.epub);
    }
    if (_installPdf) {
      formats.add(ELibraryManagedDownloadFormat.pdf);
    }
    return formats;
  }

  int _selectedFormatCount() {
    return _selectedFormats().length;
  }

  bool _isCollectionSelected(int index) {
    switch (index) {
      case 0:
        return _installBooks;
      case 1:
        return _installDevotionals;
      case 2:
        return _installCommentaries;
      case 3:
        return _installMiscCollections;
      case 4:
        return _installPamphlets;
      case 5:
        return _installPeriodicals;
      case 6:
        return _installManuscriptReleases;
      default:
        return false;
    }
  }

  String _fileCountLabel(int count) {
    return count == 1 ? '1 file' : '$count files';
  }

  static const List<String> _collectionKeys = <String>[
    'EGW Books',
    'EGW Devotionals',
    'EGW Commentaries',
    'EGW Misc Collections',
    'EGW Pamphlets',
    'EGW Periodicals',
    'EGW Manuscript Releases',
  ];

  Map<String, ELibraryInstallEstimateRecord>? _collectionCache(int index) {
    if (index < 0 || index >= _collectionKeys.length) return null;
    return _estimateCacheByCollection[_collectionKeys[index]];
  }

  ELibraryInstallEstimateRecord? _bestCachedRecord(int index) {
    final cache = _collectionCache(index);
    if (cache == null || cache.isEmpty) return null;
    return cache['epub'] ?? cache['pdf'] ?? cache.values.first;
  }

  String _estimateLineForCollection(int index) {
    final record = _bestCachedRecord(index);
    if (record == null) {
      return 'file count not cached yet • size unknown';
    }
    final count = record.fileCount * _selectedFormatCount();
    if (count == 0) {
      return '0 files found • size unknown';
    }
    return '${_fileCountLabel(count)} • size unknown';
  }

  String _selectedDownloadSummary() {
    final formatCount = _selectedFormatCount();
    if (formatCount == 0) {
      return 'Selected download: 0 files found • size unknown';
    }
    var totalCount = 0;
    var knownCount = 0;
    var selectedCount = 0;
    for (var index = 0; index < _collectionKeys.length; index++) {
      if (!_isCollectionSelected(index)) continue;
      selectedCount += 1;
      final record = _bestCachedRecord(index);
      if (record == null) continue;
      knownCount += 1;
      totalCount += record.fileCount * formatCount;
    }
    if (selectedCount == 0) {
      return 'Selected download: 0 files found • size unknown';
    }
    if (knownCount == 0) {
      return 'Selected download: file count not cached yet • size unknown';
    }
    if (knownCount < selectedCount) {
      return 'Selected download: partial count available • size unknown';
    }
    return 'Selected download: ${_fileCountLabel(totalCount)} • size unknown';
  }

  String? _installSelectionWarning() {
    if (_selectedCollectionNames().isEmpty) {
      return 'Select at least one collection to install.';
    }
    if (_selectedFormats().isEmpty) {
      return 'Select EPUB, PDF, or both before installing.';
    }
    return null;
  }

  String _friendlyErrorMessage(Object error) {
    if (error is EgwCollectionFetchException) {
      return error.userFacingMessage;
    }
    final message = error.toString();
    if (message.contains('EGW site refused this request')) {
      return 'EGW site refused this request. Open the collection in a browser or try again later.';
    }
    return message;
  }

  String? _errorDiagnostics(Object error) {
    if (error is EgwCollectionFetchException) {
      return error.diagnosticDetails;
    }
    final message = error.toString();
    final match = RegExp(
      r'Failed URL: .+\nStatus code: \d+',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(message);
    return match?.group(0);
  }

  String? _downloadFailureSummary(ELibraryDownloadReport? report) {
    if (report == null || report.failures.isEmpty) {
      return null;
    }
    for (final failure in report.failures) {
      final error = failure.error ?? '';
      if (error.contains('EGW site refused this request')) {
        return 'EGW site refused this request. Open the collection in a browser or try again later.';
      }
    }
    return 'Some eLibrary files could not be downloaded.';
  }

  String? _downloadUnavailableSummary(ELibraryDownloadReport? report) {
    if (report == null || report.filesUnavailable.isEmpty) {
      return null;
    }
    return 'Some books did not have a verified EPUB/PDF file in the selected format.';
  }

  _ELibraryRunCompletionStatus _completionStatus({
    required ELibraryDownloadReport? downloadReport,
    required int indexingErrors,
    required int indexedCount,
    required bool isRunning,
  }) {
    if (isRunning) {
      return _ELibraryRunCompletionStatus.failedOrIncomplete;
    }
    final failed = downloadReport?.failures.length ?? 0;
    final unavailable = downloadReport?.filesUnavailable.length ?? 0;
    if (failed > 0 || indexingErrors > 0 || indexedCount == 0) {
      return _ELibraryRunCompletionStatus.failedOrIncomplete;
    }
    if (unavailable > 0) {
      return _ELibraryRunCompletionStatus.completedWithWarnings;
    }
    return _ELibraryRunCompletionStatus.cleanSuccess;
  }

  String _completionHeading({
    required ELibraryDownloadReport? downloadReport,
    required int indexingErrors,
    required int indexedCount,
  }) {
    final status = _completionStatus(
      downloadReport: downloadReport,
      indexingErrors: indexingErrors,
      indexedCount: indexedCount,
      isRunning: false,
    );
    return switch (status) {
      _ELibraryRunCompletionStatus.cleanSuccess => 'eLibrary setup complete',
      _ELibraryRunCompletionStatus.completedWithWarnings =>
        'eLibrary setup completed with warnings',
      _ELibraryRunCompletionStatus.failedOrIncomplete =>
        'eLibrary setup incomplete',
    };
  }

  String _completionSummary({
    required ELibraryDownloadReport? downloadReport,
    required int indexingErrors,
    required int indexedCount,
  }) {
    final unavailable = downloadReport?.filesUnavailable.length ?? 0;
    final failed = downloadReport?.failures.length ?? 0;
    return 'Indexed: $indexedCount\n'
        'Unavailable in selected format: $unavailable\n'
        'Failed: $failed\n'
        'Indexing errors: $indexingErrors';
  }

  Future<void> _showUnavailableItemsDialog() async {
    final report = _downloadReport;
    if (report == null || report.filesUnavailable.isEmpty) return;
    final items = report.filesUnavailable;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Unavailable in selected format'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 20),
              itemBuilder: (context, index) {
                final item = items[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (item.collection.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Collection: ${item.collection}'),
                    ],
                    const SizedBox(height: 4),
                    Text('Format: ${item.format.toUpperCase()}'),
                    const SizedBox(height: 4),
                    SelectableText(item.sourceUrl),
                    if ((item.error ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SelectableText(item.error!),
                    ],
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmLegacyMigration() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Move legacy eLibrary files?'),
          content: const SingleChildScrollView(
            child: Text(
              'Legacy eLibrary files can be copied into the new EGW folder layout before the download starts.\n\n'
              'Some duplicate or conflicting legacy files may be moved to a quarantine folder after a verified copy so the original can be reviewed later.\n\n'
              'This is not a delete or reset operation. Your downloaded books are preserved.\n\n'
              'You can cancel now and come back later.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Move Files'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startSetup() async {
    if (_running) return;
    final selection = _selection;
    if (selection?.path == null ||
        selection?.exists != true ||
        selection?.isExplicitlySelected != true) {
      final warning = selection?.path == null
          ? 'Choose a Library Root before installing eLibrary files.'
          : 'Legacy Library Root detected. Open Library Root Setup to confirm or migrate before installing.';
      if (!mounted) return;
      setState(() {
        _selectionWarning = warning;
        _setupStatusMessage = warning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
      return;
    }
    final validationWarning = _installSelectionWarning();
    if (validationWarning != null) {
      if (!mounted) return;
      setState(() {
        _selectionWarning = validationWarning;
        _setupStatusMessage = validationWarning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationWarning)));
      return;
    }

    final needsLegacyMigration = await LegacyELibraryMigrationService.instance
        .hasMigrationCandidates();
    if (!mounted) return;
    if (needsLegacyMigration) {
      final confirmed = await _confirmLegacyMigration();
      if (!mounted) return;
      if (confirmed != true) {
        setState(() {
          _setupStatusMessage =
              'Legacy migration cancelled. No files were changed.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Legacy migration cancelled. No files were changed.'),
          ),
        );
        return;
      }
    }

    final rootPath = selection!.path!;

    setState(() {
      _running = true;
      _indexing = false;
      _cancelRequested = false;
      _error = null;
      _errorDetails = null;
      _downloadReport = null;
      _migrationReport = null;
      _cleanupReport = null;
      _setupReportPath = null;
      _indexReportPath = null;
      _setupStatusMessage = null;
      _progress = null;
      _indexedCount = 0;
      _indexingErrors = 0;
      _clearSelectionWarning();
    });

    try {
      final migrationReport = await LegacyELibraryMigrationService.instance
          .migrate();
      if (!mounted) return;
      if (migrationReport.filesCopied > 0 ||
          migrationReport.filesRenamedDueToConflict > 0) {
        setState(() => _migrationReport = migrationReport);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Existing eLibrary files were organized into the new folder structure. A report was saved.',
            ),
          ),
        );
      }

      final downloadReport = await ELibraryDownloadService.instance
          .runProductionSetup(
            installBooks: _installBooks,
            installDevotionals: _installDevotionals,
            installCommentaries: _installCommentaries,
            installMiscCollections: _installMiscCollections,
            installPamphlets: _installPamphlets,
            installPeriodicals: _installPeriodicals,
            installManuscriptReleases: _installManuscriptReleases,
            installEpub: _installEpub,
            installPdf: _installPdf,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _progress = progress);
            },
            isCancelled: () => _cancelRequested,
          );

      if (!mounted) return;
      setState(() {
        _downloadReport = downloadReport;
        _setupStatusMessage = 'Updating estimates...';
      });
      await _loadEstimateCache();
      if (!mounted) return;

      final cleanupReport = await ELibraryDuplicateCleanupService.instance
          .quarantineDuplicates(isCancelled: () => _cancelRequested);

      if (!mounted) return;
      setState(() {
        _cleanupReport = cleanupReport;
        _setupStatusMessage = 'Refreshing catalog...';
      });

      final catalogTouched = await LibraryCatalogService.instance
          .refreshManagedItemsFromDisk(
            rootPathOverride: downloadReport.destinationRoot,
          );
      if (!mounted) return;
      setState(() {
        _setupStatusMessage = catalogTouched == 0
            ? 'Catalog already up to date.'
            : 'Catalog refreshed ($catalogTouched items).';
      });

      if (!mounted) return;
      setState(() {
        _setupStatusMessage = 'Indexing new/changed books...';
        _indexing = true;
      });

      final indexResult = await _runManualIndex(
        rootPathOverride: downloadReport.destinationRoot,
      );
      if (!mounted) return;
      setState(() {
        _setupStatusMessage = 'Finalizing setup...';
      });

      final passageData = await CommentaryResearchLibraryService.instance
          .loadPassage(
            bookId: 1,
            chapter: 1,
            verse: 1,
            bookName: 'Genesis',
            refresh: false,
          );
      if (!mounted) return;
      final db = await UserDatabase.instance.database;
      final unindexedItems = await LibraryCatalogService.instance
          .listUnindexedManagedItems();
      final needsAttentionItems = await LibraryCatalogService.instance
          .listNeedsAttentionManagedItems();
      final failedRows = await db.rawQuery('''
        SELECT COUNT(*) AS count
        FROM library_items
        WHERE folder_type IN ('commentary', 'research')
          AND index_status = 'failed'
          AND deleted_at IS NULL
      ''');
      final indexingErrors = (failedRows.first['count'] as num?)?.toInt() ?? 0;
      final indexedCount = indexResult.indexed;

      final completedAt = DateTime.now().toUtc();
      final report = <String, Object?>{
        'started_at': downloadReport.startedAt.toIso8601String(),
        'completed_at': completedAt.toIso8601String(),
        'elapsed_seconds': downloadReport.elapsedSeconds,
        'selected_collections': <String>[
          if (_installBooks) 'EGW Books',
          if (_installDevotionals) 'EGW Devotionals',
          if (_installCommentaries) 'EGW Commentaries',
          if (_installMiscCollections) 'EGW Misc Collections',
          if (_installPamphlets) 'EGW Pamphlets',
          if (_installPeriodicals) 'EGW Periodicals',
          if (_installManuscriptReleases) 'EGW Manuscript Releases',
        ],
        'selected_formats': <String>[
          if (_installEpub) 'EPUB',
          if (_installPdf) 'PDF',
        ],
        'source_collection_urls': downloadReport.sourceCollectionUrls,
        'destination_root': downloadReport.destinationRoot,
        'total_links_discovered': downloadReport.totalLinksDiscovered,
        'epub_downloaded_count': downloadReport.epubDownloadedCount,
        'pdf_downloaded_count': downloadReport.pdfDownloadedCount,
        'skipped_existing_count': downloadReport.skippedExistingCount,
        'unavailable_count': downloadReport.unavailableCount,
        'failed_count': downloadReport.failedCount,
        'indexed_count': indexedCount,
        'indexing_errors': indexingErrors,
        'unindexed_item_count': unindexedItems.length,
        'unindexed_items': unindexedItems
            .map(
              (item) => {
                'id': item.id,
                'title': item.displayTitle,
                'collection_name': item.collectionName,
                'relative_path': item.relativePath,
                'index_status': item.indexStatus,
              },
            )
            .toList(growable: false),
        'needs_attention_count': needsAttentionItems.length,
        'needs_attention_items': needsAttentionItems
            .map(
              (item) => {
                'id': item.id,
                'title': item.displayTitle,
                'file_name': item.fileName,
                'collection_name': item.collectionName,
                'relative_path': item.relativePath,
                'index_status': item.indexStatus,
                'reason': item.indexError,
              },
            )
            .toList(growable: false),
        'auto_index_result': {
          'indexed': indexResult.indexed,
          'skipped': indexResult.skipped,
          'failed': indexResult.failed,
        },
        'migration_report_path': _migrationReport?.reportFilePath,
        'source_cleanup_policy': _storagePolicy.name,
        'source_cleanup_policy_label': _storagePolicy.label,
        'source_cleanup_status': _sourceCleanupDeferredMessage,
        'source_files_downloaded': downloadReport.filesDownloaded.length,
        'source_files_retained':
            downloadReport.filesDownloaded.length +
            downloadReport.filesSkipped.length,
        'source_files_removed_after_import': 0,
        'source_files_not_removed_because_import_not_verified':
            downloadReport.filesDownloaded.length +
            downloadReport.filesSkipped.length,
        // Source cleanup is future-facing here; imported works already live in
        // eLibrary.db and only downloaded source files can be removed.
        'files_downloaded': downloadReport.filesDownloaded
            .map((item) => item.toJson())
            .toList(growable: false),
        'files_skipped': downloadReport.filesSkipped
            .map((item) => item.toJson())
            .toList(growable: false),
        'files_unavailable': downloadReport.filesUnavailable
            .map((item) => item.toJson())
            .toList(growable: false),
        'failures': downloadReport.failures
            .map((item) => item.toJson())
            .toList(growable: false),
        'destination_folders': downloadReport.destinationFolders,
        'download_report_path': downloadReport.reportFilePath,
        'cleanup_report_path': _cleanupReport?.reportFilePath,
        'index_report_path': passageData.indexReportPath,
      };

      final reportPath = p.join(
        rootPath,
        'download_reports',
        'production_elibrary_setup_${_timestamp(completedAt)}.json',
      );
      final reportFile = File(reportPath);
      await reportFile.parent.create(recursive: true);
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );

      if (!mounted) return;
      setState(() {
        _setupReportPath = reportPath;
        _indexReportPath = passageData.indexReportPath;
        _indexedCount = indexedCount;
        _indexingErrors = indexingErrors;
        _setupStatusMessage = switch (_completionStatus(
          downloadReport: downloadReport,
          indexingErrors: indexingErrors,
          indexedCount: indexedCount,
          isRunning: false,
        )) {
          _ELibraryRunCompletionStatus.cleanSuccess =>
            'eLibrary setup complete',
          _ELibraryRunCompletionStatus.completedWithWarnings =>
            'eLibrary setup completed with warnings',
          _ELibraryRunCompletionStatus.failedOrIncomplete =>
            'eLibrary setup incomplete',
        };
        _indexing = false;
      });
      await _loadStorageSummary();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_setupStatusMessage ?? 'eLibrary setup complete'} in '
            '${downloadReport.elapsedSeconds.toStringAsFixed(1)}s',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyErrorMessage(error);
        _errorDetails = _errorDiagnostics(error);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('eLibrary setup failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _indexing = false;
          _setupStatusMessage ??= 'Done';
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = -1;
    do {
      value /= 1024;
      unitIndex += 1;
    } while (value >= 1024 && unitIndex < units.length - 1);
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
  }

  Future<void> _removeDownloadedFiles({
    required Set<String> collectionNames,
    required Set<ELibraryManagedDownloadFormat> formats,
    required String actionLabel,
  }) async {
    if (_running || _removingFiles) return;
    final selection = _selection;
    if (selection?.path == null ||
        selection?.exists != true ||
        selection?.isExplicitlySelected != true) {
      final warning = selection?.path == null
          ? 'Choose a Library Root before removing downloaded eLibrary files.'
          : 'Legacy Library Root detected. Open Library Root Setup to confirm or migrate before removing files.';
      if (!mounted) return;
      setState(() {
        _selectionWarning = warning;
        _setupStatusMessage = warning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
      return;
    }
    if (collectionNames.isEmpty) {
      final warning = 'Select at least one collection to remove.';
      if (!mounted) return;
      setState(() {
        _selectionWarning = warning;
        _setupStatusMessage = warning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
      return;
    }
    if (formats.isEmpty) {
      final warning = 'Select EPUB, PDF, or both before removing.';
      if (!mounted) return;
      setState(() {
        _selectionWarning = warning;
        _setupStatusMessage = warning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
      return;
    }

    final rootPath = selection!.path!;
    setState(() {
      _removingFiles = true;
      _selectionWarning = null;
      _setupStatusMessage = 'Scanning downloaded files...';
      _error = null;
      _errorDetails = null;
    });

    try {
      final queue = await ELibraryFileManagementService.instance
          .buildFilteredRemovalQueue(
            collectionNames: collectionNames,
            formats: formats,
            rootPath: rootPath,
          );
      if (!mounted) return;
      if (queue.isEmpty) {
        setState(
          () =>
              _setupStatusMessage = 'No matching downloaded files were found.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No matching downloaded files were found.'),
          ),
        );
        return;
      }

      final totalBytes = queue.fold<int>(
        0,
        (sum, record) => sum + record.fileSize,
      );
      final managedFolders =
          queue
              .map((record) => p.dirname(record.relativePath))
              .toSet()
              .toList(growable: false)
            ..sort();
      final epubCount = queue
          .where(
            (record) => record.format == ELibraryManagedDownloadFormat.epub,
          )
          .length;
      final pdfCount = queue
          .where((record) => record.format == ELibraryManagedDownloadFormat.pdf)
          .length;
      final breakdown = epubCount > 0 && pdfCount > 0
          ? '$epubCount EPUB and $pdfCount PDF'
          : epubCount > 0
          ? '$epubCount EPUB'
          : '$pdfCount PDF';
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(actionLabel),
            content: Text(
              'Library Root:\n${selection.path}\n\n'
              'Managed folders:\n${managedFolders.join('\n')}\n\n'
              'Remove ${queue.length} $breakdown files '
              '(${_formatBytes(totalBytes)}) from the eLibrary?\n\n'
              'If this Library Root is shared with another Biblical Heritage or standalone eLibrary app, removing files here may remove files used by that app too. This will not delete tags, notes, highlights, bookmarks, saved presentations, or user.db.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Remove'),
              ),
            ],
          );
        },
      );
      if (confirm != true) {
        if (!mounted) return;
        setState(() => _setupStatusMessage = 'Removal cancelled.');
        return;
      }

      setState(() => _setupStatusMessage = 'Removing downloaded files...');
      final report = await ELibraryFileManagementService.instance
          .removeDownloadedFiles(
            collectionNames: collectionNames,
            formats: formats,
            rootPath: rootPath,
          );
      if (!mounted) return;
      setState(() {
        _setupStatusMessage =
            'Removed ${report.removedCount} files '
            '(${_formatBytes(report.removedBytes)}). '
            'User tags, notes, highlights, and saved presentations were not changed.';
      });
      await _loadStorageSummary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${report.removedCount} files '
            '(${report.epubRemovedCount} EPUB, ${report.pdfRemovedCount} PDF).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyErrorMessage(error);
        _errorDetails = _errorDiagnostics(error);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removal failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _removingFiles = false);
      }
    }
  }

  void _cancelSetup() {
    if (!_running) return;
    setState(() => _cancelRequested = true);
  }

  bool _captureImportLocationIsReady() {
    if (Platform.isIOS) return true;
    final path = _captureFolderPath?.trim() ?? '';
    return path.isNotEmpty && !_captureFolderIsLegacy;
  }

  String _captureImportsStatusText() {
    return _captureImportLocationIsReady()
        ? '✓ Import location is ready'
        : 'Import location needs attention';
  }

  String _captureImportsHelperText() {
    if (Platform.isIOS) {
      return 'Import a copied book package or legacy CaptureClipper files.';
    }
    return _captureImportLocationIsReady()
        ? 'Import CaptureClipper book packages or captured books into the Pioneer library.'
        : 'Set the import location, then bring in book packages or captured books.';
  }

  String _timestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selection = _selection;

    return Scaffold(
      appBar: AppBar(
        title: const Text('eLibrary Setup'),
        centerTitle: true,
        leading: _setupLeading(context),
        leadingWidth: _setupLeadingWidth(),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  LibraryIndexingPendingCard(
                    pendingCount: _pendingIndexCount,
                    busy: _manualIndexing,
                    onIndexNow: _runManualIndex,
                  ),
                  if (_pendingIndexCount > 0) const SizedBox(height: 12),
                  LibraryNeedsAttentionCard(
                    items: _needsAttentionItems,
                    onRetryRepairable: _runManualIndex,
                    onRefresh: _refreshNeedsAttentionItems,
                  ),
                  if (_needsAttentionItems.isNotEmpty)
                    const SizedBox(height: 12),
                  ELibraryStorageSection(
                    statusLabel: libraryStorageStatusText(selection),
                    helperText: libraryStorageHelperText(selection),
                    disableActions:
                        _running || _manualIndexing || _refreshingEstimateCache,
                    onManageStorage: _chooseRoot,
                    onIndexNewChangedBooks: _runManualIndex,
                    onRefreshStatus: _refreshEstimateCache,
                    manualIndexing: _manualIndexing,
                    manualIndexStatus: _manualIndexStatus,
                    manualIndexCompleted: _manualIndexCompleted,
                    manualIndexTotal: _manualIndexTotal,
                    manualIndexCurrentTitle: _manualIndexCurrentTitle,
                  ),
                  const SizedBox(height: 12),
                  CaptureClipperImportsSection(
                    statusLabel: _captureImportsStatusText(),
                    helperText: _captureImportsHelperText(),
                    disableActions: _running || _captureFolderBusy,
                    lastCheckedLabel: _lastCollectionCheckLabel,
                    isIOS: Platform.isIOS,
                    isAndroid: Platform.isAndroid,
                    onDownloadPioneerBooks: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ImportPioneerLibraryScreen(),
                      ),
                    ),
                    onCheckForNewBooks: _checkForNewBooks,
                    onImportBookPackage: _importOneBookPackage,
                    onImportCapturedBooks: () =>
                        _importPickedCaptureClipperFiles(
                          relatedFilesOnly: true,
                        ),
                    onChangeImportLocation: () => _chooseCaptureFolder(),
                  ),
                  const SizedBox(height: 12),
                  ELibraryInstallCollectionsSection(
                    running: _running,
                    selectionWarning: _selectionWarning,
                    installBooks: _installBooks,
                    installDevotionals: _installDevotionals,
                    installCommentaries: _installCommentaries,
                    installMiscCollections: _installMiscCollections,
                    installPamphlets: _installPamphlets,
                    installPeriodicals: _installPeriodicals,
                    installManuscriptReleases: _installManuscriptReleases,
                    installEpub: _installEpub,
                    installPdf: _installPdf,
                    collectionEstimateLines: List<String>.generate(
                      7,
                      _estimateLineForCollection,
                    ),
                    selectedDownloadSummary: _selectedDownloadSummary(),
                    onSelectAllCollectionsAndFormats:
                        _selectAllCollectionsAndFormats,
                    onClearAllSelections: _clearAllSelections,
                    onSetPresetEpubOnly: _setPresetEpubOnly,
                    onSetPresetPdfOnly: _setPresetPdfOnly,
                    onSetPresetBoth: _setPresetBoth,
                    onStartSetup: _startSetup,
                    onCancel: _cancelSetup,
                    onBooksChanged: (value) => setState(() {
                      _installBooks = value ?? false;
                      _clearSelectionWarning();
                    }),
                    onDevotionalsChanged: (value) => setState(() {
                      _installDevotionals = value ?? false;
                      _clearSelectionWarning();
                    }),
                    onCommentariesChanged: (value) => setState(() {
                      _installCommentaries = value ?? false;
                      _clearSelectionWarning();
                    }),
                    onMiscCollectionsChanged: (value) => setState(() {
                      _installMiscCollections = value ?? false;
                      _clearSelectionWarning();
                    }),
                    onPamphletsChanged: (value) => setState(() {
                      _installPamphlets = value ?? false;
                      _clearSelectionWarning();
                    }),
                    onPeriodicalsChanged: (value) => setState(() {
                      _installPeriodicals = value ?? false;
                      _clearSelectionWarning();
                    }),
                    onManuscriptReleasesChanged: (value) => setState(() {
                      _installManuscriptReleases = value ?? false;
                      _clearSelectionWarning();
                    }),
                    onEpubChanged: (value) => setState(() {
                      _installEpub = value ?? false;
                      _clearSelectionWarning();
                    }),
                    onPdfChanged: (value) => setState(() {
                      _installPdf = value ?? false;
                      _clearSelectionWarning();
                    }),
                  ),
                  const SizedBox(height: 12),
                  ELibrarySetupAdvancedSection(
                    isIOS: Platform.isIOS,
                    selection: selection,
                    captureFolderPath: _captureFolderPath,
                    captureFolderAccess: _captureFolderAccess,
                    captureFolderStatus: _captureFolderStatus,
                    captureImportReport: _captureImportReport,
                    loadingCaptureFolder: _loadingCaptureFolder,
                    loadingCaptureImportAvailability:
                        _loadingCaptureImportAvailability,
                    storagePolicyLabel: _storagePolicy.label,
                    onImportConfiguredFolder: _promptCaptureImports,
                    onResetImportLocation: () =>
                        _chooseCaptureFolder(resetFirst: true),
                    onRepairBrokenItems: () =>
                        _importCaptureFolder(repairExistingItems: true),
                    onReviewImports: _reviewCaptureFolderImports,
                    onClearImportLocation: _clearCaptureFolder,
                    onTestBroadAnyFilePicker: _testBroadAnyFilePicker,
                    onPickScannedHtmlFile: _pickScannedHtmlFile,
                    setupReportPath: _setupReportPath,
                    indexReportPath: _indexReportPath,
                    storageMaintenanceWidget: DownloadedFileMaintenanceSection(
                      loadingStorageSummary: _loadingStorageSummary,
                      storageSummary: _storageSummary,
                      running: _running,
                      removingFiles: _removingFiles,
                      canRemoveFiles: selection?.isExplicitlySelected == true,
                      onRemoveSelected: () => _removeDownloadedFiles(
                        collectionNames: _selectedCollectionNames(),
                        formats: _selectedFormats(),
                        actionLabel: 'Remove Selected',
                      ),
                      onRemoveEpubs: () => _removeDownloadedFiles(
                        collectionNames: _collectionKeys.toSet(),
                        formats: const {ELibraryManagedDownloadFormat.epub},
                        actionLabel: 'Remove EPUBs',
                      ),
                      onRemovePdfs: () => _removeDownloadedFiles(
                        collectionNames: _collectionKeys.toSet(),
                        formats: const {ELibraryManagedDownloadFormat.pdf},
                        actionLabel: 'Remove PDFs',
                      ),
                      onRemoveAll: () => _removeDownloadedFiles(
                        collectionNames: _collectionKeys.toSet(),
                        formats: const {
                          ELibraryManagedDownloadFormat.epub,
                          ELibraryManagedDownloadFormat.pdf,
                        },
                        actionLabel: 'Remove All Downloaded Library Files',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_running) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_indexing) ...[
                              const LinearProgressIndicator(),
                              const SizedBox(height: 12),
                              Text(
                                _setupStatusMessage ??
                                    'Indexing new/changed books...',
                              ),
                            ] else ...[
                              LinearProgressIndicator(
                                value: (_progress?.totalPlannedCount ?? 0) > 0
                                    ? (_progress!.completedCount /
                                              _progress!.totalPlannedCount)
                                          .clamp(0.0, 1.0)
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _setupStatusMessage ??
                                    _progress?.statusMessage ??
                                    'Preparing download...',
                              ),
                              if ((_progress?.totalPlannedCount ?? 0) > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${_progress!.completedCount} of '
                                  '${_progress!.totalPlannedCount} prepared',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                            const SizedBox(height: 8),
                            Text(
                              '${_progress?.currentCollection ?? 'Collection'} '
                              '${_progress?.collectionIndex ?? 0}/${_progress?.collectionTotal ?? 0}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Downloaded: ${_progress?.downloadedCount ?? 0}  '
                              'Skipped: ${_progress?.skippedCount ?? 0}  '
                              'Unavailable in selected format: ${_progress?.unavailableCount ?? 0}  '
                              'Failed: ${_progress?.failedCount ?? 0}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Current file: ${_progress?.currentFile ?? '-'}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Elapsed: ${(_progress?.elapsedSeconds ?? 0).toStringAsFixed(1)}s',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_downloadReport != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _completionHeading(
                                downloadReport: _downloadReport,
                                indexingErrors: _indexingErrors,
                                indexedCount: _indexedCount,
                              ),
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _completionSummary(
                                downloadReport: _downloadReport,
                                indexingErrors: _indexingErrors,
                                indexedCount: _indexedCount,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Downloaded: ${_downloadReport!.filesDownloaded.length}',
                            ),
                            Text(
                              'Skipped existing: ${_downloadReport!.filesSkipped.length}',
                            ),
                            Text(
                              'Unavailable in selected format: ${_downloadReport!.filesUnavailable.length}',
                            ),
                            Text('Failed: ${_downloadReport!.failures.length}'),
                            Text('Indexed: $_indexedCount'),
                            Text('Indexing errors: $_indexingErrors'),
                            Text(
                              'Elapsed: ${_downloadReport!.elapsedSeconds.toStringAsFixed(1)}s',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Source cleanup policy: ${_storagePolicy.label} (future behavior)',
                            ),
                            Text(
                              'Source files downloaded: ${_downloadReport!.filesDownloaded.length}',
                            ),
                            Text(
                              'Source files retained for backup/re-import: ${_downloadReport!.filesDownloaded.length + _downloadReport!.filesSkipped.length}',
                            ),
                            Text('Source files removed after import: 0'),
                            Text(
                              'Source files not removed yet: ${_downloadReport!.filesDownloaded.length + _downloadReport!.filesSkipped.length}',
                            ),
                            Text(
                              'Cleanup status: $_sourceCleanupDeferredMessage',
                            ),
                            if (_downloadReport!
                                .filesUnavailable
                                .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                _downloadUnavailableSummary(_downloadReport) ??
                                    'Some books did not have a verified EPUB/PDF file in the selected format.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.tertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton(
                                  onPressed: _showUnavailableItemsDialog,
                                  child: const Text('View unavailable items'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _downloadReport!.filesUnavailable
                                    .take(3)
                                    .map(
                                      (item) =>
                                          '${item.title} (${item.format.toUpperCase()}): ${item.sourceUrl}\n${item.error ?? "No diagnostic details available."}',
                                    )
                                    .join('\n\n'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'These are candidates for a later fallback import path. Some may be available as PDF or online text/HTML, but fallback import is not implemented in this screen yet.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (_downloadReport!.failures.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                _downloadFailureSummary(_downloadReport) ??
                                    'Some eLibrary files could not be downloaded.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _downloadReport!.failures.first.error ??
                                    'No diagnostic details available.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            SelectableText(
                              _setupReportPath ??
                                  _downloadReport!.reportFilePath,
                            ),
                            if (_indexReportPath != null) ...[
                              const SizedBox(height: 8),
                              SelectableText(_indexReportPath!),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _error!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                            if (_errorDetails != null &&
                                _errorDetails!.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SelectableText(
                                _errorDetails!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _setupLeading(BuildContext context) {
    final inset = defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0;
    return Padding(
      padding: EdgeInsets.only(left: inset),
      child: const BackButton(),
    );
  }

  double _setupLeadingWidth() {
    return 56 + (defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0);
  }
}
