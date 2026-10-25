import 'package:flutter/material.dart';
import 'presentation_element.dart';
import '../data/presentation/note_image_layout.dart';
import '../data/presentation/presentation_slide_settings.dart';

/// Draft changes stay local until Save. The canvas reflows text, not imagery.
class PresentationSlideEditor extends StatefulWidget {
  const PresentationSlideEditor({
    super.key,
    required this.settings,
    required this.builder,
    required this.onSave,
    this.onEditingChanged,
  });
  final PresentationSlideSettings settings;
  final Widget Function(PresentationSlideSettings, ValueChanged<double>)
  builder;
  final Future<void> Function(PresentationSlideSettings) onSave;
  final ValueChanged<bool>? onEditingChanged;
  @override
  State<PresentationSlideEditor> createState() =>
      _PresentationSlideEditorState();
}

class _PresentationSlideEditorState extends State<PresentationSlideEditor> {
  late PresentationSlideSettings _saved = widget.settings;
  late PresentationSlideSettings _draft = _saved;
  bool _editing = false;
  bool _saving = false;
  double _resolvedFont = 28;
  double _gestureFont = 28;
  String? _selected;
  bool _controlsAtBottom = false;
  final Map<String, NoteImageLayout> _imageBases = {};
  bool get _imageSelected =>
      _selected != null && _imageBases.containsKey(_selected);
  // The renderer has already rejected adjustments from an older authored grid.
  NoteImageLayout get _activeImage => _imageBases[_selected]!;
  void _changeImage(String key, NoteImageLayout layout) {
    if (_saving || !_editing) return;
    setState(
      () => _draft = _draft.copyWith(
        imageLayouts: {..._draft.imageLayouts, key: layout},
      ),
    );
  }

  void _changeGap(double delta) {
    final layout = NoteImageLayout.fromJson({
      ..._activeImage.toJson(),
      'text_gap': (_activeImage.textGap + delta).clamp(0.0, 160.0),
    });
    if (layout != null) _changeImage(_selected!, layout);
  }

  String _selectedLabel = 'All text';
  double _elementBaseFont = 28;
  double get _activeFont => _selected == null
      ? _draft.fontSizeOverride ?? _resolvedFont
      : _draft.elementFontSizes[_selected] ?? _elementBaseFont;

  void _select(String key, String label, double font, Offset position) {
    if (_saving) return;
    final wasEditing = _editing;
    setState(() {
      if (!_editing) _draft = _saved;
      _editing = true;
      _selected = key;
      _selectedLabel = label;
      _elementBaseFont = font;
      _controlsAtBottom = position.dy < MediaQuery.sizeOf(context).height / 2;
    });
    if (!wasEditing) widget.onEditingChanged?.call(true);
  }

  void _undo() {
    setState(() {
      if (_selected == null) {
        _draft = _saved;
      } else if (_imageSelected) {
        final layouts = Map<String, NoteImageLayout>.of(_draft.imageLayouts)
          ..remove(_selected);
        if (_saved.imageLayouts[_selected] != null)
          layouts[_selected!] = _saved.imageLayouts[_selected]!;
        _draft = _draft.copyWith(imageLayouts: layouts);
      } else {
        final sizes = Map<String, double>.of(_draft.elementFontSizes)
          ..remove(_selected);
        final saved = _saved.elementFontSizes[_selected];
        if (saved != null) sizes[_selected!] = saved;
        final alignments = Map<String, PresentationAlignmentPreference>.of(
          _draft.elementAlignments,
        )..remove(_selected);
        final savedAlignment = _saved.elementAlignments[_selected];
        if (savedAlignment != null) alignments[_selected!] = savedAlignment;
        _draft = _draft.copyWith(
          elementFontSizes: sizes,
          elementAlignments: alignments,
        );
      }
    });
  }

  void _fit() {
    setState(() {
      if (_selected == null) {
        _draft = _draft.copyWith(
          clearFontSizeOverride: true,
          autoFitEnabled: true,
          elementFontSizes: const {},
        );
      } else if (_imageSelected) {
        _draft = _draft.copyWith(
          imageLayouts: Map<String, NoteImageLayout>.of(_draft.imageLayouts)
            ..remove(_selected),
        );
      } else {
        _draft = _draft.copyWith(
          elementFontSizes: Map<String, double>.of(_draft.elementFontSizes)
            ..remove(_selected),
        );
      }
    });
  }

  void _reportFont(double font) {
    if (font.isFinite && font > 0) _resolvedFont = font;
  }

  void _edit() {
    if (_editing) return;
    setState(() {
      _draft = _saved;
      _selected = null;
      _selectedLabel = 'All text';
      _editing = true;
    });
    widget.onEditingChanged?.call(true);
  }

