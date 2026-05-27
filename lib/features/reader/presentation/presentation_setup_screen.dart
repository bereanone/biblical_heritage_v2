import 'dart:async';

import 'package:flutter/material.dart';

import '../data/presentation/presentation_item_settings_repository.dart';
import '../data/presentation/presentation_models.dart';
import '../data/presentation/presentation_slide_settings.dart';
import 'presentation_prep/tag_presentation_media_path_resolver.dart';
import 'presentation_slide_canvas.dart';
import 'viewer_presentation_settings.dart';

class PresentationSetupResult {
  const PresentationSetupResult({
    required this.startPresentation,
    required this.slideSettingsByKey,
  });

  final bool startPresentation;
  final Map<String, PresentationSlideSettings> slideSettingsByKey;
}

class PresentationSetupScreen extends StatefulWidget {
  const PresentationSetupScreen({
    super.key,
    required this.slides,
    required this.bookNames,
    required this.aspectRatioPreset,
    required this.mediaRootPath,
    required this.tagFamily,
    required this.tag,
    required this.initialSlideSettingsByKey,
  });

  final List<PresentationSlide> slides;
  final Map<int, String> bookNames;
  final PresentationAspectRatioPreset aspectRatioPreset;
  final String? mediaRootPath;
  final String tagFamily;
  final String tag;
  final Map<String, PresentationSlideSettings> initialSlideSettingsByKey;

  @override
  State<PresentationSetupScreen> createState() =>
      _PresentationSetupScreenState();
}

class _PresentationSetupScreenState extends State<PresentationSetupScreen> {
  final PresentationItemSettingsRepository _repository =
      PresentationItemSettingsRepository.instance;
  late final Map<String, PresentationSlideSettings> _slideSettingsByKey;
  int _index = 0;
  bool _saving = false;
  List<String> _mediaRootPaths = const <String>[];

  @override
  void initState() {
    super.initState();
    _slideSettingsByKey = {
      for (final slide in widget.slides)
        slide.settingsKey:
            widget.initialSlideSettingsByKey[slide.settingsKey] ??
            PresentationSlideSettings.defaults(),
    };
    _index = widget.slides.isEmpty
        ? 0
        : _index.clamp(0, widget.slides.length - 1);
    _loadMediaRoots();
  }

  Future<void> _loadMediaRoots() async {
    final roots = await TagPresentationMediaPathResolver.collectRootCandidates(
      preferredRootPath: widget.mediaRootPath,
    );
    if (!mounted) return;
    setState(() {
      _mediaRootPaths = roots;
    });
  }

  PresentationSlide get _currentSlide => widget.slides[_index];

  PresentationSlideSettings _settingsForSlide(PresentationSlide slide) {
    return _slideSettingsByKey[slide.settingsKey] ??
        PresentationSlideSettings.defaults();
  }

  Future<void> _persistSlide(PresentationSlide slide) async {
    final settings = _settingsForSlide(slide);
    setState(() => _saving = true);
    try {
      await _repository.saveSlideSettingsForTag(
        tagFamily: widget.tagFamily,
        tag: widget.tag,
        slide: slide,
        settings: settings,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _updateCurrentSlideSettings(
    PresentationSlideSettings Function(PresentationSlideSettings current)
    update,
  ) async {
    final slide = _currentSlide;
    final current = _settingsForSlide(slide);
    final next = update(current);
    setState(() {
      _slideSettingsByKey[slide.settingsKey] = next;
    });
    await _repository.saveSlideSettingsForTag(
      tagFamily: widget.tagFamily,
      tag: widget.tag,
      slide: slide,
      settings: next,
    );
  }

  Future<void> _setLayoutPreference(PresentationLayoutPreference value) async {
    await _updateCurrentSlideSettings(
      (current) => current.copyWith(layoutOverride: value),
    );
  }

  Future<void> _setAlignmentPreference(
    PresentationAlignmentPreference value,
  ) async {
    await _updateCurrentSlideSettings(
      (current) => current.copyWith(alignmentOverride: value),
    );
  }

  Future<void> _setAllowScroll(bool value) async {
    await _updateCurrentSlideSettings(
      (current) => current.copyWith(allowScroll: value),
    );
  }

  Future<void> _setFontSize(double value) async {
    await _updateCurrentSlideSettings(
      (current) =>
          current.copyWith(fontSizeOverride: value, autoFitEnabled: false),
    );
  }

  Future<void> _adjustFontSize(double delta) async {
    final current = _settingsForSlide(_currentSlide);
    final base = current.fontSizeOverride ?? 28.0;
    final next = (base + delta).clamp(12.0, 96.0).toDouble();
    await _setFontSize(next);
  }

  Future<void> _resetAutoFit() async {
    await _updateCurrentSlideSettings(
      (current) =>
          current.copyWith(clearFontSizeOverride: true, autoFitEnabled: true),
    );
  }

  Future<void> _goPrevious() async {
    if (_index <= 0) return;
    final previousSlide = _currentSlide;
    setState(() {
      _index -= 1;
    });
    await _persistSlide(previousSlide);
  }

  Future<void> _goNext() async {
    if (_index >= widget.slides.length - 1) return;
    final previousSlide = _currentSlide;
    setState(() {
      _index += 1;
    });
    await _persistSlide(previousSlide);
  }

  Future<void> _present() async {
    await _persistSlide(_currentSlide);
    if (!mounted) return;
    Navigator.of(context).pop(
      PresentationSetupResult(
        startPresentation: true,
        slideSettingsByKey: Map<String, PresentationSlideSettings>.unmodifiable(
          _slideSettingsByKey,
        ),
      ),
    );
  }

  Future<void> _closeWithoutPresenting() async {
    await _persistSlide(_currentSlide);
    if (!mounted) return;
    Navigator.of(context).pop(
      PresentationSetupResult(
        startPresentation: false,
        slideSettingsByKey: Map<String, PresentationSlideSettings>.unmodifiable(
          _slideSettingsByKey,
        ),
      ),
    );
  }

  Widget _compactDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          isDense: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildControlPanel(BuildContext context) {
    final slide = _currentSlide;
    final settings = _settingsForSlide(slide);
    final body = Theme.of(context).textTheme;
    final canGoPrevious = _index > 0;
    final canGoNext = _index < widget.slides.length - 1;

    Widget compactButton({
      required String label,
      required VoidCallback? onPressed,
      IconData? icon,
      bool filled = false,
    }) {
      final buttonStyle = filled
          ? FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            )
          : OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            );
      final child = icon == null
          ? Text(label)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Text(label),
              ],
            );
      return filled
          ? FilledButton(onPressed: onPressed, style: buttonStyle, child: child)
          : OutlinedButton(
              onPressed: onPressed,
              style: buttonStyle,
              child: child,
            );
    }

