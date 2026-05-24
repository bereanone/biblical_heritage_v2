import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../data/library_catalog_service.dart';
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

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.onOpenBible,
    this.themeMode,
    this.onThemeChanged,
  });

  final VoidCallback? onOpenBible;
  final AppThemeMode? themeMode;
  final ValueChanged<AppThemeMode>? onThemeChanged;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}
