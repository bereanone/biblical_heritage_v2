import 'package:flutter/material.dart';

class ViewerReferenceTitle extends StatelessWidget {
  const ViewerReferenceTitle({
    super.key,
    required this.bookName,
    required this.chapter,
    this.verse,
    required this.baseStyle,
    required this.minimumFontSize,
    required this.maxWidth,
  });

  final String bookName;
  final int chapter;
  final int? verse;
  final TextStyle baseStyle;
  final double minimumFontSize;
  final double maxWidth;

  static const Map<String, String> _bookAbbreviations = {
    'Genesis': 'Gen.',
    'Exodus': 'Ex.',
    'Leviticus': 'Lev.',
    'Numbers': 'Num.',
    'Deuteronomy': 'Deut.',
    'Joshua': 'Josh.',
    'Judges': 'Judg.',
    '1 Samuel': '1 Sam.',
    '2 Samuel': '2 Sam.',
    '1 Kings': '1 Kgs.',
    '2 Kings': '2 Kgs.',
    '1 Chronicles': '1 Chr.',
    '2 Chronicles': '2 Chr.',
    'Ecclesiastes': 'Eccl.',
    'Song of Solomon': 'Song',
    'Lamentations': 'Lam.',
    'Ezekiel': 'Ezek.',
    'Obadiah': 'Obad.',
    'Habakkuk': 'Hab.',
    'Zechariah': 'Zech.',
    'Matthew': 'Matt.',
    'Mark': 'Mk.',
    'Luke': 'Lk.',
    'John': 'Jn.',
    'Romans': 'Rom.',
    '1 Corinthians': '1 Cor.',
    '2 Corinthians': '2 Cor.',
    'Galatians': 'Gal.',
    'Ephesians': 'Eph.',
    'Philippians': 'Phil.',
    'Colossians': 'Col.',
    '1 Thessalonians': '1 Thess.',
    '2 Thessalonians': '2 Thess.',
    '1 Timothy': '1 Tim.',
    '2 Timothy': '2 Tim.',
    'Philemon': 'Philem.',
    'Hebrews': 'Heb.',
    'James': 'Jas.',
    '1 Peter': '1 Pet.',
    '2 Peter': '2 Pet.',
    '1 John': '1 Jn.',
    '2 John': '2 Jn.',
    '3 John': '3 Jn.',
    'Revelation': 'Rev.',
  };

  String _referenceText(String name) {
    if (chapter <= 0) return name;
    return verse != null ? '$name $chapter:$verse' : '$name $chapter';
  }

  String _compactBook(String name) {
    final mapped = _bookAbbreviations[name] ?? name;
    if (mapped.length <= 10) return mapped;
    final parts = mapped.split(' ');
    if (parts.length >= 2 && int.tryParse(parts.first) != null) {
      final word = parts[1];
      final short = word.length <= 5 ? word : '${word.substring(0, 4)}.';
      return '${parts.first} $short';
    }
    final token = parts.first;
    return token.length <= 5 ? token : '${token.substring(0, 4)}.';
  }

  bool _fits(
    BuildContext context,
    String text,
    TextStyle style,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: double.infinity);
    return painter.width <= width;
  }

  @override
  Widget build(BuildContext context) {
    final baseFontSize = baseStyle.fontSize ?? 20;
    final minFontSize = minimumFontSize.clamp(0, baseFontSize);
    final candidates = <String>[
      _referenceText(bookName),
      _referenceText(_bookAbbreviations[bookName] ?? bookName),
      _referenceText(_compactBook(bookName)),
    ];

    for (final candidate in candidates) {
      for (double size = baseFontSize; size >= minFontSize; size -= 1) {
        final trialStyle = baseStyle.copyWith(fontSize: size);
        if (_fits(context, candidate, trialStyle, maxWidth)) {
          return Text(
            candidate,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: trialStyle,
          );
        }
      }
    }

    final fallbackStyle = baseStyle.copyWith(fontSize: minFontSize.toDouble());
    final fallbackText = candidates.last;
    return Text(
      fallbackText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: fallbackStyle,
    );
  }
}