    return Material(
      color: const Color(0xFF101319).withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Slide ${slide.slideNumber}/${widget.slides.length}',
                    style: body.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    slide.slideTitle?.trim().isNotEmpty == true
                        ? slide.slideTitle!.trim()
                        : 'Preview and adjust',
                    style: body.bodySmall?.copyWith(
                      color: body.bodySmall?.color?.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              compactButton(
                label: 'A-',
                icon: Icons.text_decrease_rounded,
                onPressed: _saving
                    ? null
                    : () => unawaited(_adjustFontSize(-2)),
              ),
              const SizedBox(width: 8),
              compactButton(
                label: 'A+',
                icon: Icons.text_increase_rounded,
                onPressed: _saving ? null : () => unawaited(_adjustFontSize(2)),
              ),
              const SizedBox(width: 8),
              compactButton(
                label: 'Reset Auto Fit',
                onPressed: _saving ? null : () => unawaited(_resetAutoFit()),
              ),
              const SizedBox(width: 10),
              _compactDropdown<PresentationAlignmentPreference>(
                label: 'Alignment',
                value:
                    settings.alignmentOverride ??
                    PresentationAlignmentPreference.left,
                items: PresentationAlignmentPreference.values
                    .map(
                      (entry) =>
                          DropdownMenuItem<PresentationAlignmentPreference>(
                            value: entry,
                            child: Text(
                              presentationAlignmentPreferenceLabel(entry),
                            ),
                          ),
                    )
                    .toList(growable: false),
                onChanged: (next) {
                  if (next == null) return;
                  unawaited(_setAlignmentPreference(next));
                },
              ),
              const SizedBox(width: 10),
              _compactDropdown<PresentationLayoutPreference>(
                label: 'Layout',
                value:
                    settings.layoutOverride ??
                    PresentationLayoutPreference.auto,
                items: presentationLayoutPreferenceOptions
                    .map(
                      (entry) => DropdownMenuItem<PresentationLayoutPreference>(
                        value: entry,
                        child: Text(presentationLayoutPreferenceLabel(entry)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (next) {
                  if (next == null) return;
                  unawaited(_setLayoutPreference(next));
                },
              ),
              const SizedBox(width: 10),
              FilterChip(
                label: const Text('Allow Scroll'),
                selected: settings.allowScroll,
                onSelected: _saving
                    ? null
                    : (value) => unawaited(_setAllowScroll(value)),
              ),
              const SizedBox(width: 10),
              compactButton(
                label: 'Previous',
                icon: Icons.chevron_left_rounded,
                onPressed: canGoPrevious && !_saving
                    ? () => unawaited(_goPrevious())
                    : null,
              ),
              const SizedBox(width: 8),
              compactButton(
                label: 'Next',
                icon: Icons.chevron_right_rounded,
                onPressed: canGoNext && !_saving
                    ? () => unawaited(_goNext())
                    : null,
              ),
              const SizedBox(width: 8),
              compactButton(
                label: 'Present',
                onPressed: _saving ? null : () => unawaited(_present()),
                filled: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = _currentSlide;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D11),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 56, 16, 60),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: PresentationSlideCanvas(
                    key: ValueKey(slide.settingsKey),
                    slide: slide,
                    aspectRatioPreset: widget.aspectRatioPreset,
                    bookNames: widget.bookNames,
                    settings: _settingsForSlide(slide),
                    mediaRootPaths: _mediaRootPaths,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: _PresenterControlButton(
                icon: Icons.close_rounded,
                onPressed: _saving
                    ? null
                    : () => unawaited(_closeWithoutPresenting()),
                foregroundColor: const Color(0xFF9AA1AB),
                borderColor: const Color(0xFF3A404A),
                tooltip: 'Close setup',
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _buildControlPanel(context),
            ),
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
