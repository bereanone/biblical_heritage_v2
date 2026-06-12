import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_citation_display_helper.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

import 'presentation_models.dart';

const bool _enablePresentationGroupingDebugLogs = false;

class PresentationGroupingAdapter {
  const PresentationGroupingAdapter({this.legacyGroupKey});

  final String? legacyGroupKey;

  Future<List<PresentationSlide>> adaptEntries(
    Iterable<HashTagEntry> entries,
  ) async {
    final sourceEntries = entries.toList(growable: false);
    final books = await StudyBibleDatabase.instance.loadBooks();
    final bookNames = {
      for (final book in books) book.bookNumber: book.bookName,
    };
    final displayDataByEntryId = await _loadDisplayDataForEntries(
      sourceEntries,
    );
    _logSourceEntries(sourceEntries, displayDataByEntryId);
    final assignedGroups = <int, _PresentationSlideDraft>{};
    final implicitSlides = <_PresentationSlideDraft>[];

    for (var index = 0; index < sourceEntries.length; index++) {
      final entry = sourceEntries[index];
      final displayData = displayDataByEntryId[entry.id];
      final slideNumber = entry.presentationSlideNumber;
      if (slideNumber != null && slideNumber > 0) {
        final draft = assignedGroups.putIfAbsent(
          slideNumber,
          () => _PresentationSlideDraft.assigned(slideNumber),
        );
        draft.addEntry(entry, displayData: displayData);
        continue;
      }

      final draft = _PresentationSlideDraft.implicit(entry.id);
      draft.addEntry(entry, displayData: displayData);
      implicitSlides.add(draft);
    }

    final orderedSlides = <_PresentationSlideDraft>[
      ...assignedGroups.values.toList(growable: false)..sort(
        (a, b) => a.assignedSlideNumber!.compareTo(b.assignedSlideNumber!),
      ),
      ...implicitSlides,
    ];

    final slides = <PresentationSlide>[];
    for (var index = 0; index < orderedSlides.length; index++) {
      final draft = orderedSlides[index];
      final slideId = draft.slideId;
      final layoutType = _layoutTypeForEntries(draft.entries);
      final slide = PresentationSlide(
        id: slideId,
        settingsKey: _slideSettingsKeyForEntries(draft.entries),
        slideTitle: _slideTitleForEntries(draft.entries, bookNames),
        slideTitleFormatJson: _slideTitleFormatJsonForEntries(draft.entries),
        legacyGroupKey: legacyGroupKey,
        slideNumber: index + 1,
        layoutType: layoutType,
        items: _itemsForEntries(draft.entries, slideId, layoutType, bookNames),
      );
      slides.add(slide);
      _logSlide(slide, index);
    }

    return List.unmodifiable(slides);
  }

  List<PresentationSlideItem> _itemsForEntries(
    List<_PresentationGroupedEntry> entries,
    String slideId,
    PresentationLayoutType layoutType,
    Map<int, String> bookNames,
  ) {
    final items = <PresentationSlideItem>[];
    for (final groupedEntry in entries) {
      items.addAll(
        _itemsForEntry(
          groupedEntry.entry,
          slideId,
          layoutType,
          bookNames: bookNames,
          displayData: groupedEntry.displayData,
        ),
      );
    }
    return List.unmodifiable(items);
  }

  List<PresentationSlideItem> _itemsForEntry(
    HashTagEntry entry,
    String slideId,
    PresentationLayoutType layoutType, {
    required Map<int, String> bookNames,
    _PresentationEntryDisplayData? displayData,
  }) {
    final isTwoColumn = layoutType == PresentationLayoutType.twoColumns;
    final noteSource = _noteSourceInfo(entry);
    final isBibleVerse = _isBibleVerseEntry(entry);
    if (!isBibleVerse) {
      final noteText = _resolvedNoteText(entry);
      return [
        PresentationSlideItem(
          id: '$slideId-note-${entry.id}',
          presentationSlideId: slideId,
          sourceType: noteSource.type,
          sourceId: noteSource.id,
          legacyItemId: entry.id.toString(),
          bookNumber: entry.bookNumber,
          chapter: entry.chapter,
          verse: entry.verse,
          verseEnd: entry.verseEnd,
          layoutRegion: PresentationLayoutRegion.full,
          layoutOrder: 0,
          itemKind: PresentationItemKind.note,
          itemPlacement:
              entry.presentationSlideRegion ?? PresentationItemPlacement.auto,
          displayTitle:
              displayData?.displayTitle ??
              _displayTitleForEntry(entry, bookNames: bookNames),
          displayText: noteText,
          citationText: null,
          noteText: noteText.isEmpty ? null : noteText,
          noteFormatJson: entry.noteFormatJson,
          displayTextFormatJson: null,
          mediaRefs: entry.mediaRefs.isEmpty ? null : entry.mediaRefs,
        ),
      ];
    }

    final displayText = _resolvedBodyText(entry);
    final noteText = _resolvedNoteText(entry);
    final citationText = _resolvedCitationText(entry, bookNames: bookNames);
    return [
      PresentationSlideItem(
        id: '$slideId-verse-${entry.id}',
        presentationSlideId: slideId,
        sourceType: 'verse',
        sourceId: _verseSourceId(entry),
        legacyItemId: entry.id.toString(),
        bookNumber: entry.bookNumber,
        chapter: entry.chapter,
        verse: entry.verse,
        verseEnd: entry.verseEnd,
        layoutRegion: isTwoColumn
            ? PresentationLayoutRegion.left
            : PresentationLayoutRegion.full,
        layoutOrder: 0,
        itemKind: PresentationItemKind.verse,
        itemPlacement:
            entry.presentationSlideRegion ?? PresentationItemPlacement.auto,
        displayTitle: _displayTitleForEntry(entry, bookNames: bookNames),
        displayText: displayText,
        citationText: citationText,
        noteText: noteText.isEmpty ? null : noteText,
        noteFormatJson: entry.noteFormatJson,
        displayTextFormatJson: entry.displayTextFormatJson,
        mediaRefs: entry.mediaRefs.isEmpty ? null : entry.mediaRefs,
      ),
    ];
  }

