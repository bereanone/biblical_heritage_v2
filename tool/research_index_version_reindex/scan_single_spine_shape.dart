// ignore_for_file: avoid_print
//
// READ-ONLY diagnostic. Does not write to the database or touch any file.
//
// For each already-indexed EPUB `library_items` row (candidates supplied as
// a JSON array of {id, title, relative_path} via SCAN_CANDIDATES_JSON),
// opens the real file under SCAN_ROOT and checks whether
// EpubInternalAnchorSectionSplitter.readTargetsByPath finds 2+ authored
// navigation targets sharing one physical spine file -- the exact shape
// that triggers the internal-anchor splitting fix. Reports which titles
// would actually change output if reindexed, versus those whose stored
// rows already reflect the current parsing logic's own output (an
// ordinary one-file-per-chapter EPUB looks identical before and after).
//
// Usage:
//   SCAN_ROOT=<library root path> SCAN_CANDIDATES_JSON=<path to json> \
//     dart run tool/research_index_version_reindex/scan_single_spine_shape.dart

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:studybible2/features/utilities/data/epub_internal_anchor_section_splitter.dart';

Future<void> main() async {
  final root = Platform.environment['SCAN_ROOT'];
  final candidatesPath = Platform.environment['SCAN_CANDIDATES_JSON'];
  if (root == null || candidatesPath == null) {
    print('SCAN_ROOT and SCAN_CANDIDATES_JSON must be set.');
    exitCode = 1;
    return;
  }

  final candidates =
      (jsonDecode(await File(candidatesPath).readAsString()) as List)
          .cast<Map<String, Object?>>();

  var checked = 0;
  var missingFile = 0;
  var readError = 0;
  var affected = 0;
  final affectedTitles = <Map<String, Object?>>[];

  for (final candidate in candidates) {
    final id = candidate['id'] as String;
    final title = candidate['title'] as String? ?? '';
    final relativePath = candidate['relative_path'] as String? ?? '';
    final file = File(p.join(root, relativePath));
    if (!await file.exists()) {
      missingFile += 1;
      continue;
    }
    checked += 1;
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final targetsByPath = EpubInternalAnchorSectionSplitter.readTargetsByPath(
        archive: archive,
        fallbackTitle: p.basenameWithoutExtension(file.path),
      );
      final maxTargetsInOneFile = targetsByPath.values.isEmpty
          ? 0
          : targetsByPath.values.map((v) => v.length).reduce(
              (a, b) => a > b ? a : b,
            );
      if (maxTargetsInOneFile >= 2) {
        affected += 1;
        affectedTitles.add({
          'id': id,
          'title': title,
          'relative_path': relativePath,
          'max_targets_sharing_one_file': maxTargetsInOneFile,
        });
      }
    } catch (error) {
      readError += 1;
      stderr.writeln('Error reading $relativePath ($title): $error');
    }
  }

  final report = <String, Object?>{
    'total_candidates': candidates.length,
    'checked': checked,
    'missing_file': missingFile,
    'read_error': readError,
    'affected_by_single_spine_shape': affected,
    'affected_titles': affectedTitles,
  };
  print(const JsonEncoder.withIndent('  ').convert(report));
}
