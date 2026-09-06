import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Generates a placeholder cover for a Pioneer library title that has no
/// cover image embedded in its own EPUB: the shared burgundy-leather
/// template with the book's title and author composited on top.
///
/// This is a write-time step (called once, at import) rather than something
/// re-run on every catalog read — see [LibraryEpubCoverExtractor] for the
/// "does this EPUB already have its own cover" check that decides whether
/// this generator should run at all.
class PioneerCoverGeneratorService {
  const PioneerCoverGeneratorService._();

  static const PioneerCoverGeneratorService instance =
      PioneerCoverGeneratorService._();

  static const String templateAssetKey =
      'assets/library_covers/templates/pioneer_cover_template.png';

  static const String _serifFontFamily = 'PlayfairDisplay';

  // Fractional boxes within the template that the base cover leaves clear of
  // ornamentation, measured against the 1254x1254 source template.
  static const double _titleLeft = 0.13;
  static const double _titleTop = 0.22;
  static const double _titleWidth = 0.74;
  static const double _titleHeight = 0.42;

  static const double _authorLeft = 0.18;
  static const double _authorTop = 0.75;
  static const double _authorWidth = 0.64;
  static const double _authorHeight = 0.08;

  static ui.Image? _cachedTemplate;

  /// Renders the template with [title] and [author] composited on it and
  /// returns encoded PNG bytes.
  Future<Uint8List> generateCoverPng({
    required String title,
    required String author,
  }) async {
    final template = await _loadTemplate();
    final width = template.width.toDouble();
    final height = template.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.drawImage(template, Offset.zero, Paint());

    _drawFittedText(
      canvas: canvas,
      rect: Rect.fromLTWH(
        width * _titleLeft,
        height * _titleTop,
        width * _titleWidth,
        height * _titleHeight,
      ),
      text: title.trim().isEmpty ? 'Untitled' : title.trim(),
      minFontSize: height * 0.022,
      maxFontSize: height * 0.088,
      maxLines: 4,
      style: const TextStyle(
        fontFamily: _serifFontFamily,
        fontWeight: FontWeight.bold,
        color: Color(0xFFF4E0B0),
        shadows: <Shadow>[
          Shadow(color: Color(0xCC1A0505), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
    );

    if (author.trim().isNotEmpty) {
      _drawFittedText(
        canvas: canvas,
        rect: Rect.fromLTWH(
          width * _authorLeft,
          height * _authorTop,
          width * _authorWidth,
          height * _authorHeight,
        ),
        text: author.trim(),
        minFontSize: height * 0.016,
        maxFontSize: height * 0.036,
        maxLines: 2,
        style: const TextStyle(
          fontFamily: _serifFontFamily,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE6D2A0),
          shadows: <Shadow>[
            Shadow(color: Color(0xCC1A0505), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.round(), height.round());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (byteData == null) {
      throw StateError('Failed to encode generated Pioneer cover as PNG.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<ui.Image> _loadTemplate() async {
    final cached = _cachedTemplate;
    if (cached != null) return cached;
    final data = await rootBundle.load(templateAssetKey);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    _cachedTemplate = frame.image;
    return frame.image;
  }

  /// Centers [text] within [rect], shrinking the font (via binary search,
  /// mirroring the auto-fit approach already used for presentation slides in
  /// `presentation_slide_canvas.dart`) until it wraps within both the width
  /// and height of the box, down to [minFontSize].
  void _drawFittedText({
    required Canvas canvas,
    required Rect rect,
    required String text,
    required double minFontSize,
    required double maxFontSize,
    required int maxLines,
    required TextStyle style,
  }) {
    bool fits(double fontSize, TextPainter painter) {
      painter.text = TextSpan(text: text, style: style.copyWith(fontSize: fontSize));
      painter.layout(maxWidth: rect.width);
      return !painter.didExceedMaxLines && painter.height <= rect.height;
    }

    final probe = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    );

    var low = minFontSize;
    var high = maxFontSize;
    var best = minFontSize;
    if (!fits(minFontSize, probe)) {
      best = minFontSize;
    } else {
      while ((high - low) > 0.5) {
        final mid = (low + high) / 2;
        if (fits(mid, probe)) {
          best = mid;
          low = mid;
        } else {
          high = mid;
        }
      }
    }

    final painter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: best)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: rect.width);

    final offset = Offset(
      rect.left + (rect.width - painter.width) / 2,
      rect.top + (rect.height - painter.height) / 2,
    );
    painter.paint(canvas, offset);
  }
}
