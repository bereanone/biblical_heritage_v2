import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/study_bible_database.dart';
import '../data/presentation/presentation_models.dart';
import '../data/presentation/presentation_slide_settings.dart';
import 'presentation_slide_canvas.dart';
import 'viewer_presentation_settings.dart';

class ViewerPresentationScreen extends StatefulWidget {
  const ViewerPresentationScreen({
    super.key,
    required this.slides,
    required this.initialIndex,
    required this.aspectRatioPreset,
  });

  final List<PresentationSlide> slides;
  final int initialIndex;
  final PresentationAspectRatioPreset aspectRatioPreset;

  @override
  State<ViewerPresentationScreen> createState() =>
      _ViewerPresentationScreenState();
}

class _ViewerPresentationScreenState extends State<ViewerPresentationScreen> {
  final Map<int, String> _bookNames = <int, String>{};
  int _index = 0;
  bool _loadingBooks = true;
  String? _mediaRootPath;
  bool _loadingMediaRoot = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.slides.length - 1);
    _loadBooks();
    _loadMediaRootPath();
  }

  Future<void> _loadBooks() async {
    final books = await StudyBibleDatabase.instance.loadBooks();
    final names = {for (final book in books) book.bookNumber: book.bookName};
    if (!mounted) return;
    setState(() {
      _bookNames
        ..clear()
        ..addAll(names);
      _loadingBooks = false;
    });
  }

  Future<void> _loadMediaRootPath() async {
    final root = await _resolveMediaRootPath();
    if (!mounted) return;
    setState(() {
      _mediaRootPath = root;
      _loadingMediaRoot = false;
    });
  }

  Future<String?> _resolveMediaRootPath() async {
    final libraryRoot = await LibraryRootService.instance.libraryRootPath();
    if (libraryRoot != null && libraryRoot.trim().isNotEmpty) {
      return libraryRoot;
    }
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'studybible_media');
  }

  PresentationSlide get _currentSlide => widget.slides[_index];

  bool get _canGoPrevious => _index > 0;
  bool get _canGoNext => _index < widget.slides.length - 1;

  void _previous() {
    if (!_canGoPrevious) return;
    setState(() {
      _index -= 1;
    });
  }

  void _next() {
    if (!_canGoNext) return;
    setState(() {
      _index += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final background = const Color(0xFF0B0D11);
    final slide = _currentSlide;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PresentationSlideCanvas(
                key: ValueKey(slide.settingsKey),
                slide: slide,
                aspectRatioPreset: widget.aspectRatioPreset,
                bookNames: _bookNames,
                settings: PresentationSlideSettings.defaults(),
                mediaRootPath: _mediaRootPath,
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: _PresenterControlButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).maybePop(),
                foregroundColor: const Color(0xFF9AA1AB),
                borderColor: const Color(0xFF3A404A),
                tooltip: 'Back',
              ),
            ),
            Positioned(
              bottom: 14,
              left: 14,
              child: _PresenterControlButton(
                icon: Icons.chevron_left_rounded,
                onPressed: _canGoPrevious ? _previous : null,
                foregroundColor: const Color(0xFF9AA1AB),
                borderColor: const Color(0xFF3A404A),
                tooltip: 'Previous slide',
              ),
            ),
            Positioned(
              bottom: 14,
              right: 14,
              child: _PresenterControlButton(
                icon: Icons.chevron_right_rounded,
                onPressed: _canGoNext ? _next : null,
                foregroundColor: const Color(0xFF9AA1AB),
                borderColor: const Color(0xFF3A404A),
                tooltip: 'Next slide',
              ),
            ),
            if (_loadingBooks || _loadingMediaRoot) const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

class _PresenterControlButton extends StatelessWidget {
  const _PresenterControlButton({
    required this.icon,
    required this.onPressed,
    required this.foregroundColor,
    required this.borderColor,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color foregroundColor;
  final Color borderColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF11151B).withValues(alpha: 0.98),
              border: Border.all(color: borderColor, width: 1.4),
            ),
            child: Icon(
              icon,
              size: 18,
              color: onPressed == null
                  ? foregroundColor.withValues(alpha: 0.7)
                  : foregroundColor,
            ),
          ),
        ),
      ),
    );
  }
}
