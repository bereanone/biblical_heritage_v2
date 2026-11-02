import 'dart:convert';
import 'dart:io';
import '../lib/features/library/presentation/library_narration_text.dart';

/// Offline audio generation uses the same speech-only rules as the reader.
Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join()) as List;
  stdout.write(
    jsonEncode([
      for (final text in input) prepareLibraryNarrationText(text as String),
    ]),
  );
}
