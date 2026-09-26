import 'dart:convert';
import 'dart:typed_data';

/// Lossless support for simple SVG wrappers containing one rotated raster.
/// This is deliberately not a general SVG renderer: unsupported structure,
/// external resources and transformations are rejected, never silently ignored.
class LibraryEmbeddedRaster {
  const LibraryEmbeddedRaster(this.bytes, this.quarterTurns);
  final Uint8List bytes;
  final int quarterTurns;

  static LibraryEmbeddedRaster parse(String svg) {
    final document = RegExp(
      r'^\s*(?:<\?xml[^?]*\?>\s*)?<svg\b([^>]*)>\s*<image\b([^>]*)/\s*>\s*</svg>\s*$',
      dotAll: true,
    ).firstMatch(svg);
    if (document == null) {
      throw const FormatException('Unsupported SVG structure');
    }
    Map<String, String> attributes(String text, Set<String> allowed) {
      final result = <String, String>{};
      final expression = RegExp(
        '([\\w:]+)\\s*=\\s*(["\x27])(.*?)\\2',
        dotAll: true,
      );
      var end = 0;
      for (final match in expression.allMatches(text)) {
        if (text.substring(end, match.start).trim().isNotEmpty ||
            !allowed.contains(match[1]) ||
            result.containsKey(match[1])) {
          throw const FormatException('Unsupported SVG attribute');
        }
        result[match[1]!] = match[3]!;
        end = match.end;
      }
      if (text.substring(end).trim().isNotEmpty) {
        throw const FormatException('Malformed SVG attribute');
      }
      return result;
    }

    final root = attributes(document[1]!, {
      'xmlns',
      'xmlns:xlink',
      'version',
      'width',
      'height',
      'viewBox',
    });
    final image = attributes(document[2]!, {
      'width',
      'height',
      'transform',
      'xlink:href',
      'href',
    });
    double number(String? value) {
      final result = double.tryParse(value ?? '');
      if (result == null || !result.isFinite || result <= 0) {
        throw const FormatException('Invalid SVG dimension');
      }
      return result;
    }

    final width = number(root['width']), height = number(root['height']);
    final iw = number(image['width']), ih = number(image['height']);
    final viewBox = root['viewBox']
        ?.split(RegExp(r'\s+'))
        .map(double.tryParse)
        .toList();
    if (viewBox == null ||
        viewBox.length != 4 ||
        viewBox[0] != 0 ||
        viewBox[1] != 0 ||
        viewBox[2] != width ||
        viewBox[3] != height ||
        width != ih ||
        height != iw) {
      throw const FormatException('Unsupported SVG viewport');
    }
    final transform = RegExp(
      r'^translate\(([\d.]+),\s*([\d.]+)\)\s+rotate\((90|270)\)$',
    ).firstMatch(image['transform'] ?? '');
    if (transform == null) {
      throw const FormatException('Unsupported SVG transform');
    }
    final turns = int.parse(transform[3]!) ~/ 90;
    if (double.tryParse(transform[1]!) != (turns == 1 ? width : 0) ||
        double.tryParse(transform[2]!) != (turns == 3 ? height : 0)) {
      throw const FormatException('Unsupported SVG translation');
    }
    if (image.containsKey('href') && image.containsKey('xlink:href')) {
      throw const FormatException('Ambiguous SVG image');
    }
    final data = RegExp(
      r'^data:image/(?:png|jpeg);base64,([A-Za-z0-9+/=\s]+)$',
    ).firstMatch(image['href'] ?? image['xlink:href'] ?? '');
    if (data == null) {
      throw const FormatException('SVG image must be an embedded PNG or JPEG');
    }
    return LibraryEmbeddedRaster(
      base64.decode(data[1]!.replaceAll(RegExp(r'\s'), '')),
      turns,
    );
  }
}
