import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_embedded_raster.dart';

void main() {
  const fixture =
      '<svg width="20" height="10" viewBox="0 0 20 10"><image width="10" height="20" transform="translate(20,0) rotate(90)" href="data:image/png;base64,AQID"/></svg>';
  test('preserves embedded bytes and clockwise rotation', () {
    final raster = LibraryEmbeddedRaster.parse(fixture);
    expect(raster.bytes, [1, 2, 3]);
    expect(raster.quarterTurns, 1);
    expect(
      LibraryEmbeddedRaster.parse(
        fixture.replaceFirst(
          'translate(20,0) rotate(90)',
          'translate(0,10) rotate(270)',
        ),
      ).quarterTurns,
      3,
    );
  });
  test('rejects unsupported SVG rather than losing visible content', () {
    for (final bad in [
      fixture.replaceFirst('</svg>', '<text>Caption</text></svg>'),
      fixture.replaceFirst('<image', '<image opacity="0.5"'),
      fixture.replaceFirst(
        'data:image/png;base64,AQID',
        'https://example.com/image.png',
      ),
      fixture.replaceFirst('translate(20,0)', 'translate(19,0)'),
      fixture.replaceFirst('0 0 20 10', '0 0 10 20'),
    ]) {
      expect(() => LibraryEmbeddedRaster.parse(bad), throwsFormatException);
    }
  });
}
