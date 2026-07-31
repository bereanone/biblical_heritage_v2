import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import 'viewer_interlinear_settings.dart';

class ViewerInterlinearTokenTile extends StatelessWidget {
  const ViewerInterlinearTokenTile({
    super.key,
    required this.token,
    required this.settings,
    required this.englishStyle,
    required this.originalStyle,
    required this.metaStyle,
    this.onOpenStrongs,
  });

  final InterlinearTokenRecord token;
  final ViewerInterlinearSettings settings;
  final TextStyle englishStyle;
  final TextStyle originalStyle;
  final TextStyle metaStyle;
  final ValueChanged<String>? onOpenStrongs;

  @override
  Widget build(BuildContext context) {
    final englishText =
        (token.english.trim().isNotEmpty && token.english != '.')
        ? token.english.replaceAll('-', '\u2011')
        : ' ';
    final originalText =
        (token.original.trim().isNotEmpty && token.original != '.')
        ? token.original
        : ' ';
    final transliterationText = token.transliteration.trim().isNotEmpty
        ? token.transliteration
        : ' ';
    final pronunciationText = token.pronunciation.trim().isNotEmpty
        ? token.pronunciation
        : ' ';
    final strongsText = token.strongsNumber.trim().isNotEmpty
        ? token.strongsNumber
        : ' ';
    final morphologyText = token.morphology.trim();
    final canOpenStrongs = token.strongsNumber.trim().isNotEmpty;
    final linkColor = Theme.of(context).colorScheme.primary;
    final linkedOriginalStyle = originalStyle.copyWith(
      color: canOpenStrongs ? linkColor : originalStyle.color,
      decoration: canOpenStrongs
          ? TextDecoration.underline
          : TextDecoration.none,
      decorationColor: canOpenStrongs ? linkColor : null,
    );
    final linkedMetaStyle = metaStyle.copyWith(
      color: canOpenStrongs ? linkColor : metaStyle.color,
      decoration: canOpenStrongs
          ? TextDecoration.underline
          : TextDecoration.none,
      decorationColor: canOpenStrongs ? linkColor : null,
      fontWeight: canOpenStrongs ? FontWeight.w700 : metaStyle.fontWeight,
    );

    void open() {
      final strongs = token.strongsNumber.trim();
      if (strongs.isEmpty) return;
      onOpenStrongs?.call(strongs);
    }

    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (settings.showEnglishGloss)
            Text(englishText, style: englishStyle, textAlign: TextAlign.center),
          if (settings.showOriginalText)
            GestureDetector(
              onTap: canOpenStrongs ? open : null,
              child: Text(
                originalText,
                style: linkedOriginalStyle,
                textAlign: TextAlign.center,
              ),
            ),
          if (settings.showTransliteration)
            Text(
              transliterationText,
              style: metaStyle,
              textAlign: TextAlign.center,
            ),
          if (settings.showPronunciation)
            Text(
              pronunciationText,
              style: metaStyle,
              textAlign: TextAlign.center,
            ),
          if (settings.showStrongsNumber)
            GestureDetector(
              onTap: canOpenStrongs ? open : null,
              child: Text(
                strongsText,
                style: linkedMetaStyle,
                textAlign: TextAlign.center,
              ),
            ),
          if (settings.showMorphology && morphologyText.isNotEmpty) ...[
            const SizedBox(height: 2),
            _MorphologyBubble(
              morphology: morphologyText,
              style: metaStyle.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MorphologyBubble extends StatelessWidget {
  const _MorphologyBubble({required this.morphology, required this.style});

  final String morphology;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final compact = _compactMorphology(morphology);
    if (compact.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _morphColor(compact),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(compact, style: style, textAlign: TextAlign.center),
    );
  }
}

Color _morphColor(String value) {
  final upper = value.toUpperCase();
  if (upper.startsWith('C')) {
    return Colors.teal.shade600;
  }
  if (upper.startsWith('T')) {
    return Colors.brown.shade400;
  }
  if (upper.startsWith('N')) {
    return Colors.green.shade600;
  }
  if (upper.startsWith('A')) {
    return Colors.green.shade600;
  }
  if (upper.startsWith('V')) {
    return Colors.blue.shade600;
  }
  if (upper.startsWith('P') || upper.startsWith('R') || upper.startsWith('D')) {
    return Colors.teal.shade500;
  }
  return Colors.blueGrey.shade400;
}

String _compactMorphology(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '';
  final parts = normalized
      .split('/')
      .map((part) => part.replaceAll('-', '').trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  const primaryOrder = ['N', 'V', 'A', 'P', 'C', 'T', 'R', 'D', 'S', 'H'];
  for (final tag in primaryOrder) {
    for (final part in parts) {
      if (part.toUpperCase().startsWith(tag)) {
        return part;
      }
    }
  }
  return parts.first;
}