  bool _isNoteOnlyEntry(HashTagEntry entry) {
    return entry.bookNumber == 0 &&
        entry.chapter == 0 &&
        entry.verse == 0 &&
        entry.verseRef.trim().startsWith('note:');
  }

  String _displayTitleForEntry(
    HashTagEntry entry, {
    Map<int, String>? bookNames,
  }) {
    final metadata = _elibraryNoteMetadata(entry);
    if (metadata != null) {
      final title = _safeELibraryTitle(metadata.sourceTitle);
      final referenceCode = _referenceCodeForEntry(entry, metadata: metadata);
      final abbreviation = metadata.sourceTitleAcronym.trim();
      if (title.isNotEmpty && referenceCode.isNotEmpty) {
        return '$title — $referenceCode';
      }
      if (title.isNotEmpty) return title;
      if (referenceCode.isNotEmpty) return referenceCode;
      if (abbreviation.isNotEmpty) return abbreviation;
      return 'eLibrary Quote';
    }
    final userTitle = entry.userTitle?.trim() ?? '';
    if (userTitle.isNotEmpty) return userTitle;
    final referenceCode = _referenceCodeForEntry(entry);
    if (_isNoteOnlyEntry(entry)) return 'Note';
    if (referenceCode.isNotEmpty) return referenceCode;
    final verseRef = entry.verseRef.trim();
    if (verseRef.isNotEmpty &&
        !_isInternalNotePlaceholder(verseRef) &&
        !_looksLikeRawBibleReference(verseRef)) {
      return verseRef;
    }
    if (_cleanHtml(entry.contentHtml).isNotEmpty) {
      return 'Slide';
    }
    if (_isBibleVerseEntry(entry)) {
      final bookName = bookNames?[entry.bookNumber]?.trim() ?? '';
      final verseLabel = entry.verseEnd > entry.verse
          ? '${entry.verse}-${entry.verseEnd}'
          : '${entry.verse}';
      return '${bookName.isNotEmpty ? bookName : 'Book ${entry.bookNumber}'} ${entry.chapter}:$verseLabel';
    }
    return 'Verse';
  }

  String _verseSourceId(HashTagEntry entry) {
    return bibleRangeSourceId(
      bookNumber: entry.bookNumber,
      chapter: entry.chapter,
      verseStart: entry.verse,
      verseEnd: entry.verseEnd,
    );
  }

  _PresentationSourceInfo _noteSourceInfo(HashTagEntry entry) {
    final metadata = _elibraryNoteMetadata(entry);
    final stableRef = metadata?.stableRef.trim() ?? '';
    if (stableRef.isNotEmpty) {
      return _PresentationSourceInfo(type: 'elibrary_note', id: stableRef);
    }
    if (_isNoteOnlyEntry(entry)) {
      return _PresentationSourceInfo(type: 'note', id: 'note:${entry.id}');
    }
    return _PresentationSourceInfo(
      type: 'tag_note',
      id: 'tag-note:${entry.id}',
    );
  }

  String _slideSettingsKeyForEntries(List<_PresentationGroupedEntry> entries) {
    final identities = <String>{};
    for (final groupedEntry in entries) {
      final entry = groupedEntry.entry;
      if (!_isBibleVerseEntry(entry)) {
        identities.add(_noteSourceInfo(entry).toStableKey());
        continue;
      }
      identities.add('verse:${_verseSourceId(entry)}');
      final noteText = _resolvedNoteText(entry);
      if (noteText.isNotEmpty) {
        identities.add(_noteSourceInfo(entry).toStableKey());
      }
    }
    final sorted = identities.toList(growable: false)..sort();
    return sorted.join('|');
  }

  String _resolvedBodyText(HashTagEntry entry) {
    final contentHtml = _cleanHtml(entry.contentHtml);
    if (contentHtml.isNotEmpty) return contentHtml;

    final displayOverride = entry.displayTextOverride?.trim() ?? '';
    if (displayOverride.isNotEmpty) return displayOverride;

    final verseText = entry.verseText.trim();
    if (verseText.isNotEmpty) return verseText;

    return '';
  }

