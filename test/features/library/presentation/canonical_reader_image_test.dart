import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/canonical_reader_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SVG embedded raster displays with its authored rotation', (tester) async {
    final fixture = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('svg_reader_');
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 40, 80), Paint()..color = Colors.red);
      final picture = recorder.endRecording();
      final image = await picture.toImage(40, 80);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${dir.path}/wrapper.svg');
      await file.writeAsString('<svg width="80" height="40" viewBox="0 0 80 40"><image width="40" height="80" transform="translate(80,0) rotate(90)" href="data:image/png;base64,${base64Encode(bytes!.buffer.asUint8List())}"/></svg>');
      image.dispose(); picture.dispose();
      return file;
    }))!;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CanonicalReaderImage(
      file: fixture, errorBuilder: (_, _, _) => const Text('Image failed'),
    ))));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Image failed'), findsNothing);
    expect(find.byKey(const ValueKey('canonical-local-image')), findsOneWidget);
    expect(tester.widget<RotatedBox>(find.byKey(const ValueKey('canonical-image-orientation'))).quarterTurns, 1);
    final size = tester.getSize(find.byKey(const ValueKey('canonical-image-orientation')));
    expect(size.width / size.height, closeTo(2, .001));
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    for (final degrees in [0, 270]) {
      testWidgets(
        'complete proportionate image at ${size.width}x${size.height}, rotation $degrees',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final fixture = await tester.runAsync(() async {
            final folder = await Directory.systemTemp.createTemp(
              'reader_image_',
            );
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            for (final part in [
              (const Rect.fromLTWH(0, 0, 400, 800), const Color(0xffff0000)),
              (const Rect.fromLTWH(400, 0, 400, 800), const Color(0xff00ff00)),
              (const Rect.fromLTWH(0, 800, 400, 800), const Color(0xff0000ff)),
              (
                const Rect.fromLTWH(400, 800, 400, 800),
                const Color(0xffffff00),
              ),
            ]) {
              canvas.drawRect(part.$1, Paint()..color = part.$2);
            }
            final picture = recorder.endRecording();
            final image = await picture.toImage(800, 1600);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('${folder.path}/asymmetric.png');
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
            picture.dispose();
            return (folder: folder, file: file);
          });
          await tester.pumpWidget(
            const MaterialApp(
              home: SizedBox(key: ValueKey('precache-context')),
            ),
          );
          await tester.runAsync(
            () => precacheImage(
              FileImage(fixture!.file),
              tester.element(find.byKey(const ValueKey('precache-context'))),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: RepaintBoundary(
                      key: const ValueKey('image-boundary'),
                      child: CanonicalReaderImage(
                        file: fixture!.file,
                        rotationDegrees: degrees,
                        errorBuilder: (_, _, _) => const Text('Image failed'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Image failed'), findsNothing);
          final finder = find.byKey(
            const ValueKey('canonical-image-orientation'),
          );
          final rect = tester.getRect(finder);
          expect(rect.width, lessThanOrEqualTo(size.width - 32 + .01));
          expect(rect.height, lessThanOrEqualTo(size.height * .65 + .01));
          expect(rect.left, greaterThanOrEqualTo(16));
          expect(rect.right, lessThanOrEqualTo(size.width - 16 + .01));
          expect(
            rect.width / rect.height,
            closeTo(degrees == 0 ? 0.5 : 2, 0.001),
          );
          expect(tester.widget<RotatedBox>(finder).quarterTurns, degrees ~/ 90);

          // Verify actual rendered orientation with an asymmetric four-color plate.
          final boundaryFinder = find.byKey(const ValueKey('image-boundary'));
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            boundaryFinder,
          );
          final pixels = await tester.runAsync(() async {
            final rendered = await boundary.toImage(pixelRatio: 1);
            final rgba = await rendered.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final width = rendered.width;
            rendered.dispose();
            return (rgba: rgba!, width: width);
          });
          final offset = rect.topLeft - tester.getTopLeft(boundaryFinder);
          List<int> sample(double x, double y) {
            final px = (offset.dx + rect.width * x).floor(),
                py = (offset.dy + rect.height * y).floor();
            final index = (py * pixels!.width + px) * 4;
            return pixels.rgba.buffer.asUint8List(index, 4).toList();
          }

          expect(
            sample(.25, .25),
            degrees == 0 ? [255, 0, 0, 255] : [0, 255, 0, 255],
          );
          expect(
            sample(.75, .25),
            degrees == 0 ? [0, 255, 0, 255] : [255, 255, 0, 255],
          );
          expect(
            sample(.25, .75),
            degrees == 0 ? [0, 0, 255, 255] : [255, 0, 0, 255],
          );
          expect(
            sample(.75, .75),
            degrees == 0 ? [255, 255, 0, 255] : [0, 0, 255, 255],
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() => fixture.folder.delete(recursive: true));
        },
      );
    }
  }
}
