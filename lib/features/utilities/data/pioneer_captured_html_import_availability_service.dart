import 'package:flutter/foundation.dart';

import 'pioneer_captured_html_import_folder_service.dart';
import 'pioneer_source_catalog.dart';

class PioneerCapturedHtmlImportAvailabilityService {
  PioneerCapturedHtmlImportAvailabilityService._();

  static final PioneerCapturedHtmlImportAvailabilityService instance =
      PioneerCapturedHtmlImportAvailabilityService._();

  PioneerCapturedHtmlAvailableImportReport? _latestReport;

  PioneerCapturedHtmlAvailableImportReport? get latestReport => _latestReport;

  bool get hasAvailableImports => _latestReport?.hasAvailableImports == true;

  int get availableImportCount => _latestReport?.availableCount ?? 0;

  Future<PioneerCapturedHtmlAvailableImportReport> refresh({
    PioneerSourceCatalog? catalog,
  }) async {
    final report = await PioneerCapturedHtmlImportFolderService.instance
        .discoverConfiguredCloudFolderImports(catalog: catalog);
    _latestReport = report;
    debugPrint(
      'CaptureClipper availability refresh: ${report.availableCount} ready folder(s).',
    );
    return report;
  }

  void clear() {
    _latestReport = null;
  }
}