  String? _resolvedCitationText(
    HashTagEntry entry, {
    required Map<int, String> bookNames,
  }) {
    final direct = entry.referenceCode?.trim() ?? '';
    if (direct.isNotEmpty) return direct;
    if (_isBibleVerseEntry(entry)) {
      final verseRef = entry.verseRef.trim();
      if (verseRef.isNotEmpty &&
          !_isInternalNotePlaceholder(verseRef) &&
          !_looksLikeRawBibleReference(verseRef)) {
        return verseRef;
      }
      final bookName = bookNames[entry.bookNumber]?.trim() ?? '';
      final verseLabel = entry.verseEnd > entry.verse
          ? '${entry.verse}-${entry.verseEnd}'
          : '${entry.verse}';
      return '${bookName.isNotEmpty ? bookName : 'Book ${entry.bookNumber}'} ${entry.chapter}:$verseLabel';
    }
    return null;
  }

  String _resolvedNoteText(HashTagEntry entry) {
    final noteText = entry.noteText?.trim() ?? '';
    if (noteText.isNotEmpty && !_isInternalPresentationPlaceholder(noteText)) {
      return noteText;
    }

    final contentHtml = _cleanHtml(entry.contentHtml);
    if (contentHtml.isNotEmpty) return contentHtml;

    final metadata = _elibraryNoteMetadata(entry);
    if (metadata != null) {
      final excerpt = metadata.excerpt.trim();
      if (excerpt.isNotEmpty) return excerpt;
      final sourceParagraph = metadata.sourceParagraph.trim();
      if (sourceParagraph.isNotEmpty) return sourceParagraph;
      final location = metadata.sourceLocation.trim();
      if (location.isNotEmpty) return location;
      final title = metadata.sourceTitle.trim();
      if (title.isNotEmpty) return title;
    }

    return '';
  }

  String? _slideTitleForEntries(
    List<_PresentationGroupedEntry> entries,
    Map<int, String> bookNames,
  ) {
    for (final groupedEntry in entries) {
      final displayTitle = groupedEntry.displayData?.slideTitle.trim();
      if (displayTitle != null && displayTitle.isNotEmpty) {
        return displayTitle;
      }
      final entry = groupedEntry.entry;
      final bibleTitle = _displayTitleForEntry(
        entry,
        bookNames: bookNames,
      ).trim();
      if (bibleTitle.isNotEmpty &&
          (_isBibleVerseEntry(entry) || _isNoteOnlyEntry(entry))) {
        return bibleTitle;
      }
      final metadata = _elibraryNoteMetadata(groupedEntry.entry);
      if (metadata == null) continue;
      final title = _safeELibraryTitle(metadata.sourceTitle);
      final referenceCode = _referenceCodeForEntry(
        groupedEntry.entry,
        metadata: metadata,
      );
      final abbreviation = metadata.sourceTitleAcronym.trim();
      if (title.isNotEmpty && referenceCode.isNotEmpty) {
        return '$title — $referenceCode';
      }
      if (title.isNotEmpty) return title;
      if (referenceCode.isNotEmpty) return referenceCode;
      if (abbreviation.isNotEmpty) return abbreviation;
      return 'eLibrary Quote';
    }
    return null;
  }

  String? _slideTitleFormatJsonForEntries(
    List<_PresentationGroupedEntry> entries,
  ) {
    for (final groupedEntry in entries) {
      final entry = groupedEntry.entry;
      final titleFormatJson = entry.titleFormatJson?.trim() ?? '';
      if (titleFormatJson.isNotEmpty) {
        return titleFormatJson;
      }
    }
    return null;
  }

