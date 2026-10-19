import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'viewer_strongs_models.dart';
import 'viewer_strongs_repository.dart';

class ViewerStrongsPageOne extends StatefulWidget {
  const ViewerStrongsPageOne({
    super.key,
    required this.strongsId,
    required this.onOpenPageTwo,
    this.mappedPhrase,
    this.morphologyTag,
    this.scrollController,
    this.initialScrollOffset = 0,
    this.onSelectCitation,
    this.repository = const ViewerStrongsRepository(),
  });

  final String strongsId;
  final VoidCallback onOpenPageTwo;
  final String? mappedPhrase;
  final String? morphologyTag;
  final ScrollController? scrollController;
  final double initialScrollOffset;
  final void Function(int blockId, double panelScrollOffset)? onSelectCitation;
  final ViewerStrongsRepository repository;

  @override
  State<ViewerStrongsPageOne> createState() => _ViewerStrongsPageOneState();
}

class _ViewerStrongsPageOneState extends State<ViewerStrongsPageOne> {
  late Future<ViewerStrongsEntry?> _entryFuture;
  late Future<int> _verseCount;
  late Future<ViewerAbbottSmithEntry?> _abbottFuture;
  late Future<ViewerBdbEntry?> _bdbFuture;
  bool _restoredScroll = false;
  bool _showFullBdb = false;

  @override
  void initState() {
    super.initState();
    _entryFuture = widget.repository.loadEntry(widget.strongsId);
    _verseCount = widget.repository.loadOccurrenceCount(widget.strongsId);
    _abbottFuture = widget.repository.loadAbbottSmithEntry(widget.strongsId);
    _bdbFuture = widget.repository.loadBdbEntry(widget.strongsId);
  }

