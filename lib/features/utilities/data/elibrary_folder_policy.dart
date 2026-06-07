import 'dart:io';

import 'package:path/path.dart' as p;

class ELibraryManagedFolderDefinition {
  const ELibraryManagedFolderDefinition({
    required this.collectionName,
    required this.relativeFolder,
    required this.folderType,
  });

  final String collectionName;
  final String relativeFolder;
  final String folderType;
}

class ELibraryFolderPolicy {
  ELibraryFolderPolicy._();

  static const managedEgwFolderDefinitions = <ELibraryManagedFolderDefinition>[
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Commentaries',
      relativeFolder: 'ePubs/EGW/EGW_Commentaries',
      folderType: 'commentary',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Commentaries',
      relativeFolder: 'PDFs/EGW/EGW_Commentaries',
      folderType: 'commentary',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Books',
      relativeFolder: 'ePubs/EGW/EGW_Books',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Books',
      relativeFolder: 'PDFs/EGW/EGW_Books',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Devotionals',
      relativeFolder: 'ePubs/EGW/EGW_Devotionals',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Devotionals',
      relativeFolder: 'PDFs/EGW/EGW_Devotionals',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Misc Collections',
      relativeFolder: 'ePubs/EGW/EGW_Misc_Collections',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Misc Collections',
      relativeFolder: 'PDFs/EGW/EGW_Misc_Collections',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Pamphlets',
      relativeFolder: 'ePubs/EGW/EGW_Pamphlets',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Pamphlets',
      relativeFolder: 'PDFs/EGW/EGW_Pamphlets',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Periodicals',
      relativeFolder: 'ePubs/EGW/EGW_Periodicals',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Periodicals',
      relativeFolder: 'PDFs/EGW/EGW_Periodicals',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Manuscript Releases',
      relativeFolder: 'ePubs/EGW/EGW_Manuscript_Releases',
      folderType: 'research',
    ),
    ELibraryManagedFolderDefinition(
      collectionName: 'EGW Manuscript Releases',
      relativeFolder: 'PDFs/EGW/EGW_Manuscript_Releases',
      folderType: 'research',
    ),
  ];

  static const legacyManagedEgwFolderDefinitions =
      <ELibraryManagedFolderDefinition>[
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Commentaries',
          relativeFolder: 'ePubs/Commentaries/EGW_Commentaries',
          folderType: 'commentary',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Commentaries',
          relativeFolder: 'PDFs/Commentaries/EGW_Commentaries',
          folderType: 'commentary',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Books',
          relativeFolder: 'ePubs/Research/EGW_Books',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Books',
          relativeFolder: 'PDFs/Research/EGW_Books',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Devotionals',
          relativeFolder: 'ePubs/Research/EGW_Devotionals',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Devotionals',
          relativeFolder: 'PDFs/Research/EGW_Devotionals',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Misc Collections',
          relativeFolder: 'ePubs/Research/EGW_Misc_Collections',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Misc Collections',
          relativeFolder: 'PDFs/Research/EGW_Misc_Collections',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Pamphlets',
          relativeFolder: 'ePubs/Research/EGW_Pamphlets',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Pamphlets',
          relativeFolder: 'PDFs/Research/EGW_Pamphlets',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Periodicals',
          relativeFolder: 'ePubs/Research/EGW_Periodicals',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Periodicals',
          relativeFolder: 'PDFs/Research/EGW_Periodicals',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Manuscript Releases',
          relativeFolder: 'ePubs/Research/EGW_Manuscript_Releases',
          folderType: 'research',
        ),
        ELibraryManagedFolderDefinition(
          collectionName: 'EGW Manuscript Releases',
          relativeFolder: 'PDFs/Research/EGW_Manuscript_Releases',
          folderType: 'research',
        ),
      ];

  static Iterable<ELibraryManagedFolderDefinition>
  get allManagedEgwFolderDefinitions sync* {
    yield* managedEgwFolderDefinitions;
    yield* legacyManagedEgwFolderDefinitions;
  }

  static const quarantineFolderSegment = '_quarantine_duplicates';

  static bool isManagedEgwFolderPath(String path) {
    final normalized = p.normalize(path).toLowerCase();
    final pathSegments = p.split(normalized);
    for (final folder in allManagedEgwFolderDefinitions) {
      final folderSegments = p.split(p.normalize(folder.relativeFolder).toLowerCase());
      if (_containsPathSegments(pathSegments, folderSegments)) {
        return true;
      }
    }
    return false;
  }

  static bool isQuarantinePath(String path) {
    final normalized = p.normalize(path).toLowerCase();
    final segments = p.split(normalized);
    return segments.any(
      (segment) => segment.trim().toLowerCase() == quarantineFolderSegment,
    );
  }

  static bool shouldSkipUserImportPath(String path) {
    return isManagedEgwFolderPath(path) || isQuarantinePath(path);
  }

  static String quarantineRoot(String rootPath) {
    return p.join(
      p.normalize(rootPath.trim()),
      'LegacyBackup',
      '_Quarantine_Duplicates',
    );
  }

  static String quarantinePathFor(
    String rootPath,
    String sourcePath, {
    String? suffix,
  }) {
    final quarantineRootDir = Directory(quarantineRoot(rootPath));
    final relative = p.relative(
      p.normalize(sourcePath.trim()),
      from: p.normalize(rootPath.trim()),
    );
    final safeRelative = relative.replaceAll('..', '_');
    final fileName = p.basename(safeRelative);
    final base = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    final tail = suffix == null || suffix.trim().isEmpty
        ? ''
        : '_${suffix.trim()}';
    return p.join(
      quarantineRootDir.path,
      p.dirname(safeRelative),
      '$base$tail$extension',
    );
  }

  static String normalizedEditionStem(String fileName) {
    final stem = p.basenameWithoutExtension(fileName).trim().toLowerCase();
    return stem.replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _containsPathSegments(
    List<String> pathSegments,
    List<String> targetSegments,
  ) {
    if (targetSegments.isEmpty || pathSegments.length < targetSegments.length) {
      return false;
    }

    for (
      var start = 0;
      start <= pathSegments.length - targetSegments.length;
      start++
    ) {
      var matched = true;
      for (var index = 0; index < targetSegments.length; index++) {
        if (pathSegments[start + index].trim().toLowerCase() !=
            targetSegments[index].trim().toLowerCase()) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }

  static String editionKeyForFileName(String fileName) {
    var stem = p.basenameWithoutExtension(fileName).trim().toLowerCase();
    stem = stem.replaceAll(RegExp(r'__legacy.*$'), '');
    stem = stem.replaceAll(RegExp(r'__conflict.*$'), '');
    stem = stem.replaceAll(RegExp(r'_\d+$'), '');
    stem = stem.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
    stem = stem.replaceAll(RegExp(r'\s+'), '');
    if (stem.contains('_')) {
      stem = stem.substring(stem.lastIndexOf('_') + 1);
    }
    return stem.replaceAll(RegExp(r'[^a-z0-9]+'), '').toUpperCase();
  }

  static String detectedAbbreviation(String fileName) {
    final stem = p.basenameWithoutExtension(fileName).trim();
    if (stem.isEmpty) return '';
    final parts = stem.split('_');
    final candidate = parts.isNotEmpty ? parts.last : stem;
    return candidate.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '').toUpperCase();
  }
}
