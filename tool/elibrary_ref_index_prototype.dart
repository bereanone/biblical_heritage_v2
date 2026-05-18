import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final dbPath = args.isNotEmpty && args[0].trim().isNotEmpty
      ? args[0].trim()
      : '/Users/deanbowen/Development/eLibrary/Databases/user.db';
  final libraryItemId = args.length > 1 && args[1].trim().isNotEmpty
      ? args[1].trim()
      : 'library_item_research_epubs_research_user_en_gc_epub';
  final bookAbbrev = args.length > 2 && args[2].trim().isNotEmpty
      ? args[2].trim()
      : 'GC';

  stdout.writeln('== eLibrary Citation Prototype ==');
  stdout.writeln('dbPath: $dbPath');
  stdout.writeln('libraryItemId: $libraryItemId');
  stdout.writeln('bookAbbrev: $bookAbbrev');

  final summary = await _queryTsv(
    dbPath,
    '''
    SELECT
      COUNT(*) AS total_rows,
      SUM(CASE WHEN original_reference_text LIKE 'GC %'
                OR original_reference_text LIKE 'DA %'
                OR original_reference_text LIKE 'RC %'
                OR original_reference_text LIKE 'HB %'
                OR original_reference_text LIKE 'TMK %'
               THEN 1 ELSE 0 END) AS official_egw_refs,
      SUM(CASE WHEN original_reference_text LIKE '%:%' THEN 1 ELSE 0 END) AS bible_like_refs,
      SUM(CASE WHEN instr(COALESCE(anchor, ''), '[') > 0
                OR instr(COALESCE(full_paragraph, ''), '[') > 0
               THEN 1 ELSE 0 END) AS page_marker_rows
    FROM library_links
    WHERE library_item_id = '$libraryItemId'
      AND deleted_at IS NULL
    ''',
  );
  stdout.writeln('\nSummary:');
  for (final row in summary) {
    stdout.writeln('  ${row['total_rows']} rows');
    stdout.writeln('  ${row['official_egw_refs']} official EGW refs');
    stdout.writeln('  ${row['bible_like_refs']} bible-like refs');
    stdout.writeln('  ${row['page_marker_rows']} page-marker rows');
  }

  final markerRows = await _queryTsv(
    dbPath,
    '''
    SELECT
      id,
      epub_href AS href,
      spine_index,
      anchor_id,
      paragraph_index,
      original_reference_text,
      substr(COALESCE(full_paragraph, anchor, ''), 1, 120) AS full_paragraph_preview,
      CASE
        WHEN instr(COALESCE(anchor, ''), '[') > 0 THEN 'anchor'
        WHEN instr(COALESCE(full_paragraph, ''), '[') > 0 THEN 'full_paragraph'
        ELSE ''
      END AS marker_source,
      CASE
        WHEN instr(COALESCE(anchor, ''), '[') > 0 THEN substr(anchor, instr(anchor, '['), 24)
        WHEN instr(COALESCE(full_paragraph, ''), '[') > 0 THEN substr(full_paragraph, instr(full_paragraph, '['), 24)
        ELSE ''
      END AS marker_preview
    FROM library_links
    WHERE library_item_id = '$libraryItemId'
      AND deleted_at IS NULL
      AND (instr(COALESCE(anchor, ''), '[') > 0 OR instr(COALESCE(full_paragraph, ''), '[') > 0)
    ORDER BY href, paragraph_index, id
    LIMIT 10
    ''',
  );

  stdout.writeln('\nFirst 10 page-marker rows:');
  for (final row in markerRows) {
    stdout.writeln(
      '  id=${row['id']} href=${row['href']} spine=${row['spine_index']} '
      'anchor_id=${row['anchor_id'] ?? ''} paragraph_index=${row['paragraph_index']} '
      'original_reference_text=${row['original_reference_text']} '
      'marker_source=${row['marker_source']} marker_preview=${row['marker_preview']} '
      'full_preview=${row['full_paragraph_preview']}',
    );
  }

  final groupedRows = await _queryTsv(
    dbPath,
    '''
    WITH paragraph_groups AS (
      SELECT
        epub_href AS href,
        paragraph_index,
        MIN(id) AS id,
        MAX(spine_index) AS spine_index,
        MAX(anchor_id) AS anchor_id,
        MAX(COALESCE(full_paragraph, anchor, '')) AS sample_text,
        MAX(
          CASE
            WHEN instr(COALESCE(anchor, ''), '[') > 0 THEN 1
            WHEN instr(COALESCE(full_paragraph, ''), '[') > 0 THEN 1
            ELSE 0
          END
        ) AS has_marker,
        MAX(
          CASE
            WHEN instr(COALESCE(anchor, ''), '[') > 0 THEN substr(anchor, instr(anchor, '['), 24)
            WHEN instr(COALESCE(full_paragraph, ''), '[') > 0 THEN substr(full_paragraph, instr(full_paragraph, '['), 24)
            ELSE ''
          END
        ) AS marker_preview,
        GROUP_CONCAT(DISTINCT original_reference_text) AS refs
      FROM library_links
      WHERE library_item_id = '$libraryItemId'
        AND deleted_at IS NULL
      GROUP BY epub_href, paragraph_index
    )
    SELECT
      href,
      paragraph_index,
      id,
      spine_index,
      anchor_id,
      has_marker,
      marker_preview,
      refs,
      substr(sample_text, 1, 120) AS sample_preview
    FROM paragraph_groups
    ORDER BY href, paragraph_index
    ''',
  );

  stdout.writeln('\nGenerated refs by visible paragraph group:');
  String? currentHref;
  int? currentPageNumber;
  var paragraphOnPage = 0;
  var emitted = 0;
  for (final row in groupedRows) {
    final href = row['href']?.toString() ?? '';
    final paragraphIndex = int.tryParse(row['paragraph_index']?.toString() ?? '');
    final hasMarker = row['has_marker']?.toString() == '1';
    final markerPreview = row['marker_preview']?.toString() ?? '';
    final samplePreview = row['sample_preview']?.toString() ?? '';
    final refs = row['refs']?.toString() ?? '';
    if (href != currentHref) {
      currentHref = href;
      currentPageNumber = null;
      paragraphOnPage = 0;
    }
    if (hasMarker) {
      currentPageNumber = _extractPageNumber(markerPreview.isNotEmpty
              ? markerPreview
              : samplePreview) ??
          currentPageNumber;
      paragraphOnPage = 0;
    }
    if (currentPageNumber != null) {
      paragraphOnPage += 1;
      final candidateRef = '$bookAbbrev $currentPageNumber.$paragraphOnPage';
      if (emitted < 20) {
        stdout.writeln(
          '  ref=$candidateRef href=$href paragraph_index=$paragraphIndex '
          'has_marker=$hasMarker marker_preview=$markerPreview '
          'refs=$refs preview=$samplePreview',
        );
        emitted += 1;
      }
    }
  }

  stdout.writeln('\nPhrase checks:');
  final checks = <String>[
    'If thou hadst known, even thou',
    'From the crest of Olivet',
  ];
  for (final phrase in checks) {
    final query = await _queryTsv(
      dbPath,
      '''
      SELECT
        epub_href AS href,
        paragraph_index,
        original_reference_text,
        substr(COALESCE(full_paragraph, anchor, ''), 1, 150) AS sample_preview
      FROM library_links
      WHERE library_item_id = '$libraryItemId'
        AND deleted_at IS NULL
        AND lower(COALESCE(full_paragraph, anchor, '')) LIKE '%${_escapeLike(phrase.toLowerCase())}%'
      ORDER BY href, paragraph_index
      LIMIT 10
      ''',
    );
    if (query.isEmpty) {
      stdout.writeln('  "$phrase" not found in library_links text.');
    } else {
      stdout.writeln('  "$phrase":');
      for (final row in query) {
        stdout.writeln(
          '    href=${row['href']} paragraph_index=${row['paragraph_index']} '
          'original_reference_text=${row['original_reference_text']} '
          'preview=${row['sample_preview']}',
        );
      }
    }
  }
}

Future<List<Map<String, String>>> _queryTsv(
  String dbPath,
  String sql,
) async {
  final result = await Process.run(
    'sqlite3',
    <String>[
      '-header',
      '-separator',
      '\t',
      dbPath,
      sql,
    ],
  );
  if (result.exitCode != 0) {
    throw StateError('sqlite3 failed: ${result.stderr}');
  }
  final output = (result.stdout as String).trim();
  if (output.isEmpty) return <Map<String, String>>[];
  final lines = const LineSplitter().convert(output);
  if (lines.isEmpty) return <Map<String, String>>[];
  final headers = lines.first.split('\t');
  final rows = <Map<String, String>>[];
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final cells = line.split('\t');
    final row = <String, String>{};
    for (var i = 0; i < headers.length; i++) {
      row[headers[i]] = i < cells.length ? cells[i] : '';
    }
    rows.add(row);
  }
  return rows;
}

int? _extractPageNumber(String text) {
  final match = RegExp(r'\[(\d{1,4})\]').firstMatch(text);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

String _escapeLike(String input) {
  return input.replaceAll('%', r'\%').replaceAll('_', r'\_');
}
