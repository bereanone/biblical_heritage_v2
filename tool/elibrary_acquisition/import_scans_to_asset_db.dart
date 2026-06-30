// Build-time tool — imports HTML capture folders from assets/scans into
// assets/databases/eLibrary.db.
//
// Run from the repo root:
//   dart run tool/elibrary_acquisition/import_scans_to_asset_db.dart \
//     --source assets/scans \
//     --db assets/databases/eLibrary.db \
//     --overwrite \
//     --report test/download_reports/scans_import_report.json
//
// This tool is dev/build-time only. The runtime app must not scan
// assets/scans directly (macOS sandbox blocks it).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/features/utilities/data/pioneer_capture_folder_metadata.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> rawArgs) async {
  final args = _parseArgs(rawArgs);
  final sourcePath = args['source'] as String;
  final dbPath = args['db'] as String;
  final overwrite = args['overwrite'] as bool;
  final reportPath = args['report'] as String?;

  print('=== import_scans_to_asset_db ===');
  print('  source   : $sourcePath');
  print('  db       : $dbPath');
  print('  overwrite: $overwrite');
  if (reportPath != null) print('  report   : $reportPath');
  print('');

  // ── Task 1: Backup ────────────────────────────────────────────────────────
  String? backupPath;
  if (overwrite) {
    backupPath = await _backupDb(dbPath);
    if (backupPath == null) {
      exitCode = 1;
      return;
    }
  }

  // ── Task 4: Filesystem scan ───────────────────────────────────────────────
  final captures = await _scanCaptureFolders(Directory(sourcePath));
  if (captures.isEmpty) {
    print('\n[scanner] Nothing to import.');
    exitCode = 1;
    return;
  }

  // ── DB open ───────────────────────────────────────────────────────────────
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbFile = File(dbPath);
  if (!dbFile.existsSync()) {
    print('[db] DB not found at $dbPath');
    print('[db] Run the app once to seed assets/databases/eLibrary.db');
    exitCode = 1;
    return;
  }

  final db = await databaseFactory.openDatabase(p.absolute(dbPath));

  // ── Per-capture import ────────────────────────────────────────────────────
  final allResults = <_ImportResult>[];
  try {
    for (final capture in captures) {
      print('\n[import] Processing ${capture.folderName} ...');
      final result = await _importCapture(
        db: db,
        capture: capture,
        overwrite: overwrite,
      );
      allResults.add(result);
      _printResult(result);
    }
  } finally {
    await db.close();
  }

  // ── Task 8: Summary ───────────────────────────────────────────────────────
  print('\n=== Summary ===');
  for (final r in allResults) {
    print('  ${r.folderName}');
    print('    Title            : ${r.title}');
    print('    Author           : ${r.author}');
    print('    Text blocks      : ${r.textBlocksInserted}');
    print('    Nav items        : ${r.navItemsInserted}');
    print('    Refs             : ${r.refsInserted}');
    print('    Duplicate refs   : ${r.duplicateRefs}');
    if (backupPath != null) {
      print('    Backup           : $backupPath');
    }
    if (r.warnings.isNotEmpty) {
      print('    Warnings         : ${r.warnings.join('; ')}');
    }
  }
  print('\nImport complete.');

  // ── Report ────────────────────────────────────────────────────────────────
  if (reportPath != null) {
    await _writeReport(reportPath, allResults);
    print('\nReport written to $reportPath');
  }

  // ── Integrity check ───────────────────────────────────────────────────────
  final checkDb = await databaseFactory.openDatabase(
    p.absolute(dbPath),
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    final integrity = await checkDb.rawQuery('PRAGMA integrity_check');
    final ok = integrity.firstOrNull?['integrity_check']?.toString() ?? '?';
    print('\n[db] integrity_check = $ok');
  } finally {
    await checkDb.close();
  }
}

// ---------------------------------------------------------------------------
// Task 1 — DB backup
// ---------------------------------------------------------------------------

