// ignore_for_file: avoid_print
//
// Re-derives `is_front_matter` / `is_body_start` on `library_navigation_items`
// for every EPUB-backed library item, using the *current* EPUB file content
// (paragraph text, evaluated with the same `libraryIsMeaningfulReadingSection`
// heuristic the app already uses) instead of trusting the possibly-stale
// snapshot recorded at import time.
//
// Classification runs over the EPUB's actual spine order (its OPF manifest),
// not the nav tree's depth/sort_order — many books split a "Section" header
// into its own near-empty divider page with the real chapters nested under
// it at a deeper level, so a scheme that only looked at top-level nav rows
// (or trusted their own paragraph text) would misjudge those chapters too.
// Every nav row referencing a given spine file — at any depth, any
// content_kind — gets that file's classification.
//
// See FRONT_MATTER_TOC_AUDIT_2026-08-25.md for the full background.
//
// Usage:
//   dart run tool/front_matter_repair/run_front_matter_repair.dart \
//     <eLibrary.db path> <primary library root> <fallback library root> \
//     [--apply] [--report <output.json>] [--only <library_item_id>]
//
// Without --apply this is a dry run: it prints/writes the report but makes
// no database changes.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/features/library/data/library_section_heuristics.dart';

import 'epub_paragraph_extractor.dart';

