import 'dart:io';

import 'package:path/path.dart' as p;

/// What a picked folder actually contains, used to decide whether "Import
/// Pioneer Library" can route it through the existing CaptureClipper
/// import path or must clearly defer it (a folder of raw Pioneer EPUBs,
/// not yet supported for bulk import).
class PioneerFolderContentsSurvey {
  const PioneerFolderContentsSurvey({
    required this.hasHtml,
    required this.hasRawEpub,
  });

  final bool hasHtml;
  final bool hasRawEpub;

  /// A CaptureClipper-style folder always has HTML captures, so it is
  /// routed through the orchestrator's capture-folder import regardless of
  /// whether loose EPUBs also happen to sit alongside it.
  bool get supportsExistingCaptureImport => hasHtml;

  /// A folder that contains EPUBs but no HTML captures at all is exactly
  /// the "raw Pioneer EPUB folder" case Phase 2 must defer rather than
  /// silently importing or falling back to legacy behavior.
  bool get isRawEpubFolder => hasRawEpub && !hasHtml;
}

/// Scans [folder] (recursively) purely to classify its contents — never
/// reads file bodies, never writes, never moves anything.
Future<PioneerFolderContentsSurvey> surveyPioneerFolderContents(
  Directory folder,
) async {
  var hasHtml = false;
  var hasRawEpub = false;
  await for (final entity in folder.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final extension = p.extension(entity.path).toLowerCase();
    if (extension == '.html' || extension == '.htm') hasHtml = true;
    if (extension == '.epub') hasRawEpub = true;
  }
  return PioneerFolderContentsSurvey(hasHtml: hasHtml, hasRawEpub: hasRawEpub);
}
