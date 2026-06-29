import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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
}

String? _normalizedTextValue(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
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