Future<String?> _backupDb(String dbPath) async {
  final src = File(dbPath);
  if (!src.existsSync()) {
    print('[backup] DB not found, skipping backup.');
    return dbPath;
  }
  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );
  final bakPath = '$dbPath.before-scans-import-$timestamp.bak';
  try {
    await src.copy(bakPath);
    final size = await File(bakPath).length();
    print('[backup] Backed up to $bakPath (${(size / 1024).round()}KB)');
    return bakPath;
  } catch (e) {
    print('[backup] FAILED: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Filesystem scanner
// ---------------------------------------------------------------------------

class _CaptureFolder {
  const _CaptureFolder({
    required this.folderName,
    required this.folderPath,
    required this.captureHtmlPath,
    required this.coverImagePath,
    required this.metadata,
  });

  final String folderName;
  final String folderPath;
  final String captureHtmlPath;
  final String? coverImagePath;
  final PioneerCaptureFolderMetadata metadata;
}

Future<List<_CaptureFolder>> _scanCaptureFolders(Directory sourceDir) async {
  print('[scanner] Scanning ${sourceDir.path} ...');

  if (!sourceDir.existsSync()) {
    print('[scanner] Source directory not found: ${sourceDir.path}');
    return const [];
  }

  final subdirs =
      sourceDir.listSync(followLinks: false).whereType<Directory>().toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

  final found = <_CaptureFolder>[];
  for (final dir in subdirs) {
    final folderName = p.basename(dir.path);
    final captureHtml = File(p.join(dir.path, 'capture.html'));
    if (!captureHtml.existsSync()) {
      print('  [skip] $folderName/ — no capture.html');
      continue;
    }

    final metadata = PioneerCaptureFolderMetadata.fromFile(
      File(p.join(dir.path, 'metadata.json')),
      folderPath: dir.path,
    );

    // Cover: metadata cover_image, root cover/thumbnail, then first image.
    final coverPath = _findCoverImage(dir, folderName, metadata: metadata);

    final sizeKb = (captureHtml.lengthSync() / 1024).round();
    print(
      '  [✓] $folderName/capture.html '
      '(${sizeKb}KB'
      '${coverPath != null ? ", cover: ${p.basename(coverPath)}" : ""})',
    );

    found.add(
      _CaptureFolder(
        folderName: folderName,
        folderPath: dir.path,
        captureHtmlPath: captureHtml.path,
        coverImagePath: coverPath,
        metadata: metadata,
      ),
    );
  }
  print('[scanner] ${found.length} capture folder(s) ready.');
  return found;
}

String? _findCoverImage(
  Directory dir,
  String folderName, {
  required PioneerCaptureFolderMetadata metadata,
}) {
  final metadataCover = metadata.coverImagePath;
  if (metadataCover != null) return metadataCover;

  for (final name in const <String>[
    'cover.png',
    'cover.jpg',
    'cover.jpeg',
    'cover.webp',
    'thumbnail.png',
    'thumbnail.jpg',
    'thumbnail.jpeg',
    'thumbnail.webp',
  ]) {
    final file = File(p.join(dir.path, name));
    if (file.existsSync()) return file.path;
  }

  final imageFiles =
      dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => _isSupportedImage(file.path))
          .toList()
        ..sort((a, b) {
          final leftName = p.basename(a.path).toLowerCase();
          final rightName = p.basename(b.path).toLowerCase();
          final leftFolderNamed = leftName == '${folderName.toLowerCase()}.png';
          final rightFolderNamed =
              rightName == '${folderName.toLowerCase()}.png';
          if (leftFolderNamed && !rightFolderNamed) return -1;
          if (rightFolderNamed && !leftFolderNamed) return 1;
          return a.path.compareTo(b.path);
        });
  return imageFiles.isEmpty ? null : imageFiles.first.path;
}

bool _isSupportedImage(String path) {
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

// ---------------------------------------------------------------------------
// Task 2 — HTML parsing
// ---------------------------------------------------------------------------

class _CaptureParagraph {
  const _CaptureParagraph({required this.ref, required this.text});

  final String ref;
  final String text;

  int get pageNumber {
    final match = RegExp(r'\s+(\d+)\.\d+$').firstMatch(ref);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  int get paragraphOnPage {
    final match = RegExp(r'\.(\d+)$').firstMatch(ref);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}

class _CaptureSection {
  const _CaptureSection({
    required this.title,
    required this.href,
    required this.spineIndex,
    required this.paragraphs,
  });

  final String title;
  final String href;
  final int spineIndex;
  final List<_CaptureParagraph> paragraphs;
}

class _ParsedCapture {
  const _ParsedCapture({
    required this.title,
    required this.author,
    required this.abbreviation,
    required this.sections,
    required this.refCount,
    required this.duplicateRefCount,
    required this.warnings,
  });

  final String title;
  final String author;
  final String abbreviation;
  final List<_CaptureSection> sections;
  final int refCount;
  final int duplicateRefCount;
  final List<String> warnings;

  int get textBlockCount =>
      sections.fold<int>(0, (sum, section) => sum + section.paragraphs.length);
}

_ParsedCapture _parseCapture(String html, _WorkMeta meta) {
  final blocks = _extractReadableBlocks(html);
  final warnings = <String>[];
  if (blocks.isEmpty) {
    warnings.add('No clip-text paragraphs found in capture.html');
  }

  final allText = _normalizeWhitespace(blocks.join(' '));
  final abbreviation =
      _detectAbbreviation(allText) ?? meta.abbreviation.trim().toUpperCase();
  final detectedTitle = _detectTitle(blocks, abbreviation);
  final metadataTitle = meta.title.trim();
  final title = metadataTitle.isNotEmpty
      ? metadataTitle
      : detectedTitle ?? _frontMatterTitle(blocks, abbreviation, 'Captured Text');
  final author = _detectAuthor(meta, allText);
  if (_detectsMultipleLofAuthors(allText)) {
    warnings.add(
      'Multi-author follow-up: LOF_ATJ includes A. T. Jones and '
      'E. J. Waggoner; build-time importer keeps author as $author for now.',
    );
  }

  final refPattern = _paragraphRefPattern(abbreviation);
  final allRefs = refPattern
      .allMatches(allText)
      .map((match) => match.group(0)!)
      .toList(growable: false);
  final duplicateRefs = _duplicateRefs(allRefs);
  if (duplicateRefs.isNotEmpty) {
    warnings.add('Duplicate refs detected: ${duplicateRefs.join(', ')}');
  }

  final sections = <_CaptureSection>[];
  var currentTitle = _frontMatterTitle(blocks, abbreviation, title);
  var currentParagraphs = <_CaptureParagraph>[];

  void flushSection() {
    final sectionIndex = sections.length;
    sections.add(
      _CaptureSection(
        title: currentTitle,
        href: 'section_${sectionIndex + 1}',
        spineIndex: sectionIndex,
        paragraphs: List<_CaptureParagraph>.unmodifiable(currentParagraphs),
      ),
    );
    currentParagraphs = <_CaptureParagraph>[];
  }

  for (final rawBlock in blocks) {
    var block = _normalizeWhitespace(rawBlock);
    if (block.isEmpty) continue;

    final chapter = _chapterHeading(block, abbreviation);
    if (chapter != null) {
      if (currentParagraphs.isNotEmpty || sections.isEmpty) {
        flushSection();
      }
      currentTitle = chapter.title;
      block = chapter.remainingText;
    }

    currentParagraphs.addAll(_paragraphsFromBlock(block, abbreviation));
  }
  if (currentParagraphs.isNotEmpty || sections.isEmpty) {
    flushSection();
  }

  return _ParsedCapture(
    title: title,
    author: author,
    abbreviation: abbreviation,
    sections: List<_CaptureSection>.unmodifiable(sections),
    refCount: allRefs.length,
    duplicateRefCount: duplicateRefs.length,
    warnings: List<String>.unmodifiable(warnings),
  );
}

List<String> _extractReadableBlocks(String html) {
  final blocks = <String>[];
  final clipPattern = RegExp(
    r'''<div\b(?=[^>]*class\s*=\s*["'][^"']*\bclip-text\b[^"']*["'])[^>]*>(.*?)</div>''',
    dotAll: true,
    caseSensitive: false,
  );
  final paragraphPattern = RegExp(
    r'<p\b[^>]*>(.*?)</p>',
    caseSensitive: false,
    dotAll: true,
  );

  for (final clip in clipPattern.allMatches(html)) {
    final clipHtml = clip.group(1) ?? '';
    for (final paragraph in paragraphPattern.allMatches(clipHtml)) {
      final text = _stripHtml(paragraph.group(1) ?? '');
      if (text.isNotEmpty) blocks.add(text);
    }
  }
  if (blocks.isNotEmpty) {
    return List<String>.unmodifiable(blocks);
  }

  for (final paragraph in paragraphPattern.allMatches(html)) {
    final text = _stripHtml(paragraph.group(1) ?? '');
    if (text.isNotEmpty) blocks.add(text);
  }
  return List<String>.unmodifiable(blocks);
}

String _stripHtml(String html) {
  return _decodeHtmlEntities(
    html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' '),
  );
}

String _decodeHtmlEntities(String text) {
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#160;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&rsquo;', "'")
      .replaceAll('&lsquo;', "'")
      .replaceAll('&rdquo;', '"')
      .replaceAll('&ldquo;', '"');
}

String _normalizeWhitespace(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _detectAbbreviation(String text) {
  final match = RegExp(
    r'\b([A-Z][A-Z0-9_]{1,40})\s+\d+\.\d+\b',
  ).firstMatch(text);
  return match?.group(1)?.toUpperCase();
}

String? _detectTitle(List<String> blocks, String abbreviation) {
  for (final block in blocks) {
    final normalized = _normalizeWhitespace(block);
    if (normalized.isEmpty) continue;
    final match = RegExp(
      '^(.+?)\\s+${RegExp.escape(abbreviation)}\\s+\\d+\\b',
    ).firstMatch(normalized);
    final title = match?.group(1)?.trim();
    if (title != null &&
        title.isNotEmpty &&
        !title.toLowerCase().startsWith('chapter ')) {
      return title;
    }
  }
  return null;
}

String _detectAuthor(_WorkMeta meta, String text) {
  final upperAbbreviation = meta.abbreviation.toUpperCase();
  if (upperAbbreviation == 'LOF_ATJ' && text.contains('A. T. Jones')) {
    return 'A. T. Jones';
  }
  return meta.author;
}

bool _detectsMultipleLofAuthors(String text) {
  return text.contains('A. T. Jones') && text.contains('E. J. Waggoner');
}

String _frontMatterTitle(
  List<String> blocks,
  String abbreviation,
  String fallbackTitle,
) {
  if (blocks.isEmpty) return fallbackTitle;
  final normalized = _normalizeWhitespace(blocks.first);
  final titleMatch = RegExp(
    '^(.+?)\\s+${RegExp.escape(abbreviation)}\\s+\\d+\\s+(.+?)\\s+${RegExp.escape(abbreviation)}\\s+\\d+\\b',
  ).firstMatch(normalized);
  final candidate = titleMatch?.group(2)?.trim();
  if (candidate != null && candidate.isNotEmpty) {
    return candidate;
  }
  return fallbackTitle;
}

class _LeadingChapter {
  const _LeadingChapter({required this.title, required this.remainingText});

  final String title;
  final String remainingText;
}

_LeadingChapter? _chapterHeading(String block, String abbreviation) {
  final searchBlock = block.length > 500 ? block.substring(0, 500) : block;
  final match = RegExp(
    'Chapter\\s+(\\d+)\\s*[—-]\\s*(.+?)\\s+${RegExp.escape(abbreviation)}\\s+\\d+\\b',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(searchBlock);
  if (match == null) return null;
  final number = match.group(1) ?? '0';
  final title = _normalizeChapterTitle(match.group(2) ?? '');
  final remainingText = _normalizeWhitespace(block.substring(match.end));
  return _LeadingChapter(
    title: 'Chapter $number — $title',
    remainingText: remainingText,
  );
}

String _normalizeChapterTitle(String title) {
  return _normalizeWhitespace(
    title,
  ).replaceAll(RegExp(r'\s*[—-]\s*'), ' - ').trim();
}

List<_CaptureParagraph> _paragraphsFromBlock(
  String block,
  String abbreviation,
) {
  final paragraphs = <_CaptureParagraph>[];
  final refPattern = _paragraphRefPattern(abbreviation);
  var cursor = 0;
  for (final match in refPattern.allMatches(block)) {
    final ref = match.group(0) ?? '';
    final text = _stripLeadingAuthor(
      _removeInlinePageMarkers(
        block.substring(cursor, match.start),
        abbreviation,
      ),
    );
    if (ref.isNotEmpty && text.isNotEmpty) {
      paragraphs.add(_CaptureParagraph(text: text, ref: ref));
    }
    cursor = match.end;
  }
  return List<_CaptureParagraph>.unmodifiable(paragraphs);
}

String _removeInlinePageMarkers(String text, String abbreviation) {
  return _normalizeWhitespace(
    text.replaceAll(
      RegExp('\\b${RegExp.escape(abbreviation)}\\s+\\d+\\b'),
      ' ',
    ),
  );
}

String _stripLeadingAuthor(String text) {
  return _normalizeWhitespace(
    text.replaceFirst(
      RegExp(
        r'^(A\.\s*T\.\s*Jones|Alonzo\s+Trevier\s+Jones|E\.\s*J\.\s*Waggoner|Uriah\s+Smith)\s+',
      ),
      '',
    ),
  );
}

List<String> _duplicateRefs(List<String> refs) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final ref in refs) {
    if (!seen.add(ref)) {
      duplicates.add(ref);
    }
  }
  return List<String>.unmodifiable(duplicates.toList()..sort());
}

RegExp _paragraphRefPattern(String abbreviation) {
  return RegExp('\\b${RegExp.escape(abbreviation)}\\s+\\d+\\.\\d+\\b');
}

class _WorkMeta {
  const _WorkMeta({
    required this.title,
    required this.author,
    required this.abbreviation,
    required this.libraryItemId,
  });

  final String title;
  final String author;
  final String abbreviation;
  final String libraryItemId;
}

_WorkMeta _metaForFolder(String folderName) {
  final dir = Directory(
    p.join(Directory.current.path, 'assets', 'scans', folderName),
  );
  final metadataFile = File(p.join(dir.path, 'metadata.json'));
  if (metadataFile.existsSync()) {
    final metadata = PioneerCaptureFolderMetadata.fromFile(
      metadataFile,
      folderPath: dir.path,
    );
    return _WorkMeta(
      title: metadata.title ?? folderName,
      author: metadata.primaryContributorName ?? 'Unknown',
      abbreviation: metadata.preferredAbbreviation ?? folderName,
      libraryItemId: metadata.workId ?? folderName,
    );
  }
  return switch (folderName.toUpperCase()) {
    'LOF_ATJ' => const _WorkMeta(
      title: 'Lessons on Faith',
      author: 'A. T. Jones',
      abbreviation: 'LOF_ATJ',
      libraryItemId: 'library_item_research_pioneer_at_jones_lessons_on_faith',
    ),
    _ => _WorkMeta(
      title: folderName,
      author: 'Unknown',
      abbreviation: folderName,
      libraryItemId: folderName,
    ),
  };
}

// ---------------------------------------------------------------------------
// Import result
// ---------------------------------------------------------------------------

class _ImportResult {
  const _ImportResult({
    required this.folderName,
    required this.title,
    required this.author,
    required this.libraryItemId,
    required this.textBlocksInserted,
    required this.navItemsInserted,
    required this.refsInserted,
    required this.duplicateRefs,
    required this.warnings,
  });

  final String folderName;
  final String title;
  final String author;
  final String libraryItemId;
  final int textBlocksInserted;
  final int navItemsInserted;
  final int refsInserted;
  final int duplicateRefs;
  final List<String> warnings;
}

// ---------------------------------------------------------------------------
// Core import
// ---------------------------------------------------------------------------

Future<_ImportResult> _importCapture({
  required Database db,
  required _CaptureFolder capture,
  required bool overwrite,
}) async {
  final folderName = capture.folderName;
  final meta = _metaForFolder(folderName);
  final itemId = meta.libraryItemId;
  final now = DateTime.now().toUtc().toIso8601String();
  const deviceId = 'build_tool';
  final warnings = <String>[];

  // ── Task 2: Parse HTML ───────────────────────────────────────────────────
  final html = await File(capture.captureHtmlPath).readAsString(encoding: utf8);
  final parsed = _parseCapture(html, meta);
  warnings.addAll(parsed.warnings);

  if (parsed.textBlockCount == 0) {
    warnings.add('No paragraph text blocks found in capture.html');
    return _ImportResult(
      folderName: folderName,
      title: parsed.title,
      author: parsed.author,
      libraryItemId: itemId,
      textBlocksInserted: 0,
      navItemsInserted: 0,
      refsInserted: 0,
      duplicateRefs: parsed.duplicateRefCount,
      warnings: warnings,
    );
  }

  final normalizedCoverPath = await normalizeScanCoverAssets(
    sourcePath: capture.coverImagePath,
    workId: folderName,
    coverRoot: Directory('assets/library_covers'),
    warnings: warnings,
  );
  final relativeCaptureHtml = p.relative(
    capture.captureHtmlPath,
    from: Directory.current.path,
  );

  // ── Task 7: Overwrite — delete existing rows ─────────────────────────────
  if (overwrite) {
    print('[db] Clearing existing rows for $itemId ...');
    await db.transaction((txn) async {
      final existing = await txn.rawQuery(
        '''
        SELECT DISTINCT id
        FROM library_items
        WHERE id IN (?, ?, ?)
           OR title = ?
           OR relative_path LIKE ?
           OR source_url LIKE ?
        ''',
        [
          itemId,
          '${itemId}_egw_copied_range',
          folderName,
          parsed.title,
          '%$folderName%',
          '%$folderName%',
        ],
      );
      final refIndexed = await txn.rawQuery(
        '''
        SELECT DISTINCT library_item_id AS id
        FROM elibrary_ref_index
        WHERE book_abbrev = ?
        ''',
        [parsed.abbreviation],
      );
      final existingIds = <String>{
        ...existing.map((r) => r['id']?.toString() ?? ''),
        ...refIndexed.map((r) => r['id']?.toString() ?? ''),
      }.where((id) => id.isNotEmpty).toList(growable: false);
      for (final id in existingIds) {
        await txn.delete(
          'elibrary_ref_index',
          where: 'library_item_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'library_links',
          where: 'library_item_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'library_navigation_items',
          where: 'library_item_id = ?',
          whereArgs: [id],
        );
        await txn.delete('library_items', where: 'id = ?', whereArgs: [id]);
        print('[db]   Deleted existing item: $id');
      }
    });
  }

  // ── Tasks 3-6: Write all rows in one transaction ─────────────────────────
  var textBlocksInserted = 0;
  var navItemsInserted = 0;
  var refsInserted = 0;

  await db.transaction((txn) async {
    // Task 3: library_items
    await txn.insert('library_items', {
      'id': itemId,
      'title': parsed.title,
      'author': parsed.author,
      'file_name': 'capture.html',
      'relative_path': relativeCaptureHtml,
      'file_size': await File(capture.captureHtmlPath).length(),
      'mime_type': 'text/html',
      'file_format': 'html',
      'folder_type': 'Research',
      'library_role': 'pioneer',
      'collection_name': 'Pioneer Authors',
      'source_site': capture.metadata.sourceSite ?? 'egwwritings.org',
      'source_url': relativeCaptureHtml,
      'cover_path': normalizedCoverPath,
      'source_type': 'egw_html_capture',
      'date_added': now,
      'indexed_at': now,
      'index_status': 'indexed',
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'device_id': deviceId,
      'revision': 1,
      'sync_status': 'pending',
    });

    for (var i = 0; i < parsed.sections.length; i++) {
      final section = parsed.sections[i];
      // Task 5: library_navigation_items
      await txn.insert('library_navigation_items', {
        'id': '${itemId}_nav_${i + 1}',
        'library_item_id': itemId,
        'parent_id': null,
        'label': section.title,
        'href': section.href,
        'anchor_id': null,
        'spine_index': section.spineIndex,
        'sort_order': i + 1,
        'depth': 0,
        'nav_type': 'toc',
        'content_kind': 'chapter',
        'is_front_matter': 0,
        'is_body_start': i == 0 ? 1 : 0,
        'body_order': i + 1,
        'created_at': now,
        'updated_at': now,
        'device_id': deviceId,
        'revision': 1,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      navItemsInserted++;

      for (
        var paragraphIndex = 0;
        paragraphIndex < section.paragraphs.length;
        paragraphIndex++
      ) {
        final paragraph = section.paragraphs[paragraphIndex];
        final paragraphNumber = paragraphIndex + 1;

        // Task 4: library_text_blocks
        await txn.insert('library_text_blocks', {
          'library_item_id': itemId,
          'epub_href': section.href,
          'spine_index': section.spineIndex,
          'paragraph_index': paragraphNumber,
          'paragraph_on_section': paragraphNumber,
          'section_title': section.title,
          'plain_text': paragraph.text,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        textBlocksInserted++;

        // Task 6: elibrary_ref_index
        await txn.insert('elibrary_ref_index', {
          'library_item_id': itemId,
          'work_key': itemId,
          'edition_key': null,
          'edition_year': null,
          'book_title': parsed.title,
          'book_abbrev': parsed.abbreviation,
          'href': section.href,
          'anchor_id': null,
          'paragraph_index': paragraphNumber,
          'page_number': paragraph.pageNumber,
          'paragraph_on_page': paragraph.paragraphOnPage,
          'ref_code': paragraph.ref,
          'stable_ref': paragraph.ref,
          'plain_text': paragraph.text,
          'text_hash': _simpleHash(paragraph.text),
          'ref_source': 'egw_html_capture',
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        refsInserted++;
      }
    }
  });

  return _ImportResult(
    folderName: folderName,
    title: parsed.title,
    author: parsed.author,
    libraryItemId: itemId,
    textBlocksInserted: textBlocksInserted,
    navItemsInserted: navItemsInserted,
    refsInserted: refsInserted,
    duplicateRefs: parsed.duplicateRefCount,
    warnings: warnings,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<String?> normalizeScanCoverAssets({
  required String? sourcePath,
  required String workId,
  required Directory coverRoot,
  required List<String> warnings,
}) async {
  final rawPath = sourcePath?.trim() ?? '';
  if (rawPath.isEmpty) {
    warnings.add('No cover image found; app will use generated fallback tile.');
    return null;
  }

  try {
    final sourceFile = File(rawPath);
    final bytes = await sourceFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      warnings.add('Cover resize failed: could not decode $rawPath');
      return null;
    }

    final cropped = centerCropToBookCover(decoded);
    final displayCover = img.copyResize(
      cropped,
      width: 600,
      height: 900,
      interpolation: img.Interpolation.cubic,
    );
    final thumbnail = img.copyResize(
      cropped,
      width: 300,
      height: 450,
      interpolation: img.Interpolation.cubic,
    );

    final coverDir = coverRoot;
    final thumbDir = Directory(p.join(coverDir.path, 'thumbs'));
    await coverDir.create(recursive: true);
    await thumbDir.create(recursive: true);

    final displayPath = p.join(coverDir.path, '$workId.png');
    final thumbPath = p.join(thumbDir.path, '$workId.png');
    await File(
      displayPath,
    ).writeAsBytes(img.encodePng(displayCover), flush: true);
    await File(thumbPath).writeAsBytes(img.encodePng(thumbnail), flush: true);
    return thumbPath.replaceAll('\\', '/');
  } catch (error) {
    warnings.add('Cover resize failed for $rawPath: $error');
    return null;
  }
}

img.Image centerCropToBookCover(img.Image source) {
  const targetRatio = 2 / 3;
  final sourceRatio = source.width / source.height;
  var x = 0;
  var y = 0;
  var width = source.width;
  var height = source.height;

  if (sourceRatio > targetRatio) {
    width = (source.height * targetRatio).round().clamp(1, source.width);
    x = ((source.width - width) / 2).round();
  } else if (sourceRatio < targetRatio) {
    height = (source.width / targetRatio).round().clamp(1, source.height);
    y = ((source.height - height) / 2).round();
  }

  return img.copyCrop(source, x: x, y: y, width: width, height: height);
}

String _simpleHash(String text) {
  // FNV-1a 32-bit: fast, no crypto dep needed for a non-security hash
  var hash = 0x811c9dc5;
  for (final ch in text.codeUnits) {
    hash ^= ch;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

void _printResult(_ImportResult r) {
  print(
    '[import] ${r.folderName}: '
    '${r.textBlocksInserted} text blocks, '
    '${r.navItemsInserted} nav items, '
    '${r.refsInserted} refs'
    '${r.duplicateRefs > 0 ? ", ${r.duplicateRefs} duplicates skipped" : ""}',
  );
  for (final w in r.warnings) {
    print('[import]   warning: $w');
  }
}

// ---------------------------------------------------------------------------
// Report writer
// ---------------------------------------------------------------------------

Future<void> _writeReport(
  String reportPath,
  List<_ImportResult> results,
) async {
  final file = File(reportPath);
  await file.parent.create(recursive: true);
  final report = {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'tool': 'import_scans_to_asset_db',
    'works': results
        .map(
          (r) => {
            'folder_name': r.folderName,
            'title': r.title,
            'author': r.author,
            'library_item_id': r.libraryItemId,
            'text_blocks_inserted': r.textBlocksInserted,
            'nav_items_inserted': r.navItemsInserted,
            'refs_inserted': r.refsInserted,
            'duplicate_refs': r.duplicateRefs,
            'warnings': r.warnings,
          },
        )
        .toList(),
  };
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
}

// ---------------------------------------------------------------------------
// Arg parser
// ---------------------------------------------------------------------------

Map<String, Object?> _parseArgs(List<String> rawArgs) {
  final result = <String, Object?>{
    'source': 'assets/scans',
    'db': 'assets/databases/eLibrary.db',
    'overwrite': false,
    'report': null,
  };

  for (var i = 0; i < rawArgs.length; i++) {
    final arg = rawArgs[i];
    if (arg == '--overwrite') {
      result['overwrite'] = true;
    } else if (arg == '--source' && i + 1 < rawArgs.length) {
      result['source'] = rawArgs[++i];
    } else if (arg == '--db' && i + 1 < rawArgs.length) {
      result['db'] = rawArgs[++i];
    } else if (arg == '--report' && i + 1 < rawArgs.length) {
      result['report'] = rawArgs[++i];
    } else if (arg.startsWith('--source=')) {
      result['source'] = arg.substring('--source='.length);
    } else if (arg.startsWith('--db=')) {
      result['db'] = arg.substring('--db='.length);
    } else if (arg.startsWith('--report=')) {
      result['report'] = arg.substring('--report='.length);
    }
  }
  return result;
}
