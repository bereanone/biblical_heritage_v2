part of 'library_book_reader_screen.dart';

class _ReaderHeadingTarget {
  const _ReaderHeadingTarget({required this.key, required this.offset});

  final String key;
  final double offset;
}

class _SectionBlockView extends StatelessWidget {
  const _SectionBlockView({
    super.key,
    required this.block,
    required this.blockIndex,
    required this.geometryRegistry,
    required this.geometryScopeId,
    required this.geometryRevision,
    required this.sectionTitle,
    required this.sectionEntryName,
    required this.paragraphIndex,
    required this.textColor,
    required this.subduedColor,
    required this.bodyFontSize,
    required this.searchQuery,
    required this.highlightTerms,
    required this.topPadding,
    required this.bottomPadding,
    required this.isNightMode,
    required this.showRefCodes,
    required this.referenceCode,
    required this.hasUserMarkup,
    required this.selectionHighlightSpec,
    required this.rangeSelection,
    required this.persistedHighlights,
    required this.onBlockTap,
    required this.onWordLongPress,
    required this.onWordLongPressMove,
    required this.onWordLongPressMoveDetails,
    required this.onWordTap,
    required this.textKey,
    required this.diagnosticLoggingEnabled,
  });

  final LibraryBookBlock block;
  final int blockIndex;
  final TextRangeGeometryRegistry geometryRegistry;
  final String geometryScopeId;
  final int geometryRevision;
  final String sectionTitle;
  final String sectionEntryName;
  final int? paragraphIndex;
  final Color textColor;
  final Color subduedColor;
  final double bodyFontSize;
  final String? searchQuery;
  final List<String> highlightTerms;
  final double topPadding;
  final double bottomPadding;
  final bool isNightMode;
  final bool showRefCodes;
  final String? referenceCode;
  final bool hasUserMarkup;
  final HighlightRenderSpec selectionHighlightSpec;
  final LibraryRangeSelection rangeSelection;
  final List<ElibraryMarkupRecord> persistedHighlights;
  final VoidCallback? onBlockTap;
  final ValueChanged<int> onWordLongPress;
  final ValueChanged<int> onWordLongPressMove;
  final ValueChanged<LongPressMoveUpdateDetails>? onWordLongPressMoveDetails;
  final ValueChanged<int> onWordTap;
  final Key? textKey;
  final bool diagnosticLoggingEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHeading = block.isHeading;
    final isBlockquote = block.isBlockquote;
    final className = block.className ?? '';
    final isChapterTitle = isHeading && _hasEpubClass(className, 'chapterhead');
    final isSectionTitle = isHeading && _hasEpubClass(className, 'sectionhead');
    final isDevotionalLead =
        _hasEpubClass(className, 'devotionaltext') ||
        _hasEpubClass(className, 'bibletext') ||
        _hasEpubClass(className, 'center');
    final fontSize = isChapterTitle
        ? bodyFontSize * 1.95
        : isHeading
        ? bodyFontSize * _headingFontScale(block.headingLevel)
        : isDevotionalLead
        ? bodyFontSize * 1.02
        : bodyFontSize;
    final textAlign = isChapterTitle || isSectionTitle || isDevotionalLead
        ? TextAlign.center
        : TextAlign.start;
    final style =
        (isChapterTitle
                ? theme.textTheme.headlineSmall
                : isHeading
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodyLarge)
            ?.copyWith(
              color: textColor,
              fontWeight: isChapterTitle || isSectionTitle || isDevotionalLead
                  ? FontWeight.w800
                  : isHeading
                  ? FontWeight.w700
                  : FontWeight.w400,
              fontSize: fontSize,
              height: isChapterTitle
                  ? 1.12
                  : isHeading
                  ? 1.35
                  : isDevotionalLead
                  ? 1.45
                  : isBlockquote
                  ? 1.7
                  : 1.6,
              fontStyle: isBlockquote ? FontStyle.italic : null,
            );
    final resolvedStyle =
        style ??
        theme.textTheme.bodyLarge?.copyWith(color: textColor) ??
        TextStyle(color: textColor, fontSize: bodyFontSize, height: 1.6);
    final cleanReferenceCode = showRefCodes
        ? cleanDisplayRefCode(referenceCode)
        : null;
    final appendedRefString =
        cleanReferenceCode != null && cleanReferenceCode.isNotEmpty
        ? '{$cleanReferenceCode}'
        : null;
    final hasRefCodeSpan = appendedRefString != null;
    final geometrySeeds = <TextRangeLayoutSeed>[];
    final textSpan = TextSpan(
      style: resolvedStyle,
      children: [
        ...buildLibraryInteractiveEpubSpans(
          html: block.html,
          fallbackText: block.text,
          baseStyle: resolvedStyle,
          selectionHighlightSpec: selectionHighlightSpec,
          isNightMode: isNightMode,
          blockIndex: blockIndex,
          rangeSelection: rangeSelection,
          persistedHighlights: persistedHighlights,
          onWordLongPress: onWordLongPress,
          onWordTap: onWordTap,
          onWordLongPressMove: onWordLongPressMove,
          onWordLongPressMoveDetails: onWordLongPressMoveDetails,
          enableWordLongPressRecognizers: true,
          highlightQuery: searchQuery,
          highlightTerms: highlightTerms,
          geometryScopeId: geometryScopeId,
          geometryContentKey: _geometryContentKeyForBlock(block, blockIndex),
          geometrySeeds: _enableTextRangeGeometry ? geometrySeeds : null,
        ),
        if (appendedRefString != null) ...[
          const TextSpan(text: ' '),
          TextSpan(
            text: appendedRefString,
            style: resolvedStyle.copyWith(
              color: subduedColor,
              fontSize: (resolvedStyle.fontSize ?? bodyFontSize) * 0.86,
              fontWeight: hasUserMarkup ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ],
    );

    if (diagnosticLoggingEnabled && kDebugMode) {
      final rawPreview = block.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final preview = rawPreview.length > 60
          ? rawPreview.substring(0, 60)
          : rawPreview;
      debugPrint(
        '[LibraryBookReader] render paragraph '
        'showRefCodes=$showRefCodes '
        'blockType=${block.kind} '
        'paragraphIndex=${paragraphIndex ?? '(none)'} '
        'href=${sectionEntryName.isEmpty ? '(none)' : sectionEntryName} '
        'sectionTitle=${sectionTitle.isEmpty ? '(none)' : sectionTitle} '
        'rawPreview=${preview.isEmpty ? '(none)' : preview} '
        'cleanRefCodeCandidate=${cleanReferenceCode ?? '(null)'} '
        'finalAppendedRef=${appendedRefString ?? '(none)'} '
        'renderer=SelectableText.rich '
        'textSpanIncludesRefCodeSpan=$hasRefCodeSpan',
      );
    }

    final bodyChild = _enableTextRangeGeometry
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPressStart: (details) {
              final anchor = geometryRegistry.nearestAnchorToGlobalPoint(
                details.globalPosition,
                sourceKind: TextRangeSourceKind.elibrary,
                scopeId: geometryScopeId,
              );
              if (anchor == null) return;
              onWordLongPress(anchor.tokenIndex);
            },
            onLongPressMoveUpdate: (details) {
              final anchor = geometryRegistry.nearestAnchorToGlobalPoint(
                details.globalPosition,
                sourceKind: TextRangeSourceKind.elibrary,
                scopeId: geometryScopeId,
              );
              if (anchor == null) return;
              onWordLongPressMove(anchor.tokenIndex);
            },
            child: TextRangeGeometryReporter(
              registry: geometryRegistry,
              scopeId: geometryScopeId,
              sourceKind: TextRangeSourceKind.elibrary,
              text: textSpan,
              seeds: geometrySeeds,
              geometryRevision: geometryRevision,
              textDirection: Directionality.of(context),
              textAlign: textAlign,
              child: Text.rich(textSpan, textAlign: textAlign, key: textKey),
            ),
          )
        : Text.rich(textSpan, textAlign: textAlign, key: textKey);

    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onBlockTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: isBlockquote
                ? Border(
                    left: BorderSide(
                      color: _readerBorderColor(
                        theme,
                        isNightMode,
                      ).withValues(alpha: 0.65),
                      width: 2,
                    ),
                  )
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.only(left: isBlockquote ? 12 : 0),
            child: bodyChild,
          ),
        ),
      ),
    );
  }
}

String _geometryContentKeyForBlock(LibraryBookBlock block, int index) {
  final anchorId = block.anchorId?.trim();
  if (anchorId != null && anchorId.isNotEmpty) {
    return 'anchor:${_normalizeBlockKeyStandalone(anchorId)}';
  }
  final bodyOrder = block.bodyOrder;
  if (bodyOrder != null) {
    return 'body:$bodyOrder';
  }
  return 'block:$index';
}

String _normalizeBlockKeyStandalone(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
