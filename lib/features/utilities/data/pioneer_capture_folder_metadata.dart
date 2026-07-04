import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';

class PioneerCaptureFolderContributorData {
  const PioneerCaptureFolderContributorData({
    required this.name,
    this.fullName,
    this.role = 'author',
    this.sortOrder = 0,
    this.isPrimary = false,
  });

  final String name;
  final String? fullName;
  final String role;
  final int sortOrder;
  final bool isPrimary;

  factory PioneerCaptureFolderContributorData.fromJson(
    Map<String, Object?> json,
  ) {
    return PioneerCaptureFolderContributorData(
      name: json['name']?.toString() ?? '',
      fullName: json['full_name']?.toString(),
      role: json['role']?.toString() ?? 'author',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isPrimary: json['primary'] == true,
    );
  }
}

class PioneerCaptureFolderMetadata {
  const PioneerCaptureFolderMetadata({
    this.title,
    this.abbreviation,
    this.displayAbbreviation,
    this.workId,
    this.sourceType,
    this.sourceSite,
    this.sourceUrl,
    this.coverImagePath,
    this.contributors = const <PioneerCaptureFolderContributorData>[],
  });

  final String? title;
  final String? abbreviation;
  final String? displayAbbreviation;
  final String? workId;
  final String? sourceType;
  final String? sourceSite;
  final String? sourceUrl;
  final String? coverImagePath;
  final List<PioneerCaptureFolderContributorData> contributors;

  bool get hasIdentity => workId?.trim().isNotEmpty == true;

  String? get preferredAbbreviation {
    final display = displayAbbreviation?.trim() ?? '';
    if (display.isNotEmpty) return display;
    final abbreviationValue = abbreviation?.trim() ?? '';
    if (abbreviationValue.isNotEmpty) return abbreviationValue;
    return null;
  }

