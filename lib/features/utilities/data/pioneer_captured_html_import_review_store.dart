import 'package:flutter/foundation.dart';

import '../../../core/bootstrap/local_settings_store.dart';

@immutable
class PioneerCapturedHtmlImportReviewEntry {
  const PioneerCapturedHtmlImportReviewEntry({
    required this.importedAt,
    required this.title,
    required this.author,
    required this.sourceFilePath,
    required this.sourceRelativePath,
    required this.sourceType,
    required this.status,
    this.warningOrFailureReason,
    this.libraryItemId,
  });

  final DateTime importedAt;
  final String title;
  final String author;
  final String sourceFilePath;
  final String sourceRelativePath;
  final String sourceType;
  final String status;
  final String? warningOrFailureReason;
  final String? libraryItemId;

  bool get isImported => _normalizedStatus == 'imported';
  bool get isSkippedDuplicate => _normalizedStatus == 'skippedduplicate';
  bool get isNeedsCleanup => _normalizedStatus == 'needscleanup';
  bool get isFailed => _normalizedStatus == 'failed';
  bool get hasLibraryItemId =>
      libraryItemId?.trim().isNotEmpty == true && !isFailed;

  String get displayStatusLabel {
    switch (_normalizedStatus) {
      case 'imported':
        return 'Imported';
      case 'skippedduplicate':
        return 'Skipped duplicate';
      case 'needscleanup':
        return 'Needs cleanup';
      case 'failed':
        return 'Failed';
    }
    return status.trim().isEmpty ? 'Unknown' : status.trim();
  }

  String get _normalizedStatus => status.trim().toLowerCase();

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'imported_at': importedAt.toIso8601String(),
      'title': title,
      'author': author,
      'source_file_path': sourceFilePath,
      'source_relative_path': sourceRelativePath,
      'source_type': sourceType,
      'status': status,
      'warning_or_failure_reason': warningOrFailureReason,
      'library_item_id': libraryItemId,
    };
  }

  factory PioneerCapturedHtmlImportReviewEntry.fromJson(
    Map<String, Object?> json,
  ) {
    final importedAt =
        DateTime.tryParse(json['imported_at']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final reason = json['warning_or_failure_reason']?.toString().trim() ?? '';
    final libraryItemId = json['library_item_id']?.toString().trim() ?? '';
    return PioneerCapturedHtmlImportReviewEntry(
      importedAt: importedAt,
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      sourceFilePath: json['source_file_path']?.toString() ?? '',
      sourceRelativePath: json['source_relative_path']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      warningOrFailureReason: reason.isEmpty ? null : reason,
      libraryItemId: libraryItemId.isEmpty ? null : libraryItemId,
    );
  }
}

class PioneerCapturedHtmlImportReviewStore {
  PioneerCapturedHtmlImportReviewStore({LocalSettingsStore? settingsStore})
    : _settingsStore = settingsStore ?? LocalSettingsStore.instance;

  static final PioneerCapturedHtmlImportReviewStore instance =
      PioneerCapturedHtmlImportReviewStore();

  static const _reviewEntriesKey = 'pioneer_captured_html_review_entries';
  static const _maxStoredEntries = 50;

  final LocalSettingsStore _settingsStore;

  Future<List<PioneerCapturedHtmlImportReviewEntry>> loadRecentEntries({
    int limit = 20,
  }) async {
    final settings = await _settingsStore.load();
    final entries = _decodeEntries(settings[_reviewEntriesKey]);
    entries.sort((left, right) => right.importedAt.compareTo(left.importedAt));
    if (limit <= 0) {
      return const <PioneerCapturedHtmlImportReviewEntry>[];
    }
    return entries.take(limit).toList(growable: false);
  }

  Future<void> recordEntries(
    Iterable<PioneerCapturedHtmlImportReviewEntry> entries,
  ) async {
    final newEntries = entries.toList(growable: false);
    if (newEntries.isEmpty) return;

    final settings = await _settingsStore.load();
    final existing = _decodeEntries(settings[_reviewEntriesKey]);
    final merged = <PioneerCapturedHtmlImportReviewEntry>[
      ...newEntries,
      ...existing,
    ];
    merged.sort((left, right) => right.importedAt.compareTo(left.importedAt));
    settings[_reviewEntriesKey] = merged
        .take(_maxStoredEntries)
        .map((entry) => entry.toJson())
        .toList(growable: false);
    await _settingsStore.save(settings);
  }

  List<PioneerCapturedHtmlImportReviewEntry> _decodeEntries(Object? raw) {
    if (raw is! List) return const <PioneerCapturedHtmlImportReviewEntry>[];
    final decoded = <PioneerCapturedHtmlImportReviewEntry>[];
    for (final item in raw) {
      if (item is Map<String, Object?>) {
        decoded.add(PioneerCapturedHtmlImportReviewEntry.fromJson(item));
        continue;
      }
      if (item is Map) {
        decoded.add(
          PioneerCapturedHtmlImportReviewEntry.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    }
    return decoded;
  }
}
