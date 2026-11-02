import 'package:flutter/material.dart';

import '../../../core/theme/app_settings_service.dart';
import '../../reader/data/highlight_groups_repository.dart';
import '../../reader/presentation/highlight_paint_button.dart';

const List<_ElibraryHighlightPaletteChoice> _elibraryFallbackPalette =
    <_ElibraryHighlightPaletteChoice>[
      _ElibraryHighlightPaletteChoice('Sun', '#F4DE45'),
      _ElibraryHighlightPaletteChoice('Leaf', '#55B861'),
      _ElibraryHighlightPaletteChoice('Sky', '#3E9BE6'),
      _ElibraryHighlightPaletteChoice('Coral', '#FF533F'),
      _ElibraryHighlightPaletteChoice('Amber', '#F6A21A'),
      _ElibraryHighlightPaletteChoice('Violet', '#9749B8'),
      _ElibraryHighlightPaletteChoice('Teal', '#7BCBC7'),
      _ElibraryHighlightPaletteChoice('Rose', '#E77777'),
      _ElibraryHighlightPaletteChoice('Blue', '#66AEEA'),
      _ElibraryHighlightPaletteChoice('Stone', '#B8A39A'),
      _ElibraryHighlightPaletteChoice('Mint', '#CFEAA5'),
      _ElibraryHighlightPaletteChoice('Lilac', '#CFC3E8'),
    ];

Future<String?> showElibraryHighlightColorPicker(BuildContext context) async {
  final defaultColor = await AppSettingsService.instance
      .loadDefaultElibraryHighlightColorHex();
  final savedGroups = await HighlightGroupsRepository().loadGroups();
  final palette = <_ElibraryHighlightPaletteChoice>[];
  final seen = <String>{};

  void addChoice(String? hex, {String? label}) {
    final normalized = _normalizeHex(hex);
    if (normalized == null || !seen.add(normalized)) return;
    palette.add(
      _ElibraryHighlightPaletteChoice(label ?? normalized, normalized),
    );
  }

  addChoice(defaultColor, label: 'Last used');
  for (final group in savedGroups) {
    addChoice(
      group.colorHex,
      label: group.name.trim().isEmpty ? 'Saved color' : group.name.trim(),
    );
  }
  for (final choice in _elibraryFallbackPalette) {
    addChoice(choice.hex, label: choice.label);
  }
  addChoice('#F7D87D', label: 'Default');

  if (palette.isEmpty) {
    palette.add(const _ElibraryHighlightPaletteChoice('Default', '#F7D87D'));
  }

  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return _ElibraryHighlightColorPickerDialog(
        palette: palette,
        initialHex: _normalizeHex(defaultColor) ?? palette.first.hex,
      );
    },
  );
}

class _ElibraryHighlightColorPickerDialog extends StatefulWidget {
  const _ElibraryHighlightColorPickerDialog({
    required this.palette,
    required this.initialHex,
  });

  final List<_ElibraryHighlightPaletteChoice> palette;
  final String initialHex;

  @override
  State<_ElibraryHighlightColorPickerDialog> createState() =>
      _ElibraryHighlightColorPickerDialogState();
}

class _ElibraryHighlightColorPickerDialogState
    extends State<_ElibraryHighlightColorPickerDialog> {
  late String _selectedHex;

  @override
  void initState() {
    super.initState();
    _selectedHex = widget.initialHex;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Choose Highlight Color')),
          IconButton(
            tooltip: 'Highlighting help',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (helpContext) => AlertDialog(
                title: const Text('eLibrary highlighting'),
                content: const SingleChildScrollView(
                  child: Text(
                    'With text selected, open Range Actions and choose Highlight. '
                    'Choose a color, then tap Apply Highlight (the paintbrush button) '
                    'to paint the selected text. Choosing a color sample alone '
                    'does not apply it. Cancel leaves the text unchanged. '
                    'Use Clear Markup in Range Actions to remove highlighting '
                    'from the selected range.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(helpContext).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: widget.palette
                .map((choice) {
                  final selected =
                      choice.hex.toLowerCase() == _selectedHex.toLowerCase();
                  final swatchColor = _colorFromHex(choice.hex);
                  return GestureDetector(
                    onTap: () => setState(() => _selectedHex = choice.hex),
                    child: Tooltip(
                      message: choice.label,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: swatchColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? colorScheme.onSurface
                                : colorScheme.outline.withValues(alpha: 0.35),
                            width: selected ? 3 : 1.5,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    blurRadius: 4,
                                    spreadRadius: 0.5,
                                  ),
                                ]
                              : null,
                        ),
                        child: selected
                            ? Icon(
                                Icons.check,
                                size: 20,
                                color: _contrastTextColor(swatchColor),
                              )
                            : null,
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        HighlightPaintButton(
          onPressed: () => Navigator.of(context).pop(_selectedHex),
        ),
      ],
    );
  }
}

class _ElibraryHighlightPaletteChoice {
  const _ElibraryHighlightPaletteChoice(this.label, this.hex);

  final String label;
  final String hex;
}

Color _colorFromHex(String hex) {
  final normalized = _normalizeHex(hex)?.replaceFirst('#', '') ?? 'F7D87D';
  final value = int.tryParse(normalized, radix: 16) ?? 0xF7D87D;
  final argb = normalized.length == 8 ? value : (0xFF000000 | value);
  return Color(argb);
}

String? _normalizeHex(String? hex) {
  final value = hex?.trim() ?? '';
  if (value.isEmpty) return null;
  return value.startsWith('#') ? value : '#$value';
}

Color _contrastTextColor(Color color) {
  final luminance = color.computeLuminance();
  return luminance > 0.55 ? Colors.black : Colors.white;
}