  @override
  void didUpdateWidget(covariant ViewerStrongsPageOne oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.strongsId != widget.strongsId ||
        oldWidget.repository != widget.repository) {
      _entryFuture = widget.repository.loadEntry(widget.strongsId);
      _verseCount = widget.repository.loadOccurrenceCount(widget.strongsId);
      _abbottFuture = widget.repository.loadAbbottSmithEntry(widget.strongsId);
      _bdbFuture = widget.repository.loadBdbEntry(widget.strongsId);
      _restoredScroll = false;
      _showFullBdb = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canonical =
        normalizeStrongsCanonical(widget.strongsId) ?? widget.strongsId.trim();
    return FutureBuilder(
      future: _entryFuture,
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final entry = snapshot.data;

        return Material(
          color: theme.colorScheme.surface,
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry?.lemma.isNotEmpty == true
                          ? entry!.lemma
                          : canonical,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFamily: 'NotoSerif',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close word details',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    "Strong's $canonical",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  FutureBuilder<int>(
                    future: _verseCount,
                    builder: (context, countSnapshot) {
                      if (!countSnapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      return ActionChip(
                        avatar: const Icon(Icons.bar_chart, size: 17),
                        label: Text('Found in ${countSnapshot.data} verses'),
                        labelStyle: theme.textTheme.labelLarge?.copyWith(
                          fontFamily: 'Roboto',
                        ),
                        onPressed: widget.onOpenPageTwo,
                      );
                    },
                  ),
                ],
              ),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (snapshot.connectionState == ConnectionState.done &&
                  entry == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    "Strong's entry not found.",
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              if (entry != null) ...[
                if (entry.transliteration.isNotEmpty ||
                    entry.pronunciation.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      [
                        if (entry.transliteration.isNotEmpty)
                          entry.transliteration,
                        if (entry.pronunciation.isNotEmpty) entry.pronunciation,
                      ].join(' · '),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                if (entry.language.isNotEmpty || entry.partOfSpeech.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (entry.language.isNotEmpty)
                          entry.language == 'H' ? 'Hebrew' : 'Greek',
                        if (entry.partOfSpeech.isNotEmpty) entry.partOfSpeech,
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (widget.mappedPhrase?.trim().isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'In this verse: “${widget.mappedPhrase!.trim()}”',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                FutureBuilder<ViewerAbbottSmithEntry?>(
                  future: _abbottFuture,
                  builder: (context, abbottSnapshot) {
                    final abbott = abbottSnapshot.data;
                    if (abbottSnapshot.connectionState !=
                        ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!_restoredScroll && widget.initialScrollOffset > 0) {
                      _restoredScroll = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final controller = widget.scrollController;
                        if (!mounted ||
                            controller == null ||
                            !controller.hasClients) {
                          return;
                        }
                        controller.jumpTo(
                          widget.initialScrollOffset.clamp(
                            controller.position.minScrollExtent,
                            controller.position.maxScrollExtent,
                          ),
                        );
                      });
                    }
                    final hasAbbott =
                        abbott != null && abbott.senses.isNotEmpty;
                    if (!hasAbbott &&
                        entry.shortDefinition.isEmpty &&
                        abbott?.related.isNotEmpty != true) {
                      return const SizedBox.shrink();
                    }
                    final definitionText = hasAbbott
                        ? [
                            for (final sense in abbott.senses)
                              '${sense.number} ${sense.parts.map((part) => part.text).join()}'
                                  .trim(),
                          ].join('\n')
                        : entry.shortDefinition;
                    final copyText = [
                      if (entry.lemma.trim().isNotEmpty) entry.lemma.trim(),
                      "Strong's ${entry.strongsId}",
                      if (entry.transliteration.trim().isNotEmpty)
                        'Transliteration: ${entry.transliteration}',
                      if (entry.pronunciation.trim().isNotEmpty)
                        'Pronunciation: ${entry.pronunciation}',
                      [
                        entry.language,
                        entry.partOfSpeech,
                      ].where((value) => value.trim().isNotEmpty).join(' · '),
                      if (definitionText.trim().isNotEmpty) definitionText,
                    ].where((value) => value.trim().isNotEmpty).join('\n');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: copyText),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Entry copied')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy entry'),
                        ),
                        const SizedBox(height: 12),
                        Divider(color: theme.colorScheme.outlineVariant),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            hasAbbott
                                ? 'Meanings and Scripture examples'
                                : 'Brief definition',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (hasAbbott) ...[
                          if (entry.shortDefinition.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                "Strong's: ${entry.shortDefinition}",
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          for (final sense in abbott.senses)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text.rich(
                                TextSpan(
                                  style: theme.textTheme.bodyLarge,
                                  children: [
                                    if (sense.number.isNotEmpty)
                                      TextSpan(
                                        text: '${sense.number} ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ..._senseSpans(context, sense.parts),
                                  ],
                                ),
                              ),
                            ),
                          if (abbott.related.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Related terms',
                              style: theme.textTheme.labelLarge,
                            ),
                            for (final parts in abbott.related)
                              Text.rich(
                                TextSpan(
                                  style: theme.textTheme.bodyMedium,
                                  children: _senseSpans(context, parts),
                                ),
                              ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'George Abbott-Smith · A Manual Greek Lexicon of the New Testament (1922) · Public domain',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ] else ...[
                          if (entry.shortDefinition.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                entry.shortDefinition,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                          if (abbott?.related.isNotEmpty == true) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Abbott-Smith source note',
                              style: theme.textTheme.labelLarge,
                            ),
                            for (final parts in abbott!.related)
                              Text.rich(
                                TextSpan(
                                  style: theme.textTheme.bodyMedium,
                                  children: _senseSpans(context, parts),
                                ),
                              ),
                          ],
                        ],
                      ],
                    );
                  },
                ),
                FutureBuilder<ViewerBdbEntry?>(
                  future: _bdbFuture,
                  builder: (context, bdbSnapshot) {
                    final bdb = bdbSnapshot.data;
                    if (bdb == null || bdb.text.trim().isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Brown-Driver-Briggs',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          bdb.text,
                          maxLines: _showFullBdb ? null : 5,
                          overflow: _showFullBdb
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (bdb.text.length > 300)
                          TextButton(
                            onPressed: () =>
                                setState(() => _showFullBdb = !_showFullBdb),
                            child: Text(
                              _showFullBdb ? 'Show less' : 'Read full entry',
                            ),
                          ),
                        Text(
                          'BDB (1906) · BibleAquifer CC0 · ${bdb.articleId}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<InlineSpan> _senseSpans(
    BuildContext context,
    List<ViewerLexiconPart> parts,
  ) => [
    for (final part in parts)
      if (part.blockId == null || widget.onSelectCitation == null)
        TextSpan(text: part.text)
      else
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: InkWell(
            onTap: () {
              final offset = widget.scrollController?.hasClients == true
                  ? widget.scrollController!.offset
                  : 0.0;
              Navigator.of(context).pop();
              widget.onSelectCitation!(part.blockId!, offset);
            },
            child: Text(
              part.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
  ];
}