  void _cancel() {
    setState(() {
      _draft = _saved;
      _editing = false;
    });
    widget.onEditingChanged?.call(false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_draft);
      if (!mounted) return;
      setState(() {
        _saved = _draft;
        _saving = false;
        _editing = false;
      });
      widget.onEditingChanged?.call(false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save. Your adjustment is still here; please try again.',
          ),
        ),
      );
    }
  }

  void _resize(double font) {
    final size = font.clamp(12.0, 160.0);
    setState(() {
      _draft = _selected == null
          ? _draft.copyWith(fontSizeOverride: size, autoFitEnabled: false)
          : _draft.copyWith(
              fontSizeOverride: _draft.fontSizeOverride ?? _resolvedFont,
              autoFitEnabled: false,
              elementFontSizes: {..._draft.elementFontSizes, _selected!: size},
            );
    });
  }

  void _align(PresentationAlignmentPreference alignment) {
    setState(() {
      _draft = _selected == null
          ? _draft.copyWith(alignmentOverride: alignment)
          : _draft.copyWith(
              fontSizeOverride: _draft.fontSizeOverride ?? _resolvedFont,
              autoFitEnabled: false,
              elementAlignments: {
                ..._draft.elementAlignments,
                _selected!: alignment,
              },
            );
    });
  }

  Widget _alignmentButton(
    PresentationAlignmentPreference alignment,
    IconData icon,
  ) => IconButton(
    tooltip: 'Align ${presentationAlignmentPreferenceToJson(alignment)}',
    icon: Icon(icon),
    isSelected:
        (_selected == null
            ? _draft.alignmentOverride
            : _draft.elementAlignments[_selected]) ==
        alignment,
    onPressed: _saving ? null : () => _align(alignment),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_editing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _editing && !_saving) _cancel();
    },
    child: PresentationElementScope(
      editing: _editing,
      selected: _selected,
      select: _select,
      registerImage: (key, layout) => _imageBases[key] = layout,
      changeImage: _changeImage,
      reportBaseFont: (key, font) {
        if (key == _selected) _elementBaseFont = font;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: _edit,
              onScaleStart: _editing && !_saving && !_imageSelected
                  ? (_) => _gestureFont = _activeFont
                  : null,
              onScaleUpdate: _editing && !_saving && !_imageSelected
                  ? (details) {
                      if (details.pointerCount >= 2)
                        _resize(_gestureFont * details.scale);
                    }
                  : null,
              child: widget.builder(_editing ? _draft : _saved, _reportFont),
            ),
          ),
          if (_editing)
            Positioned(
              top: _controlsAtBottom ? null : 8,
              bottom: _controlsAtBottom ? 8 : null,
              left: 60,
              right: 8,
              child: Theme(
                data: ThemeData.dark().copyWith(
                  platform: Theme.of(context).platform,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFFE0BE87),
                    brightness: Brightness.dark,
                  ),
                ),
                child: Material(
                  color: const Color(0xEE20242C),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _imageSelected
                              ? 'Image · protected text margin · drag to move'
                              : '$_selectedLabel · text size',
                          textAlign: TextAlign.center,
                        ),
                        if (!_imageSelected)
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              _alignmentButton(
                                PresentationAlignmentPreference.left,
                                Icons.format_align_left,
                              ),
                              _alignmentButton(
                                PresentationAlignmentPreference.center,
                                Icons.format_align_center,
                              ),
                              _alignmentButton(
                                PresentationAlignmentPreference.right,
                                Icons.format_align_right,
                              ),
                              _alignmentButton(
                                PresentationAlignmentPreference.justify,
                                Icons.format_align_justify,
                              ),
                            ],
                          ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Move controls',
                              icon: const Icon(Icons.swap_vert),
                              onPressed: _saving
                                  ? null
                                  : () => setState(
                                      () => _controlsAtBottom =
                                          !_controlsAtBottom,
                                    ),
                            ),
                            if (_selected != null)
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => setState(() {
                                        _selected = null;
                                        _selectedLabel = 'All text';
                                      }),
                                child: const Text('All text'),
                              ),
                            IconButton(
                              tooltip: _imageSelected
                                  ? 'Less image margin'
                                  : 'Smaller text',
                              onPressed: _saving
                                  ? null
                                  : () => _imageSelected
                                        ? _changeGap(-8)
                                        : _resize(_activeFont / 1.1),
                              icon: Icon(
                                _imageSelected
                                    ? Icons.remove
                                    : Icons.text_decrease,
                              ),
                            ),
                            IconButton(
                              tooltip: _imageSelected
                                  ? 'More image margin'
                                  : 'Larger text',
                              onPressed: _saving
                                  ? null
                                  : () => _imageSelected
                                        ? _changeGap(8)
                                        : _resize(_activeFont * 1.1),
                              icon: Icon(
                                _imageSelected
                                    ? Icons.add
                                    : Icons.text_increase,
                              ),
                            ),
                            TextButton(
                              onPressed: _saving ? null : _undo,
                              child: const Text('Undo'),
                            ),
                            TextButton(
                              onPressed: _saving ? null : _fit,
                              child: const Text('Fit'),
                            ),
                            TextButton(
                              onPressed: _saving ? null : _cancel,
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: _saving ? null : _save,
                              child: Text(_saving ? 'Saving…' : 'Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