  _ELibraryNoteMetadata? _elibraryNoteMetadata(HashTagEntry entry) {
    final raw = entry.noteFormatJson?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['kind']?.toString() != 'elibrary_note') return null;
      return _ELibraryNoteMetadata(
        sourceTitle: decoded['source_title']?.toString() ?? '',
        sourceTitleAcronym: decoded['source_title_acronym']?.toString() ?? '',
        sourceLocation: decoded['source_location']?.toString() ?? '',
        sourceReferenceText: decoded['source_reference_text']?.toString() ?? '',
        sourceHref: decoded['source_href']?.toString() ?? '',
        sourceAnchorId: decoded['source_anchor_id']?.toString() ?? '',
        sourceSpineIndex: _intFromJson(decoded['source_spine_index']),
        sourceParagraphIndex: _intFromJson(decoded['source_paragraph_index']),
        sourceRelativePath: decoded['source_relative_path']?.toString() ?? '',
        sourcePageNumber: _intFromJson(decoded['source_page_number']),
        sourceParagraphNumber: _intFromJson(decoded['source_paragraph_number']),
        searchQuery: decoded['search_query']?.toString() ?? '',
        sourceParagraph: decoded['source_paragraph']?.toString() ?? '',
        excerpt: decoded['excerpt']?.toString() ?? '',
        stableRef: decoded['stable_ref']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  String _cleanHtml(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return '';
    final stripped = value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
    return _isInternalPresentationPlaceholder(stripped) ? '' : stripped;
  }

  bool _isInternalNotePlaceholder(String value) {
    return RegExp(r'^note:\d+(?::\d+)?$').hasMatch(value.trim());
  }

  bool _isInternalPresentationPlaceholder(String value) {
    final trimmed = value.trim();
    return _isInternalNotePlaceholder(trimmed) ||
        trimmed.startsWith('elibrary:');
  }

  bool _looksLikeRawBibleReference(String value) {
    return RegExp(r'^\d+:\d+:\d+(?:-\d+)?$').hasMatch(value.trim());
  }

  PresentationLayoutType _layoutTypeForEntries(
    List<_PresentationGroupedEntry> entries,
  ) {
    final bibleVerseCount = entries
        .where((groupedEntry) => _isBibleVerseEntry(groupedEntry.entry))
        .length;
    final hasStandaloneNoteItems = entries.any(
      (groupedEntry) => _isNoteOnlyEntry(groupedEntry.entry),
    );
    if (bibleVerseCount > 1) {
      return PresentationLayoutType.fullWidth;
    }
    if (bibleVerseCount == 1 && hasStandaloneNoteItems) {
      return PresentationLayoutType.twoColumns;
    }
    return PresentationLayoutType.fullWidth;
  }

  bool _isBibleVerseEntry(HashTagEntry entry) {
    return entry.bookNumber > 0 && entry.chapter > 0 && entry.verse > 0;
  }

  Future<Map<int, _PresentationEntryDisplayData?>> _loadDisplayDataForEntries(
    List<HashTagEntry> entries,
  ) async {
    final result = <int, _PresentationEntryDisplayData?>{};
    final referenceCache = <String, Future<_ELibraryCitationLookupResult>>{};

    for (final entry in entries) {
      final metadata = _elibraryNoteMetadata(entry);
      if (metadata == null) {
        result[entry.id] = null;
        continue;
      }
      result[entry.id] = await _buildDisplayDataForELibraryEntry(
        entry: entry,
        metadata: metadata,
        referenceCache: referenceCache,
      );
    }

    return result;
  }

  Future<_PresentationEntryDisplayData?> _buildDisplayDataForELibraryEntry({
    required HashTagEntry entry,
    required _ELibraryNoteMetadata metadata,
    required Map<String, Future<_ELibraryCitationLookupResult>> referenceCache,
  }) async {
    final lookup = await _resolvedCitationForStableRef(
      metadata.stableRef,
      referenceCache: referenceCache,
    );
    final title = _resolvedELibraryTitle(
      metadata: metadata,
      libraryItem: lookup.libraryItem,
      bookAbbreviation: lookup.bookAbbreviation,
    );
    final abbreviation = metadata.sourceTitleAcronym.trim().isNotEmpty
        ? _safeELibraryBookAbbreviation(metadata.sourceTitleAcronym.trim())
        : _safeELibraryBookAbbreviation(lookup.bookAbbreviation ?? '');
    final referenceCode = _referenceCodeForEntry(
      entry,
      metadata: metadata,
      lookup: lookup,
    );
    final displayTitle = _composeELibraryDisplayTitle(
      title: title,
      location: referenceCode,
    );
    final safeDisplayTitle = displayTitle.isNotEmpty
        ? displayTitle
        : _fallbackELibraryDisplayTitle(metadata: metadata, lookup: lookup);

    if (_enablePresentationGroupingDebugLogs) {
      final parsed = lookup.parsed;
      final parsedItemId = parsed?.itemId ?? '';
      final parsedHref = parsed?.epubHref ?? '';
      final parsedSpine = parsed?.spineIndex;
      final parsedParagraph = parsed?.paragraphIndex;
      debugPrint(
        '[PresentationGroupingAdapter] elibrary source '
        'id=${entry.id} '
        'raw stable_ref=${metadata.stableRef.isEmpty ? '(empty)' : metadata.stableRef} '
        'item=${parsedItemId.isEmpty ? '(none)' : parsedItemId} '
        'bookKey=${abbreviation.isEmpty ? '(none)' : abbreviation} '
        'spine=${parsedSpine?.toString() ?? '(none)'} '
        'paragraph=${parsedParagraph?.toString() ?? '(none)'} '
        'href=${parsedHref.isEmpty ? '(none)' : _normalizedEpubHref(parsedHref)} '
        'query=${lookup.queryDescription} '
        'matches=${lookup.matchCount} '
        'candidates=${lookup.candidateSummary.isEmpty ? '(none)' : lookup.candidateSummary} '
        'finalDisplayTitle=${safeDisplayTitle.isEmpty ? '(empty)' : safeDisplayTitle}',
      );
    }

    return _PresentationEntryDisplayData(
      slideTitle: safeDisplayTitle,
      displayTitle: safeDisplayTitle,
      sourceTitle: title,
      sourceLocation: referenceCode,
      resolvedCitation: referenceCode.isEmpty ? null : referenceCode,
    );
  }

  Future<_ELibraryCitationLookupResult> _resolvedCitationForStableRef(
    String stableRef, {
    required Map<String, Future<_ELibraryCitationLookupResult>> referenceCache,
  }) {
    final normalized = stableRef.trim();
    if (normalized.isEmpty) {
      return Future<_ELibraryCitationLookupResult>.value(
        const _ELibraryCitationLookupResult(
          parsed: null,
          libraryItem: null,
          bookAbbreviation: null,
          citation: null,
          queryDescription: '(empty)',
          matchCount: 0,
          candidateSummary: '',
        ),
      );
    }
    return referenceCache.putIfAbsent(normalized, () async {
      final parsed = _parseStableRef(normalized);
      if (parsed == null) {
        return const _ELibraryCitationLookupResult(
          parsed: null,
          libraryItem: null,
          bookAbbreviation: null,
          citation: null,
          queryDescription: 'parse=(invalid)',
          matchCount: 0,
          candidateSummary: '',
        );
      }

      final itemId = parsed.itemId.trim();
      if (itemId.isEmpty) {
        return _ELibraryCitationLookupResult(
          parsed: parsed,
          libraryItem: null,
          bookAbbreviation: null,
          citation: null,
          queryDescription: 'itemId=(empty)',
          matchCount: 0,
          candidateSummary: '',
        );
      }

      final catalogItem = await LibraryCatalogService.instance.loadItemById(
        itemId,
      );
      final normalizedHref = _normalizedEpubHref(parsed.epubHref);
      final paragraphIndex = parsed.paragraphIndex;
      final spineIndex = parsed.spineIndex;
      final queryBits = <String>[
        'library_item_id=$itemId',
        if (spineIndex != null) 'spine_index=$spineIndex',
        if (paragraphIndex != null) 'paragraph_index=$paragraphIndex',
        if (normalizedHref.isNotEmpty) 'epub_href=$normalizedHref',
      ];
      if (catalogItem == null) {
        return _ELibraryCitationLookupResult(
          parsed: parsed,
          libraryItem: null,
          bookAbbreviation: null,
          citation: null,
          queryDescription: queryBits.join(' AND '),
          matchCount: 0,
          candidateSummary: '',
        );
      }

      final db = await UserDatabase.instance.database;
      final candidateRows = await _queryELibraryCitationRows(
        db: db,
        libraryItemId: catalogItem.id,
        spineIndex: spineIndex,
        paragraphIndex: paragraphIndex,
        normalizedHref: normalizedHref,
      );
      final citation = _citationFromELibraryRows(
        rows: candidateRows,
        parsedParagraphIndex: paragraphIndex,
      );

      return _ELibraryCitationLookupResult(
        parsed: parsed,
        libraryItem: catalogItem,
        bookAbbreviation: _libraryBookAbbreviation(catalogItem),
        citation: citation,
        queryDescription: queryBits.join(' AND '),
        matchCount: candidateRows.length,
        candidateSummary: _summarizeELibraryCitationCandidates(candidateRows),
      );
    });
  }

  void _logSourceEntries(
    List<HashTagEntry> entries,
    Map<int, _PresentationEntryDisplayData?> displayDataByEntryId,
  ) {
    if (!_enablePresentationGroupingDebugLogs) return;
    for (final entry in entries) {
      final displayData = displayDataByEntryId[entry.id];
      debugPrint(
        '[PresentationGroupingAdapter] source '
        'id=${entry.id} '
        'ref=${_debugReferenceForEntry(entry)} '
        'slide=${entry.presentationSlideNumber ?? 'auto'} '
        'type=${_debugSourceTypeForEntry(entry)} '
        'note=${_debugNoteState(entry)} '
        'title=${displayData?.slideTitle ?? _displayTitleForEntry(entry)}',
      );
    }
  }

  void _logSlide(PresentationSlide slide, int index) {
    if (!_enablePresentationGroupingDebugLogs) return;
    final references = slide.items
        .map(_debugReferenceForItem)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    debugPrint(
      '[PresentationGroupingAdapter] slide '
      'index=${index + 1} '
      'settingsKey=${slide.settingsKey} '
      'itemCount=${slide.items.length} '
      'refs=${references.join(', ')}',
    );
  }

  String _debugReferenceForEntry(HashTagEntry entry) {
    final verseRef = entry.verseRef.trim();
    if (verseRef.isNotEmpty) return verseRef;
    if (entry.bookNumber > 0 && entry.chapter > 0 && entry.verse > 0) {
      return '${entry.bookNumber}:${entry.chapter}:${entry.verse}';
    }
    return 'entry:${entry.id}';
  }

  String _debugReferenceForItem(PresentationSlideItem item) {
    if (item.itemKind == PresentationItemKind.note) {
      return 'note:${item.legacyItemId ?? item.sourceId}';
    }
    return item.sourceId;
  }

  String _debugSourceTypeForEntry(HashTagEntry entry) {
    if (_isNoteOnlyEntry(entry)) return 'note';
    if (_elibraryNoteMetadata(entry) != null) return 'elibrary_note';
    if (_isBibleVerseEntry(entry)) return 'verse';
    return 'tag_note';
  }

  String _debugNoteState(HashTagEntry entry) {
    final noteText = _resolvedNoteText(entry).trim();
    return noteText.isEmpty ? 'none' : 'attached';
  }

  _StableRefParts? _parseStableRef(String stableRef) {
    final parts = stableRef.split(':');
    if (parts.length < 4 || parts.first != 'elibrary') return null;
    final itemId = parts[1];
    final spineIndex = int.tryParse(parts[2]);
    final paragraphIndex = int.tryParse(parts[3]);
    final anchorId = parts.length > 4 ? parts[4] : '';
    final epubHref = parts.length > 5 ? parts.sublist(5).join(':') : '';
    return _StableRefParts(
      itemId: itemId,
      spineIndex: spineIndex,
      paragraphIndex: paragraphIndex,
      anchorId: anchorId,
      epubHref: epubHref,
    );
  }

  String _referenceCodeForEntry(
    HashTagEntry entry, {
    _ELibraryNoteMetadata? metadata,
    _ELibraryCitationLookupResult? lookup,
  }) {
    final direct = entry.referenceCode?.trim() ?? '';
    final safeDirect = _safeELibraryReferenceText(direct);
    if (safeDirect.isNotEmpty) {
      return safeDirect;
    }

    final noteMetadata = metadata ?? _elibraryNoteMetadata(entry);
    if (noteMetadata == null) return '';
    final lookupCitation = lookup?.citation;
    final citationText = noteMetadata.citationText.isNotEmpty
        ? noteMetadata.citationText
        : lookupCitation == null
        ? ''
        : '${lookupCitation.pageNumber}.${lookupCitation.paragraphNumber}';
    return libraryUserFacingELibraryCitationText(
      sourceTitle: noteMetadata.sourceTitle,
      sourceTitleAcronym: noteMetadata.sourceTitleAcronym,
      sourceLocation: noteMetadata.sourceLocation,
      sourceReferenceText: noteMetadata.sourceReferenceText,
      fileName: noteMetadata.sourceRelativePath.trim().isNotEmpty
          ? p.basename(noteMetadata.sourceRelativePath)
          : null,
      relativePath: noteMetadata.sourceRelativePath,
      pageCitation: citationText.isNotEmpty ? citationText : null,
      paragraphIndex:
          noteMetadata.sourceParagraphNumber ??
          noteMetadata.sourceParagraphIndex ??
          lookup?.parsed?.paragraphIndex,
    );
  }

  String _composeELibraryDisplayTitle({
    required String title,
    required String location,
  }) {
    final cleanTitle = title.trim();
    final cleanLocation = location.trim();
    if (cleanTitle.isNotEmpty && cleanLocation.isNotEmpty) {
      final lowerTitle = cleanTitle.toLowerCase();
      final lowerLocation = cleanLocation.toLowerCase();
      if (lowerLocation == lowerTitle ||
          lowerLocation.startsWith('$lowerTitle — ') ||
          lowerLocation.startsWith('$lowerTitle ')) {
        return cleanLocation;
      }
    }
    if (cleanTitle.isNotEmpty && cleanLocation.isNotEmpty) {
      return '$cleanTitle — $cleanLocation';
    }
    if (cleanTitle.isNotEmpty) return cleanTitle;
    if (cleanLocation.isNotEmpty) return cleanLocation;
    return '';
  }

  String _cleanDisplayText(String value) {
    final cleaned = value.trim();
    return cleaned.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<List<Map<String, Object?>>> _queryELibraryCitationRows({
    required Database db,
    required String libraryItemId,
    required int? spineIndex,
    required int? paragraphIndex,
    required String normalizedHref,
  }) async {
    final rows = <Map<String, Object?>>[];
    final seenKeys = <String>{};

    Future<void> addRows(
      String sql,
      List<Object?> args,
      String queryLabel,
    ) async {
      final queryRows = await db.rawQuery(sql, args);
      for (final row in queryRows) {
        final key = [
          row['paragraph_index']?.toString() ?? '',
          row['epub_href']?.toString() ?? '',
          row['anchor_id']?.toString() ?? '',
          row['original_reference_text']?.toString() ?? '',
        ].join('|');
        if (!seenKeys.add(key)) continue;
        rows.add({...row, '__query_label': queryLabel});
      }
    }

    if (normalizedHref.isNotEmpty) {
      await addRows(
        '''
        SELECT paragraph_index, anchor, original_reference_text, full_paragraph,
               epub_href, anchor_id, spine_index
        FROM library_links
        WHERE library_item_id = ?
          AND LOWER(REPLACE(REPLACE(COALESCE(epub_href, ''), '\\', '/'), './', '')) = ?
        ORDER BY paragraph_index ASC
        ''',
        [libraryItemId, normalizedHref],
        'href',
      );
    }

    if (rows.isEmpty && spineIndex != null && paragraphIndex != null) {
      final lowerBound = paragraphIndex > 24 ? paragraphIndex - 24 : 1;
      await addRows(
        '''
        SELECT paragraph_index, anchor, original_reference_text, full_paragraph,
               epub_href, anchor_id, spine_index
        FROM library_links
        WHERE library_item_id = ?
          AND spine_index = ?
          AND paragraph_index BETWEEN ? AND ?
        ORDER BY paragraph_index ASC
        ''',
        [libraryItemId, spineIndex, lowerBound, paragraphIndex],
        'spine+paragraph',
      );
    }

    if (rows.isEmpty && paragraphIndex != null) {
      final lowerBound = paragraphIndex > 24 ? paragraphIndex - 24 : 1;
      await addRows(
        '''
        SELECT paragraph_index, anchor, original_reference_text, full_paragraph,
               epub_href, anchor_id, spine_index
        FROM library_links
        WHERE library_item_id = ?
          AND paragraph_index BETWEEN ? AND ?
        ORDER BY paragraph_index ASC
        ''',
        [libraryItemId, lowerBound, paragraphIndex],
        'paragraph',
      );
    }

    return rows;
  }

  _ELibraryCitation? _citationFromELibraryRows({
    required List<Map<String, Object?>> rows,
    required int? parsedParagraphIndex,
  }) {
    for (final row in rows) {
      final texts = <String?>[
        row['original_reference_text']?.toString(),
        row['anchor']?.toString(),
        row['full_paragraph']?.toString(),
      ];
      for (final text in texts) {
        final citation = _citationFromText(text, parsedParagraphIndex);
        if (citation != null) return citation;
      }
    }
    return null;
  }

  _ELibraryCitation? _citationFromText(
    String? text,
    int? parsedParagraphIndex,
  ) {
    final clean = text?.trim() ?? '';
    if (clean.isEmpty) return null;

    final explicit = RegExp(r'(\d{1,4})\s*[.:]\s*(\d{1,3})').firstMatch(clean);
    if (explicit != null) {
      final pageNumber = int.tryParse(explicit.group(1)!);
      final paragraphNumber = int.tryParse(explicit.group(2)!);
      if (pageNumber != null && paragraphNumber != null) {
        return _ELibraryCitation(
          pageNumber: pageNumber,
          paragraphNumber: paragraphNumber,
        );
      }
    }

    final pageOnly = RegExp(r'\[(\d{1,4})\]').firstMatch(clean);
    if (pageOnly == null ||
        parsedParagraphIndex == null ||
        parsedParagraphIndex <= 0) {
      return null;
    }

    final pageNumber = int.tryParse(pageOnly.group(1)!);
    if (pageNumber == null) return null;
    return _ELibraryCitation(
      pageNumber: pageNumber,
      paragraphNumber: parsedParagraphIndex,
    );
  }

  String _summarizeELibraryCitationCandidates(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return '';
    return rows
        .take(3)
        .map((row) {
          final pieces = <String>[
            if ((row['original_reference_text']?.toString().trim() ?? '')
                .isNotEmpty)
              'orig=${row['original_reference_text']}',
            if ((row['anchor']?.toString().trim() ?? '').isNotEmpty)
              'anchor=${row['anchor']}',
            if ((row['epub_href']?.toString().trim() ?? '').isNotEmpty)
              'href=${_normalizedEpubHref(row['epub_href']?.toString() ?? '')}',
            if ((row['spine_index'] as num?)?.toInt() != null)
              'spine=${(row['spine_index'] as num).toInt()}',
            if ((row['paragraph_index'] as num?)?.toInt() != null)
              'paragraph=${(row['paragraph_index'] as num).toInt()}',
          ];
          return pieces.join(' ');
        })
        .join(' ; ');
  }

  String _resolvedELibraryTitle({
    required _ELibraryNoteMetadata metadata,
    required LibraryCatalogItem? libraryItem,
    required String? bookAbbreviation,
  }) {
    final catalogTitle = _safeELibraryTitle(libraryItem?.displayTitle ?? '');
    if (catalogTitle.isNotEmpty) return catalogTitle;

    final metadataTitle = _safeELibraryTitle(metadata.sourceTitle);
    if (metadataTitle.isNotEmpty) return metadataTitle;

    final abbreviation = _safeELibraryBookAbbreviation(bookAbbreviation ?? '');
    if (abbreviation.isNotEmpty) {
      return abbreviation;
    }

    return '';
  }

  String _safeELibraryTitle(String value) {
    final cleaned = _cleanDisplayText(value);
    if (cleaned.isEmpty || _looksLikeInternalELibraryText(cleaned)) {
      return '';
    }
    return cleaned;
  }

  String _safeELibraryReferenceText(String value) {
    return librarySafeUserFacingReferenceText(value) ?? '';
  }

  String _safeELibraryBookAbbreviation(String value) {
    return librarySafeUserFacingReferenceText(value) ?? '';
  }

  String _fallbackELibraryDisplayTitle({
    required _ELibraryNoteMetadata metadata,
    required _ELibraryCitationLookupResult lookup,
  }) {
    final title = _safeELibraryTitle(metadata.sourceTitle);
    if (title.isNotEmpty) return title;

    final citation = lookup.citation;
    final citationText = citation == null
        ? ''
        : '${citation.pageNumber}.${citation.paragraphNumber}';
    return libraryUserFacingELibraryDisplayLabel(
      sourceTitle: metadata.sourceTitle,
      sourceTitleAcronym: metadata.sourceTitleAcronym.isNotEmpty
          ? metadata.sourceTitleAcronym
          : (lookup.bookAbbreviation ?? ''),
      sourceLocation: metadata.sourceLocation,
      sourceReferenceText: metadata.sourceReferenceText,
      fileName: metadata.sourceRelativePath.trim().isNotEmpty
          ? p.basename(metadata.sourceRelativePath)
          : null,
      relativePath: metadata.sourceRelativePath,
      pageCitation: citationText.isNotEmpty ? citationText : null,
      paragraphIndex:
          metadata.sourceParagraphNumber ??
          metadata.sourceParagraphIndex ??
          lookup.parsed?.paragraphIndex,
    );
  }

  bool _looksLikeInternalELibraryText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return true;
    if (RegExp(r'^content\d+$', caseSensitive: false).hasMatch(trimmed)) {
      return true;
    }
    return trimmed.startsWith('elibrary:') ||
        trimmed.contains('::') ||
        trimmed.toLowerCase().contains('.xhtml') ||
        trimmed.toLowerCase().contains('oebps/') ||
        trimmed.toLowerCase() == 'book 0 0:0';
  }

  String _normalizedEpubHref(String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return '';
    return p
        .normalize(trimmed)
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^\./+'), '')
        .toLowerCase();
  }

  String? _libraryBookAbbreviation(LibraryCatalogItem item) {
    return libraryUserFacingBookAbbreviation(
      title: item.displayTitle,
      fileName: item.fileName,
      relativePath: item.relativePath,
    );
  }

  int? _intFromJson(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

class _ELibraryCitationLookupResult {
  const _ELibraryCitationLookupResult({
    required this.parsed,
    required this.libraryItem,
    required this.bookAbbreviation,
    required this.citation,
    required this.queryDescription,
    required this.matchCount,
    required this.candidateSummary,
  });

  final _StableRefParts? parsed;
  final LibraryCatalogItem? libraryItem;
  final String? bookAbbreviation;
  final _ELibraryCitation? citation;
  final String queryDescription;
  final int matchCount;
  final String candidateSummary;
}

class _PresentationSlideDraft {
  _PresentationSlideDraft._({required this.groupKey, this.assignedSlideNumber});

  factory _PresentationSlideDraft.assigned(int slideNumber) {
    return _PresentationSlideDraft._(
      groupKey: 'assigned-$slideNumber',
      assignedSlideNumber: slideNumber,
    );
  }

  factory _PresentationSlideDraft.implicit(int entryId) {
    return _PresentationSlideDraft._(groupKey: 'implicit-$entryId');
  }

  final String groupKey;
  final int? assignedSlideNumber;
  final List<_PresentationGroupedEntry> entries = <_PresentationGroupedEntry>[];

  String get slideId => 'presentation-slide-$groupKey';

  void addEntry(
    HashTagEntry entry, {
    _PresentationEntryDisplayData? displayData,
  }) {
    entries.add(
      _PresentationGroupedEntry(entry: entry, displayData: displayData),
    );
  }
}

class _PresentationGroupedEntry {
  const _PresentationGroupedEntry({required this.entry, this.displayData});

  final HashTagEntry entry;
  final _PresentationEntryDisplayData? displayData;
}

class _PresentationEntryDisplayData {
  const _PresentationEntryDisplayData({
    required this.slideTitle,
    required this.displayTitle,
    required this.sourceTitle,
    required this.sourceLocation,
    this.resolvedCitation,
  });

  final String slideTitle;
  final String displayTitle;
  final String sourceTitle;
  final String sourceLocation;
  final String? resolvedCitation;
}

class _ELibraryNoteMetadata {
  const _ELibraryNoteMetadata({
    required this.sourceTitle,
    required this.sourceTitleAcronym,
    required this.sourceLocation,
    required this.sourceReferenceText,
    required this.sourceHref,
    required this.sourceAnchorId,
    required this.sourceSpineIndex,
    required this.sourceParagraphIndex,
    required this.sourceRelativePath,
    required this.sourcePageNumber,
    required this.sourceParagraphNumber,
    required this.searchQuery,
    required this.sourceParagraph,
    required this.excerpt,
    required this.stableRef,
  });

  final String sourceTitle;
  final String sourceTitleAcronym;
  final String sourceLocation;
  final String sourceReferenceText;
  final String sourceHref;
  final String sourceAnchorId;
  final int? sourceSpineIndex;
  final int? sourceParagraphIndex;
  final String sourceRelativePath;
  final int? sourcePageNumber;
  final int? sourceParagraphNumber;
  final String searchQuery;
  final String sourceParagraph;
  final String excerpt;
  final String stableRef;

  String get citationText {
    final page = sourcePageNumber;
    final paragraph = sourceParagraphNumber;
    if (page != null && paragraph != null && page > 0 && paragraph > 0) {
      return '$page.$paragraph';
    }
    return '';
  }
}

class _StableRefParts {
  const _StableRefParts({
    required this.itemId,
    required this.spineIndex,
    required this.paragraphIndex,
    required this.anchorId,
    required this.epubHref,
  });

  final String itemId;
  final int? spineIndex;
  final int? paragraphIndex;
  final String anchorId;
  final String epubHref;
}

class _ELibraryCitation {
  const _ELibraryCitation({
    required this.pageNumber,
    required this.paragraphNumber,
  });

  final int pageNumber;
  final int paragraphNumber;
}

class _PresentationSourceInfo {
  const _PresentationSourceInfo({required this.type, required this.id});

  final String type;
  final String id;

  String toStableKey() => '$type:$id';
}
