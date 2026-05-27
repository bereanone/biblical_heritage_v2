import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/bootstrap/library_root_service.dart';

class TagPresentationMediaPathResolver {
  TagPresentationMediaPathResolver._();

  static const List<String> _knownMediaDirectories = <String>[
    'Media/tag_content',
    'Media',
    'Images',
    'Graphics',
  ];

  static Future<List<String>> collectRootCandidates({
    String? preferredRootPath,
  }) async {
    final roots = <String>[];

    void addRoot(String? rootPath) {
      final normalized = rootPath?.trim() ?? '';
      if (normalized.isEmpty) return;
      final resolved = p.normalize(normalized);
      if (roots.contains(resolved)) return;
      if (Directory(resolved).existsSync()) {
        roots.add(resolved);
      }
    }

    addRoot(preferredRootPath);

    final selection = await LibraryRootService.instance.loadSelection();
    addRoot(selection.path);
    addRoot(await LibraryRootService.instance.accessibleLibraryRootPath());
    addRoot(await LibraryRootService.instance.libraryRootPath());

    final documentsDir = await getApplicationDocumentsDirectory();
    addRoot(p.join(documentsDir.path, 'BiblicalHeritage', 'v2'));

    final supportDir = await getApplicationSupportDirectory();
    addRoot(p.join(supportDir.path, 'BiblicalHeritage', 'v2'));
    addRoot(p.join(supportDir.path, 'studybible_media'));

    return List<String>.unmodifiable(roots);
  }

  static String? resolveStoredMediaPath(
    String? storedPath,
    Iterable<String> rootCandidates,
  ) {
    final candidate = storedPath?.trim() ?? '';
    if (candidate.isEmpty) return null;

    if (p.isAbsolute(candidate) && File(candidate).existsSync()) {
      return candidate;
    }

    final normalized = p.normalize(candidate);
    final fallbacks = <String>[
      normalized,
      if (p.basename(normalized) != normalized) p.basename(normalized),
    ];

    final normalizedRoots = <String>{};
    for (final root in rootCandidates) {
      final normalizedRoot = root.trim();
      if (normalizedRoot.isEmpty) continue;
      final resolvedRoot = p.normalize(normalizedRoot);
      if (!normalizedRoots.add(resolvedRoot)) continue;

      for (final relative in fallbacks) {
        final direct = p.join(resolvedRoot, relative);
        if (File(direct).existsSync()) return direct;

        final baseName = p.basename(relative);
        for (final mediaDirectory in _knownMediaDirectories) {
          final nested = p.join(resolvedRoot, mediaDirectory, baseName);
          if (File(nested).existsSync()) return nested;
        }
      }
    }

    return null;
  }
}
