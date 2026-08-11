import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/bootstrap/library_root_service.dart';

/// Extracts a Pioneer Library EPUB collection ZIP (the same package format
/// distributed to collaborators) into a working folder so it can be scanned
/// and imported the same way as a manually-extracted folder. Picking a
/// single ZIP file is a much simpler, more familiar Android/iOS interaction
/// than navigating the system folder-tree picker.
class PioneerZipExtractService {
  PioneerZipExtractService._();

  static final PioneerZipExtractService instance = PioneerZipExtractService._();

  static const String workingFolderName = 'pioneer_zip_import';

  Future<String> extractToWorkingFolder(String zipPath) async {
    final sourceFile = File(zipPath.trim());
    if (!await sourceFile.exists()) {
      throw const FormatException('The selected ZIP file no longer exists.');
    }
    final bytes = await sourceFile.readAsBytes();
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const FormatException(
        'The selected file is not a valid ZIP archive.',
      );
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (error) {
      throw FormatException(
        'The selected file is not a valid ZIP archive: $error',
      );
    }

    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    final supportDir = rootPath == null || rootPath.isEmpty
        ? await getApplicationSupportDirectory()
        : Directory(p.join(rootPath, 'Temporary'));
    final destinationDir = Directory(
      p.join(supportDir.path, workingFolderName),
    );
    if (await destinationDir.exists()) {
      await destinationDir.delete(recursive: true);
    }
    await destinationDir.create(recursive: true);

    for (final entry in archive) {
      if (!entry.isFile) continue;
      final relativePath = entry.name.replaceAll('\\', '/').trim();
      if (relativePath.isEmpty || relativePath.startsWith('__MACOSX/')) {
        continue;
      }
      final outputPath = p.normalize(p.join(destinationDir.path, relativePath));
      if (!p.isWithin(destinationDir.path, outputPath)) {
        throw const FormatException(
          'The selected ZIP archive contains an unsafe file path.',
        );
      }
      final outFile = File(outputPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(entry.content as List<int>, flush: true);
    }
    return destinationDir.path;
  }
}