  String? get primaryContributorName {
    for (final contributor in contributors) {
      if (contributor.isPrimary && contributor.name.trim().isNotEmpty) {
        return contributor.name.trim();
      }
    }
    for (final contributor in contributors) {
      final name = contributor.name.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  static PioneerCaptureFolderMetadata empty() =>
      const PioneerCaptureFolderMetadata();

  factory PioneerCaptureFolderMetadata.fromFolder(
    Directory folder, {
    List<String>? availableFiles,
  }) {
    final metadataFile = File(p.join(folder.path, 'metadata.json'));
    final manifestFile = File(p.join(folder.path, 'manifest.json'));
    final normalizedAvailableFiles =
        availableFiles ??
        folder
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => file.path)
            .toList(growable: false);

    final metadata = metadataFile.existsSync()
        ? PioneerCaptureFolderMetadata.fromFile(
            metadataFile,
            folderPath: folder.path,
            availableFiles: normalizedAvailableFiles,
          )
        : PioneerCaptureFolderMetadata.empty();
    final manifest = manifestFile.existsSync()
        ? PioneerCaptureFolderMetadata.fromManifestFile(
            manifestFile,
            folderPath: folder.path,
            availableFiles: normalizedAvailableFiles,
          )
        : PioneerCaptureFolderMetadata.empty();

    return metadata.mergeWith(manifest);
  }

  factory PioneerCaptureFolderMetadata.fromJsonMap(
    Map<String, Object?> data, {
    required String folderPath,
    List<String>? availableFiles,
  }) {
    final contributorsJson = data['contributors'];
    final contributors = <PioneerCaptureFolderContributorData>[];
    if (contributorsJson is List) {
      for (final item in contributorsJson) {
        if (item is Map<String, Object?>) {
          final contributor = PioneerCaptureFolderContributorData.fromJson(
            item,
          );
          if (contributor.name.trim().isNotEmpty) {
            contributors.add(contributor);
          }
        }
      }
    }

    return PioneerCaptureFolderMetadata(
      title: _normalizedTextValue(data['title']),
      abbreviation: _normalizedTextValue(data['abbreviation']),
      displayAbbreviation: _normalizedTextValue(data['display_abbreviation']),
      workId: _normalizedTextValue(data['work_id']),
      sourceType: _normalizedTextValue(data['source_type']),
      sourceSite: _normalizedTextValue(data['source_site']),
      sourceUrl: _normalizedTextValue(data['source_url']),
      coverImagePath: _metadataCoverImagePath(
        data,
        folderPath: folderPath,
        availableFiles: availableFiles,
      ),
      contributors: List<PioneerCaptureFolderContributorData>.unmodifiable(
        contributors,
      ),
    );
  }

  factory PioneerCaptureFolderMetadata.fromManifestMap(
    Map<String, Object?> data, {
    required String folderPath,
    List<String>? availableFiles,
  }) {
    final contributorsJson = data['contributors'];
    final contributors = <PioneerCaptureFolderContributorData>[];
    if (contributorsJson is List) {
      for (final item in contributorsJson) {
        if (item is Map<String, Object?>) {
          final contributor = PioneerCaptureFolderContributorData.fromJson(
            item,
          );
          if (contributor.name.trim().isNotEmpty) {
            contributors.add(contributor);
          }
        }
      }
    }

    final manifestTitle = _manifestTitleValue(data['title']?.toString());
    return PioneerCaptureFolderMetadata(
      title: manifestTitle,
      abbreviation: _normalizedTextValue(
        data['abbreviation'] ?? data['abbr'] ?? data['work_code'],
      ),
      displayAbbreviation: _normalizedTextValue(
        data['display_abbreviation'] ??
            data['displayAbbreviation'] ??
            data['abbreviation'] ??
            data['abbr'],
      ),
      workId: _normalizedTextValue(
        data['work_id'] ?? data['workId'] ?? data['id'],
      ),
      sourceType: _normalizedTextValue(
        data['source_type'] ?? data['sourceType'],
      ),
      sourceSite: _normalizedTextValue(
        data['source_site'] ?? data['sourceSite'],
      ),
      sourceUrl: _normalizedTextValue(data['source_url'] ?? data['sourceUrl']),
      coverImagePath:
          _metadataCoverImagePath(
            data,
            folderPath: folderPath,
            availableFiles: availableFiles,
          ) ??
          _manifestImageCoverPath(
            data,
            folderPath: folderPath,
            availableFiles: availableFiles,
          ),
      contributors: List<PioneerCaptureFolderContributorData>.unmodifiable(
        contributors,
      ),
    );
  }

  factory PioneerCaptureFolderMetadata.fromJsonString(
    String raw, {
    required String folderPath,
    List<String>? availableFiles,
  }) {
    final decoded = json.decode(raw);
    if (decoded is Map<String, Object?>) {
      return PioneerCaptureFolderMetadata.fromJsonMap(
        decoded,
        folderPath: folderPath,
        availableFiles: availableFiles,
      );
    }
    if (decoded is Map) {
      return PioneerCaptureFolderMetadata.fromJsonMap(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
        folderPath: folderPath,
        availableFiles: availableFiles,
      );
    }
    return PioneerCaptureFolderMetadata.empty();
  }

  factory PioneerCaptureFolderMetadata.fromManifestString(
    String raw, {
    required String folderPath,
    List<String>? availableFiles,
  }) {
    final decoded = json.decode(raw);
    if (decoded is Map<String, Object?>) {
      return PioneerCaptureFolderMetadata.fromManifestMap(
        decoded,
        folderPath: folderPath,
        availableFiles: availableFiles,
      );
    }
    if (decoded is Map) {
      return PioneerCaptureFolderMetadata.fromManifestMap(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
        folderPath: folderPath,
        availableFiles: availableFiles,
      );
    }
    return PioneerCaptureFolderMetadata.empty();
  }

  factory PioneerCaptureFolderMetadata.fromFile(
    File file, {
    required String folderPath,
    List<String>? availableFiles,
  }) {
    if (!file.existsSync()) {
      return PioneerCaptureFolderMetadata.empty();
    }
    try {
      return PioneerCaptureFolderMetadata.fromJsonString(
        file.readAsStringSync(),
        folderPath: folderPath,
        availableFiles: availableFiles,
      );
    } catch (_) {
      return PioneerCaptureFolderMetadata.empty();
    }
  }

  factory PioneerCaptureFolderMetadata.fromManifestFile(
    File file, {
    required String folderPath,
    List<String>? availableFiles,
  }) {
    if (!file.existsSync()) {
      return PioneerCaptureFolderMetadata.empty();
    }
    try {
      return PioneerCaptureFolderMetadata.fromManifestString(
        file.readAsStringSync(),
        folderPath: folderPath,
        availableFiles: availableFiles,
      );
    } catch (_) {
      return PioneerCaptureFolderMetadata.empty();
    }
  }

  PioneerCaptureFolderMetadata mergeWith(
    PioneerCaptureFolderMetadata fallback,
  ) {
    return PioneerCaptureFolderMetadata(
      title: title ?? fallback.title,
      abbreviation: abbreviation ?? fallback.abbreviation,
      displayAbbreviation: displayAbbreviation ?? fallback.displayAbbreviation,
      workId: workId ?? fallback.workId,
      sourceType: sourceType ?? fallback.sourceType,
      sourceSite: sourceSite ?? fallback.sourceSite,
      sourceUrl: sourceUrl ?? fallback.sourceUrl,
      coverImagePath: coverImagePath ?? fallback.coverImagePath,
      contributors: contributors.isNotEmpty
          ? contributors
          : fallback.contributors,
    );
  }
}

bool looksLikeCaptureFolderPlaceholderTitle(
  String value, {
  String? folderCode,
  String? abbreviation,
}) {
  final normalized = value.trim();
  if (normalized.isEmpty) return true;

  final normalizedKey = _stableCaptureFolderCodeKey(normalized);
  final candidateKeys = <String>{
    if (folderCode?.trim().isNotEmpty == true)
      _stableCaptureFolderCodeKey(folderCode!.trim()),
    if (abbreviation?.trim().isNotEmpty == true)
      _stableCaptureFolderCodeKey(abbreviation!.trim()),
  };
  if (candidateKeys.contains(normalizedKey)) return true;

  if (RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(normalized)) {
    return true;
  }

  if (normalized.contains('_')) {
    return true;
  }

  if (RegExp(r'^\w+(?:[-_]\w+)+$', caseSensitive: false).hasMatch(normalized)) {
    return true;
  }

  if (RegExp(
    r'^(chapter|section)\s+\d+\b',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return true;
  }

  return false;
}

String _stableCaptureFolderCodeKey(String value) {
  return value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '');
}

String? _normalizedTextValue(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _manifestTitleValue(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (_looksLikeCaptureSessionTitle(text)) return null;
  return text;
}

String? _metadataCoverImagePath(
  Map<String, Object?> data, {
  required String folderPath,
  List<String>? availableFiles,
}) {
  final raw = data['cover_image'] ?? data['coverImage'] ?? data['cover_path'];
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty || !_isImageFile(value)) return null;

  final candidate = p.isAbsolute(value)
      ? p.normalize(value)
      : p.normalize(p.join(folderPath, value));
  final normalizedCandidate = candidate.replaceAll('\\', '/');
  final files = availableFiles;
  if (files != null) {
    for (final file in files) {
      if (file.replaceAll('\\', '/') == normalizedCandidate) {
        return normalizedCandidate;
      }
    }
    return null;
  }
  return File(candidate).existsSync() ? candidate : null;
}

String? _manifestImageCoverPath(
  Map<String, Object?> data, {
  required String folderPath,
  List<String>? availableFiles,
}) {
  final items = data['items'];
  if (items is! List) return null;

  for (final item in items) {
    if (item is! Map) continue;
    final itemMap = item.map((key, value) => MapEntry(key.toString(), value));
    final type = itemMap['type']?.toString().toLowerCase() ?? '';
    final imagePath =
        itemMap['imagePath']?.toString().trim() ??
        itemMap['image_path']?.toString().trim() ??
        itemMap['path']?.toString().trim() ??
        itemMap['filePath']?.toString().trim() ??
        itemMap['file_name']?.toString().trim() ??
        itemMap['fileName']?.toString().trim() ??
        '';
    if (imagePath.isEmpty) continue;
    if (!_isImageFile(imagePath)) continue;
    if (type.isNotEmpty &&
        !type.contains('image') &&
        !type.contains('cover') &&
        !type.contains('png') &&
        !type.contains('jpeg') &&
        !type.contains('jpg') &&
        !type.contains('webp')) {
      continue;
    }

    final candidate = p.isAbsolute(imagePath)
        ? p.normalize(imagePath)
        : p.normalize(p.join(folderPath, imagePath));
    final normalizedCandidate = candidate.replaceAll('\\', '/');
    final files = availableFiles;
    if (files != null) {
      for (final file in files) {
        if (file.replaceAll('\\', '/') == normalizedCandidate) {
          return normalizedCandidate;
        }
      }
      continue;
    }
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  return null;
}

bool _looksLikeCaptureSessionTitle(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return true;
  if (normalized.contains('_')) return true;
  if (RegExp(r'\b\d{4}-\d{2}-\d{2}\b').hasMatch(normalized)) return true;
  if (RegExp(r'^\w+(?:[-_]\w+)+$', caseSensitive: false).hasMatch(normalized)) {
    return true;
  }
  return false;
}

Future<String?> cachePioneerCaptureCoverPath({
  required String? coverPath,
  required String itemId,
  String? rootPath,
}) async {
  final source = coverPath?.trim() ?? '';
  if (source.isEmpty) return null;
  final sourceFile = File(source);
  if (!await sourceFile.exists()) {
    return null;
  }

  final resolvedRootPath = rootPath?.trim().isNotEmpty == true
      ? rootPath!.trim()
      : await LibraryRootService.instance.accessibleLibraryRootPath();
  if (resolvedRootPath == null || resolvedRootPath.trim().isEmpty) {
    return sourceFile.path;
  }

  final coverRoot = Directory(
    p.join(resolvedRootPath, 'Graphics', 'eLibraryCovers'),
  );
  await coverRoot.create(recursive: true);

  final sourcePath = p.normalize(sourceFile.path);
  final normalizedCoverRoot = p.normalize(coverRoot.path);
  if (sourcePath.startsWith('$normalizedCoverRoot${p.separator}') ||
      sourcePath == normalizedCoverRoot) {
    return sourcePath;
  }

  final extension = p.extension(sourcePath).toLowerCase();
  final targetExtension = switch (extension) {
    '.jpg' => extension,
    '.jpeg' => extension,
    '.png' => extension,
    '.webp' => extension,
    '.gif' => extension,
    '.bmp' => extension,
    _ => '.png',
  };
  final targetPath = p.join(normalizedCoverRoot, '$itemId$targetExtension');
  await sourceFile.copy(targetPath);
  return targetPath;
}

bool _isImageFile(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.webp':
      return true;
    default:
      return false;
  }
}
