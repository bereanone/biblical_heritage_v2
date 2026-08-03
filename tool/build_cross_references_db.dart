import 'dart:io';

import 'cross_reference_importer.dart';

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final required = [
    'source',
    'output',
    'bible',
    'resolved-url',
    'download-date',
    'sha256',
  ];
  final missing = required
      .where((key) => options[key]?.isNotEmpty != true)
      .toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Missing options: ${missing.map((e) => '--$e').join(', ')}');
    stderr.writeln(
      'Usage: dart run tool/build_cross_references_db.dart '
      '--source FILE --output FILE --bible FILE --resolved-url URL '
      '--download-date YYYY-MM-DD --sha256 HEX',
    );
    exitCode = 64;
    return;
  }
  final importer = await CrossReferenceImporter.fromBibleDatabase(
    options['bible']!,
  );
  final summary = await importer.build(
    sourcePath: options['source']!,
    outputPath: options['output']!,
    metadata: {
      'resolved_download_url': options['resolved-url']!,
      'download_date': options['download-date']!,
      'source_sha256': options['sha256']!,
    },
  );
  stdout.writeln('Raw rows: ${summary.rawRows}');
  stdout.writeln('Expanded relationships: ${summary.expandedRelationships}');
  stdout.writeln('Unique relationships: ${summary.importedRows}');
  stdout.writeln('Duplicates removed: ${summary.duplicatesRemoved}');
  stdout.writeln('Rejected rows: ${summary.rejectedRows}');
  stdout.writeln('Output: ${options['output']}');
}

Map<String, String> _parseArguments(List<String> arguments) {
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--') || index + 1 >= arguments.length) continue;
    result[argument.substring(2)] = arguments[++index];
  }
  return result;
}
