import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Append-only event trail for narration, in the same `narration-events.log`
/// the narrator already writes (the app's temp directory, which is
/// `Library/Caches` on iOS). Written synchronously and flushed so the last
/// lines survive the app being suspended or killed while the screen is locked.
/// Never throws: diagnostics must not interrupt speech.
class NarrationDiagnostics {
  NarrationDiagnostics._();

  static const _maxBytes = 1024 * 1024;
  static Future<File?>? _file;

  static Future<File?> _open() async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/narration-events.log');
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        file.writeAsStringSync('');
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  static void log(String message) {
    final opening = _file ??= _open();
    unawaited(
      opening.then((file) {
        try {
          file?.writeAsStringSync(
            '${DateTime.now().toIso8601String()} $message\n',
            mode: FileMode.append,
            flush: true,
          );
        } catch (_) {
          /* Best effort. */
        }
      }),
    );
  }
}
