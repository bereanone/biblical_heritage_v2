import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'viewer_strongs_models.dart';
import 'viewer_strongs_repository.dart';

class ViewerStrongsPageOne extends StatefulWidget {
  const ViewerStrongsPageOne({
    super.key,
    required this.strongsId,
    required this.onOpenPageTwo,
    this.repository = const ViewerStrongsRepository(),
  });

  final String strongsId;
  final VoidCallback onOpenPageTwo;
  final ViewerStrongsRepository repository;

  @override
  State<ViewerStrongsPageOne> createState() => _ViewerStrongsPageOneState();
}

class _ViewerStrongsPageOneState extends State<ViewerStrongsPageOne> {
  bool _showCopiedBanner = false;

  Future<void> _copyEntry(ViewerStrongsEntry entry) async {
    await Clipboard.setData(ClipboardData(text: _buildClipboardText(entry)));
    if (!mounted) return;
    setState(() {
      _showCopiedBanner = true;
    });
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _showCopiedBanner = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final canonical =
        normalizeStrongsCanonical(widget.strongsId) ?? widget.strongsId.trim();
    return FutureBuilder(
      future: widget.repository.loadEntry(canonical),
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final entry = snapshot.data;

        return Material(
          color: theme.colorScheme.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Strong's $canonical",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy to Clipboard',
                    onPressed: entry == null ? null : () => _copyEntry(entry),
                    icon: const Icon(Icons.copy),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (_showCopiedBanner)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.onPrimaryContainer,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Strong's entry copied to clipboard.",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                if (entry.lemma.isNotEmpty)
                  Text(
                    entry.lemma,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (entry.transliteration.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      entry.transliteration,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (entry.shortDefinition.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entry.shortDefinition,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                if (entry.partOfSpeech.isNotEmpty ||
                    entry.pronunciation.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      [
                        if (entry.language.isNotEmpty)
                          entry.language == 'H' ? 'Hebrew' : 'Greek',
                        if (entry.partOfSpeech.isNotEmpty) entry.partOfSpeech,
                        if (entry.pronunciation.isNotEmpty) entry.pronunciation,
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Open occurrence results',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Show page 2 with all verse occurrences',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenPageTwo,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _buildClipboardText(ViewerStrongsEntry entry) {
  final languageLabel = switch (entry.language) {
    'H' => 'Hebrew',
    'G' => 'Greek',
    _ => 'Original Language',
  };
  final lines = <String>["Strong's ${entry.strongsId}"];

  if (entry.lemma.isNotEmpty) {
    lines.add('Lemma: ${entry.lemma}');
  }
  if (entry.transliteration.isNotEmpty) {
    lines.add('Transliteration: ${entry.transliteration}');
  }
  if (entry.pronunciation.isNotEmpty) {
    lines.add('Pronunciation: ${entry.pronunciation}');
  }
  if (entry.partOfSpeech.isNotEmpty) {
    lines.add('Part of Speech: ${entry.partOfSpeech}');
  }
  lines.add('Language: $languageLabel');

  if (entry.shortDefinition.isNotEmpty) {
    lines.add('');
    lines.add('Definition:');
    lines.add(entry.shortDefinition);
  }

  return lines.join('\n');
}
