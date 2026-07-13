import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../data/library_catalog_service.dart';
import '../data/library_recent_items.dart';
import '../data/library_section_heuristics.dart';
import '../../utilities/data/pioneer_captured_html_import_availability_service.dart';
import '../../utilities/data/pioneer_captured_html_import_folder_service.dart';
import 'library_book_reader_screen.dart';
import 'library_catalog_search_dialog.dart';
import 'library_navigation_tree.dart';
import 'library_font_scale.dart';
import '../../utilities/presentation/elibrary_setup_screen.dart';
import '../../utilities/presentation/library_root_setup_screen.dart';

part 'library_screen_state.dart';
part 'library_screen_header.dart';
part 'library_screen_browser.dart';
part 'library_screen_toc.dart';
part 'library_screen_helpers.dart';

enum _LibraryTab { books, recent }

enum _LibraryView { shelf, list }

typedef CapturedImportAvailabilityLoader =
    Future<PioneerCapturedHtmlAvailableImportReport> Function();

Future<PioneerCapturedHtmlAvailableImportReport>
_defaultCapturedImportAvailabilityLoader() {
  return PioneerCapturedHtmlImportAvailabilityService.instance.refresh();
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.onOpenBible,
    this.themeMode,
    this.onThemeChanged,
    this.capturedImportAvailabilityLoader,
    this.initialCapturedImportReport,
  });

  final VoidCallback? onOpenBible;
  final AppThemeMode? themeMode;
  final ValueChanged<AppThemeMode>? onThemeChanged;
  final CapturedImportAvailabilityLoader? capturedImportAvailabilityLoader;
  final PioneerCapturedHtmlAvailableImportReport? initialCapturedImportReport;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}