Future<void> main(List<String> arguments) async {
  final positional = <String>[];
  var apply = false;
  String? reportPath;
  String? onlyItemId;
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--apply') {
      apply = true;
    } else if (arg == '--report') {
      reportPath = arguments[++i];
    } else if (arg == '--only') {
      onlyItemId = arguments[++i];
    } else {
      positional.add(arg);
    }
  }

  if (positional.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/front_matter_repair/run_front_matter_repair.dart '
      '<eLibrary.db> <primary root> <fallback root> [--apply] '
      '[--report <output.json>] [--only <library_item_id>]',
    );
    exitCode = 64;
    return;
  }

  final dbPath = positional[0];
  final primaryRoot = positional[1];
  final fallbackRoot = positional[2];

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(dbPath);

  final itemRows = await db.rawQuery('''
    select li.id, li.title, li.relative_path, li.file_format
    from library_items li
    where li.deleted_at is null
      and lower(coalesce(li.file_format, '')) = 'epub'
      and li.id in (select distinct library_item_id from library_navigation_items)
    order by li.title
  ''');

  final results = <Map<String, Object?>>[];
  var itemsChanged = 0;
  var rowsChanged = 0;
  var itemsNoFile = 0;
  var itemsNoNavRows = 0;
  var itemsAlreadyCorrect = 0;
  var itemsNoSpine = 0;
  var itemsNoRealContent = 0;

  for (final item in itemRows) {
    final itemId = item['id']!.toString();
    if (onlyItemId != null && itemId != onlyItemId) continue;
    final title = item['title']?.toString() ?? '';
    final relativePath = item['relative_path']?.toString().trim() ?? '';

    // All nav rows at every depth — front-matter classification must reach
    // nested chapters, not just the top-level "toc" entries.
    final navRows = await db.query(
      'library_navigation_items',
      where: 'library_item_id = ?',
      whereArgs: [itemId],
      orderBy: 'sort_order',
    );
    if (navRows.isEmpty) {
      itemsNoNavRows += 1;
      continue;
    }

    final filePath = _resolveExisting(
      relativePath: relativePath,
      primaryRoot: primaryRoot,
      fallbackRoot: fallbackRoot,
    );
    if (filePath == null) {
      itemsNoFile += 1;
      results.add({
        'item_id': itemId,
        'title': title,
        'status': 'skipped_no_file',
        'relative_path': relativePath,
      });
      continue;
    }

    final List<String> spineHrefs;
    final Map<String, List<String>> paragraphsByHref;
    try {
      final bytes = File(filePath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      spineHrefs = _readSpineOrder(archive);
      paragraphsByHref = _extractParagraphsByHref(archive);
    } catch (error) {
      results.add({
        'item_id': itemId,
        'title': title,
        'status': 'skipped_parse_error',
        'error': error.toString(),
      });
      continue;
    }
    if (spineHrefs.isEmpty) {
      itemsNoSpine += 1;
      results.add({
        'item_id': itemId,
        'title': title,
        'status': 'skipped_no_spine',
      });
      continue;
    }

    // A representative label for each spine href, for the front-matter
    // label check — any nav row referencing that href with a front-matter
    // label (e.g. "Preface") is enough to disqualify the whole file, even
    // if a different row referencing the same file has a plainer label.
    final labelsByHref = <String, List<String>>{};
    for (final row in navRows) {
      final href = _normalizeHrefKey(_cleanHref(row['href']?.toString() ?? ''));
      if (href.isEmpty) continue;
      (labelsByHref[href] ??= <String>[]).add(row['label']?.toString() ?? '');
    }

    int? firstMeaningfulSpineIndex;
    int? firstNonFrontMatterLabelSpineIndex;
    final spineInfo = <Map<String, Object?>>[];
    for (var i = 0; i < spineHrefs.length; i++) {
      final href = spineHrefs[i];
      final labels = labelsByHref[href] ?? const <String>[];
      final looksLikeFrontMatterByLabel =
          labels.any(libraryIsFrontMatterOpeningLabel) ||
          libraryIsFrontMatterOpeningLabel(p.basenameWithoutExtension(href));
      if (!looksLikeFrontMatterByLabel) {
        firstNonFrontMatterLabelSpineIndex ??= i;
      }
      final paragraphs = paragraphsByHref[href] ?? const <String>[];
      // A page can be full of real, substantial prose and still not be a
      // chapter — "Information about this Book" is the clearest case: it
      // easily clears the paragraph-length bar but must never be treated as
      // the book's first chapter. The label gate above (mirroring
      // `_firstRealContentNavigationHref` in library_book_reader_screen.dart)
      // rules those out before paragraph length is even considered.
      final isMeaningful =
          !looksLikeFrontMatterByLabel &&
          libraryIsMeaningfulReadingSection(
            title: labels.isEmpty ? '' : labels.first,
            href: href,
            paragraphs: paragraphs,
            bookTitle: title,
          );
      if (firstMeaningfulSpineIndex == null && isMeaningful) {
        firstMeaningfulSpineIndex = i;
      }
      spineInfo.add({
        'href': href,
        'paragraph_count': paragraphs.length,
        'is_meaningful': isMeaningful,
      });
    }
    // If nothing passed the full "meaningful" bar (e.g. every chapter's
    // paragraph extraction came back thin), prefer the first spine file that
    // at least isn't itself front-matter-labeled over blindly picking index
    // 0 — index 0 is very often the cover or About page.
    if (firstMeaningfulSpineIndex == null &&
        firstNonFrontMatterLabelSpineIndex == null) {
      // Nothing in the whole book — not even a plausibly-titled fallback —
      // looks like real content. A handful of pamphlets' EPUBs genuinely
      // contain nothing but cover/titlepage/toc/about (no chapter file was
      // ever included). Guessing here would only make things worse than
      // whatever's already recorded, so leave this one for manual review
      // instead of writing a confident-looking wrong answer.
      itemsNoRealContent += 1;
      results.add({
        'item_id': itemId,
        'title': title,
        'status': 'skipped_no_real_content_found',
        'spine_length': spineHrefs.length,
      });
      continue;
    }
    firstMeaningfulSpineIndex ??= firstNonFrontMatterLabelSpineIndex!;
    final firstMeaningfulHref = spineHrefs[firstMeaningfulSpineIndex];

    // Only the earliest nav row (by sort_order) referencing the first
    // meaningful href becomes the body-start marker — matches the original
    // importer's one-row-per-book convention.
    String? bodyStartNavId;

    final changes = <Map<String, Object?>>[];
    for (final row in navRows) {
      final href = _normalizeHrefKey(_cleanHref(row['href']?.toString() ?? ''));
      final spineIndex = spineHrefs.indexOf(href);
      // A row whose href isn't in the spine at all (shouldn't normally
      // happen) is left exactly as it already is — never guessed at.
      if (spineIndex < 0) continue;

      final correctFrontMatter = spineIndex < firstMeaningfulSpineIndex ? 1 : 0;
      final isBodyStartCandidate = href == firstMeaningfulHref;
      var correctBodyStart = 0;
      if (isBodyStartCandidate) {
        bodyStartNavId ??= row['id']!.toString();
        correctBodyStart = row['id'] == bodyStartNavId ? 1 : 0;
      }

      final currentFrontMatter = (row['is_front_matter'] as num?)?.toInt() ?? 0;
      final currentBodyStart = (row['is_body_start'] as num?)?.toInt() ?? 0;
      if (correctFrontMatter != currentFrontMatter ||
          correctBodyStart != currentBodyStart) {
        changes.add({
          'nav_id': row['id'],
          'label': row['label'],
          'href': row['href'],
          'depth': row['depth'],
          'from_front_matter': currentFrontMatter,
          'to_front_matter': correctFrontMatter,
          'from_body_start': currentBodyStart,
          'to_body_start': correctBodyStart,
        });
        if (apply) {
          await db.update(
            'library_navigation_items',
            {
              'is_front_matter': correctFrontMatter,
              'is_body_start': correctBodyStart,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    }

    if (changes.isEmpty) {
      itemsAlreadyCorrect += 1;
    } else {
      itemsChanged += 1;
      rowsChanged += changes.length;
    }

    results.add({
      'item_id': itemId,
      'title': title,
      'status': changes.isEmpty ? 'already_correct' : 'corrected',
      'first_meaningful_spine_index': firstMeaningfulSpineIndex,
      'first_meaningful_href': firstMeaningfulHref,
      'spine_length': spineHrefs.length,
      'nav_row_count': navRows.length,
      'changed_row_count': changes.length,
      'changes': changes,
    });
  }

  final summary = <String, Object?>{
    'mode': apply ? 'applied' : 'dry_run',
    'items_scanned': itemRows.length,
    'items_changed': itemsChanged,
    'rows_changed': rowsChanged,
    'items_already_correct': itemsAlreadyCorrect,
    'items_skipped_no_file': itemsNoFile,
    'items_skipped_no_nav_rows': itemsNoNavRows,
    'items_skipped_no_spine': itemsNoSpine,
    'items_skipped_no_real_content': itemsNoRealContent,
    'items': results,
  };

  final encoded = const JsonEncoder.withIndent('  ').convert(summary);
  if (reportPath != null) {
    await File(reportPath).writeAsString(encoded);
    stdout.writeln('Report written to $reportPath');
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'mode': summary['mode'],
      'items_scanned': summary['items_scanned'],
      'items_changed': summary['items_changed'],
      'rows_changed': summary['rows_changed'],
      'items_already_correct': summary['items_already_correct'],
      'items_skipped_no_file': summary['items_skipped_no_file'],
      'items_skipped_no_nav_rows': summary['items_skipped_no_nav_rows'],
      'items_skipped_no_spine': summary['items_skipped_no_spine'],
      'items_skipped_no_real_content': summary['items_skipped_no_real_content'],
    }),
  );

  await db.close();
}

String? _resolveExisting({
  required String relativePath,
  required String primaryRoot,
  required String fallbackRoot,
}) {
  if (relativePath.isEmpty) return null;
  final primary = p.join(primaryRoot, relativePath);
  if (File(primary).existsSync()) return primary;
  if (p.normalize(fallbackRoot) != p.normalize(primaryRoot)) {
    final fallback = p.join(fallbackRoot, relativePath);
    if (File(fallback).existsSync()) return fallback;
  }
  return null;
}

final RegExp _manifestItemPattern = RegExp(
  r'<item\b[^>]*\bid="([^"]+)"[^>]*\bhref="([^"]+)"[^>]*/?>',
  caseSensitive: false,
);
final RegExp _manifestItemPatternReversed = RegExp(
  r'<item\b[^>]*\bhref="([^"]+)"[^>]*\bid="([^"]+)"[^>]*/?>',
  caseSensitive: false,
);
final RegExp _spinePattern = RegExp(
  r'<spine\b[^>]*>(.*?)</spine>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _itemrefPattern = RegExp(
  r'<itemref\b[^>]*\bidref="([^"]+)"',
  caseSensitive: false,
);

/// Reads the EPUB's actual reading order from its OPF manifest + spine,
/// returning normalized hrefs in spine order. This is the authoritative
/// document order — more reliable than trusting `library_navigation_items`
/// sort values, which can legitimately interleave a file's own internal
/// sub-headings out of true inter-file order.
List<String> _readSpineOrder(Archive archive) {
  ArchiveFile? opfFile;
  for (final entry in archive) {
    if (entry.isFile && entry.name.toLowerCase().endsWith('.opf')) {
      opfFile = entry;
      break;
    }
  }
  if (opfFile == null) return const [];
  final opfDir = p.dirname(opfFile.name);
  final raw = utf8.decode(opfFile.content as List<int>, allowMalformed: true);

  final idToHref = <String, String>{};
  for (final match in _manifestItemPattern.allMatches(raw)) {
    idToHref[match.group(1)!] = match.group(2)!;
  }
  for (final match in _manifestItemPatternReversed.allMatches(raw)) {
    idToHref.putIfAbsent(match.group(2)!, () => match.group(1)!);
  }

  final spineMatch = _spinePattern.firstMatch(raw);
  if (spineMatch == null) return const [];
  final spineBody = spineMatch.group(1)!;

  final hrefs = <String>[];
  for (final match in _itemrefPattern.allMatches(spineBody)) {
    final idref = match.group(1)!;
    final href = idToHref[idref];
    if (href == null) continue;
    final lower = href.toLowerCase();
    if (!lower.endsWith('.xhtml') && !lower.endsWith('.html')) continue;
    final resolved = opfDir.isEmpty || opfDir == '.'
        ? href
        : p.join(opfDir, href);
    hrefs.add(_normalizeHrefKey(resolved));
  }
  return hrefs;
}

Map<String, List<String>> _extractParagraphsByHref(Archive archive) {
  final result = <String, List<String>>{};
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = p.normalize(entry.name);
    final lower = name.toLowerCase();
    if (!lower.endsWith('.xhtml') && !lower.endsWith('.html')) continue;
    final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
    result[_normalizeHrefKey(name)] = extractParagraphsFromXhtml(raw);
  }
  return result;
}

String _normalizeHrefKey(String href) {
  return p.normalize(href).toLowerCase();
}

String _cleanHref(String href) {
  return href.split('#').first.split('?').first.trim();
}
