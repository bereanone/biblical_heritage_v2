import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../library/data/library_citation_display_helper.dart';
import 'tag_dialog_styles.dart';
import 'tag_quick_apply_helper.dart';

class TagDialogEntryList extends StatelessWidget {
  const TagDialogEntryList({
    super.key,
    required this.currentTag,
    required this.entries,
    required this.formatEntry,
    required this.fontScale,
    this.onEntryTap,
  });

  final String currentTag;
  final List<HashTagEntry> entries;
  final String Function(HashTagEntry entry) formatEntry;
  final double fontScale;
  final ValueChanged<HashTagEntry>? onEntryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          currentTag.isEmpty ? 'Selected tag entries' : currentTag,
          style: TagDialogStyles.titleTextStyle(
            theme,
            fontScale,
            color: TagDialogStyles.title(theme),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No entries for the selected tag.',
              style: TagDialogStyles.bodyTextStyle(
                theme,
                fontScale,
                color: TagDialogStyles.body(theme),
              ),
            ),
          )
        else
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 0,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: TagDialogStyles.card(theme),
                title: Text(
                  formatEntry(entry),
                  style: TagDialogStyles.titleTextStyle(
                    theme,
                    fontScale,
                    color: TagDialogStyles.title(theme),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  _subtitleForEntry(entry),
                  style: TagDialogStyles.bodyTextStyle(
                    theme,
                    fontScale,
                    color: TagDialogStyles.body(theme),
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: TagDialogStyles.body(theme),
                ),
                onTap: onEntryTap == null ? null : () => onEntryTap!(entry),
              ),
            ),
          ),
      ],
    );
  }

  String _subtitleForEntry(HashTagEntry entry) {
    final eLibrarySubtitle = _eLibrarySubtitle(entry);
    if (eLibrarySubtitle.isNotEmpty) return eLibrarySubtitle;

    final referenceCode = _cleanVisibleText(entry.referenceCode);
    if (referenceCode.isNotEmpty) return referenceCode;

    final noteText = entry.noteText?.trim() ?? '';
    if (noteText.isNotEmpty) return noteText;

    final verseRef = entry.verseRef.trim();
    if (verseRef.isEmpty || _looksInternal(verseRef)) return '';
    return verseRef;
  }

  String _cleanVisibleText(String? value) {
    final cleaned = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty || _looksInternal(cleaned)) return '';
    return cleaned;
  }

  String _eLibrarySubtitle(HashTagEntry entry) {
    final metadata = _eLibraryMetadata(entry);
    if (metadata == null) return '';
    return libraryUserFacingELibraryDisplayLabel(
      sourceTitle: metadata.sourceTitle,
      sourceTitleAcronym: metadata.sourceTitleAcronym,
      sourceLocation: metadata.sourceLocation,
      sourceReferenceText: metadata.sourceReferenceText,
      fileName: metadata.sourceRelativePath.trim().isNotEmpty
          ? p.basename(metadata.sourceRelativePath)
          : null,
      relativePath: metadata.sourceRelativePath,
      pageCitation: metadata.citationText.isNotEmpty
          ? metadata.citationText
          : null,
      paragraphIndex:
          metadata.sourceParagraphNumber ?? metadata.sourceParagraphIndex,
    );
  }

  _TagDialogELibraryMetadata? _eLibraryMetadata(HashTagEntry entry) {
    final raw = entry.noteFormatJson?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['kind']?.toString() != 'elibrary_note') return null;
      return _TagDialogELibraryMetadata(
        sourceTitle: decoded['source_title']?.toString() ?? '',
        sourceTitleAcronym: decoded['source_title_acronym']?.toString() ?? '',
        sourceLocation: decoded['source_location']?.toString() ?? '',
        sourceReferenceText: decoded['source_reference_text']?.toString() ?? '',
        sourceRelativePath: decoded['source_relative_path']?.toString() ?? '',
        sourcePageNumber: _intFromJson(decoded['source_page_number']),
        sourceParagraphNumber: _intFromJson(decoded['source_paragraph_number']),
        sourceParagraphIndex: _intFromJson(decoded['source_paragraph_index']),
      );
    } catch (_) {
      return null;
    }
  }

  int? _intFromJson(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _looksInternal(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return true;
    final lower = trimmed.toLowerCase();
    return lower.startsWith('elibrary:') ||
        lower.startsWith('note:') ||
        lower.contains('::') ||
        lower.contains('oebps/') ||
        lower.contains('.xhtml') ||
        lower == 'book 0 0:0';
  }
}

class _TagDialogELibraryMetadata {
  const _TagDialogELibraryMetadata({
    required this.sourceTitle,
    required this.sourceTitleAcronym,
    required this.sourceLocation,
    required this.sourceReferenceText,
    required this.sourceRelativePath,
    required this.sourcePageNumber,
    required this.sourceParagraphNumber,
    required this.sourceParagraphIndex,
  });

  final String sourceTitle;
  final String sourceTitleAcronym;
  final String sourceLocation;
  final String sourceReferenceText;
  final String sourceRelativePath;
  final int? sourcePageNumber;
  final int? sourceParagraphNumber;
  final int? sourceParagraphIndex;

  String get citationText {
    final page = sourcePageNumber;
    final paragraph = sourceParagraphNumber;
    if (page != null && paragraph != null && page > 0 && paragraph > 0) {
      return '$page.$paragraph';
    }
    return '';
  }
}
