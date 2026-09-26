import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'library_embedded_raster.dart';

Future<({ImageProvider provider, int turns})> loadCanonicalReaderImage(
  File file,
) async {
  if (!file.path.toLowerCase().endsWith('.svg')) {
    return (provider: FileImage(file), turns: 0);
  }
  final raster = LibraryEmbeddedRaster.parse(await file.readAsString());
  return (provider: MemoryImage(raster.bytes), turns: raster.quarterTurns);
}

/// Displays the complete illustration within the current reading viewport.
/// Orientation belongs to the imported image, independent of device rotation.
/// RotatedBox also rotates layout constraints, unlike a paint-only transform.
class CanonicalReaderImage extends StatelessWidget {
  const CanonicalReaderImage({
    super.key,
    required this.file,
    required this.errorBuilder,
    this.rotationDegrees = 0,
    this.semanticLabel,
  }) : assert(
         rotationDegrees == 0 ||
             rotationDegrees == 90 ||
             rotationDegrees == 180 ||
             rotationDegrees == 270,
       );

  final File file;
  final int rotationDegrees;
  final String? semanticLabel;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (file.path.toLowerCase().endsWith('.svg')) {
      return FutureBuilder<({ImageProvider provider, int turns})>(
        future: loadCanonicalReaderImage(file),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return errorBuilder(context, snapshot.error!, snapshot.stackTrace);
          }
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final raster = snapshot.data!;
          return _buildImage(
            context,
            raster.provider,
            (rotationDegrees ~/ 90 + raster.turns) % 4,
          );
        },
      );
    }
    return _buildImage(context, FileImage(file), rotationDegrees ~/ 90);
  }

  Widget _buildImage(BuildContext context, ImageProvider provider, int turns) {
    final media = MediaQuery.of(context);
    final usableHeight = math.max(
      1.0,
      media.size.height - media.padding.vertical - media.viewInsets.bottom,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : math.max(1.0, media.size.width - media.padding.horizontal);
        final height = math.min(
          usableHeight * .65,
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : double.infinity,
        );
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: height),
            child: RotatedBox(
              key: const ValueKey('canonical-image-orientation'),
              quarterTurns: turns,
              child: Image(
                image: provider,
                key: const ValueKey('canonical-local-image'),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                semanticLabel: semanticLabel,
                errorBuilder: errorBuilder,
              ),
            ),
          ),
        );
      },
    );
  }
}
