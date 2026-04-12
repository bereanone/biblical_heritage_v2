import 'package:flutter/material.dart';

import 'viewer_interlinear_settings.dart';

Future<ViewerInterlinearSettings?> showViewerInterlinearSettingsSheet(
  BuildContext context, {
  required ViewerInterlinearSettings settings,
}) {
  return Navigator.of(context).push<ViewerInterlinearSettings>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ViewerInterlinearSettingsScreen(settings: settings),
    ),
  );
}

class _ViewerInterlinearSettingsScreen extends StatefulWidget {
  const _ViewerInterlinearSettingsScreen({
    required this.settings,
  });

  final ViewerInterlinearSettings settings;

  @override
  State<_ViewerInterlinearSettingsScreen> createState() =>
      _ViewerInterlinearSettingsScreenState();
}

class _ViewerInterlinearSettingsScreenState
    extends State<_ViewerInterlinearSettingsScreen> {
  late ViewerInterlinearSettings _settings = widget.settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipSelectedColor = theme.colorScheme.primary;
    final chipUnselectedColor = theme.colorScheme.surfaceContainerHighest;
    final chipSelectedTextColor = theme.colorScheme.onPrimary;
    final chipUnselectedTextColor = theme.colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_settings),
        ),
        title: const Text('Interlinear Mode'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        children: [
          Text('Language Source', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              Chip(label: Text('Bible Tokens (Original Language)')),
            ],
          ),
          const SizedBox(height: 18),
          Text('Word Order', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Original Language Order'),
                selected: !_settings.englishOrder,
                selectedColor: chipSelectedColor,
                backgroundColor: chipUnselectedColor,
                checkmarkColor: chipSelectedTextColor,
                labelStyle: TextStyle(
                  color: !_settings.englishOrder
                      ? chipSelectedTextColor
                      : chipUnselectedTextColor,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) {
                  setState(() {
                    _settings = _settings.copyWith(englishOrder: false);
                  });
                },
              ),
              ChoiceChip(
                label: const Text('English (KJV) Order'),
                selected: _settings.englishOrder,
                selectedColor: chipSelectedColor,
                backgroundColor: chipUnselectedColor,
                checkmarkColor: chipSelectedTextColor,
                labelStyle: TextStyle(
                  color: _settings.englishOrder
                      ? chipSelectedTextColor
                      : chipUnselectedTextColor,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) {
                  setState(() {
                    _settings = _settings.copyWith(englishOrder: true);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsCheckRow(
            label: 'English Gloss',
            value: _settings.showEnglishGloss,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(showEnglishGloss: value);
              });
            },
          ),
          _SettingsCheckRow(
            label: 'Ancient Text',
            value: _settings.showOriginalText,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(showOriginalText: value);
              });
            },
          ),
          _SettingsCheckRow(
            label: 'Transliteration',
            value: _settings.showTransliteration,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(showTransliteration: value);
              });
            },
          ),
          _SettingsCheckRow(
            label: 'Pronunciation',
            value: _settings.showPronunciation,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(showPronunciation: value);
              });
            },
          ),
          _SettingsCheckRow(
            label: "Strong's Number",
            value: _settings.showStrongsNumber,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(showStrongsNumber: value);
              });
            },
          ),
          _SettingsCheckRow(
            label: 'Morphology',
            value: _settings.showMorphology,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(showMorphology: value);
              });
            },
          ),
        ],
      ),
    );
  }
}

class _SettingsCheckRow extends StatelessWidget {
  const _SettingsCheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (next) => onChanged(next ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
