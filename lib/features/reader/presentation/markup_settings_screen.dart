import 'package:flutter/material.dart';

import '../data/highlight_groups_repository.dart';
import 'highlight_render.dart';
import 'viewer_search_dialog.dart';

class MarkupSettingsScreen extends StatefulWidget {
  const MarkupSettingsScreen({super.key});

  @override
  State<MarkupSettingsScreen> createState() => _MarkupSettingsScreenState();
}

class _MarkupSettingsScreenState extends State<MarkupSettingsScreen> {
  static const List<_PaletteChoice> _palette = <_PaletteChoice>[
    _PaletteChoice('Sun', '#F4DE45'),
    _PaletteChoice('Leaf', '#55B861'),
    _PaletteChoice('Sky', '#3E9BE6'),
    _PaletteChoice('Coral', '#FF533F'),
    _PaletteChoice('Amber', '#F6A21A'),
    _PaletteChoice('Violet', '#9749B8'),
    _PaletteChoice('Teal', '#7BCBC7'),
    _PaletteChoice('Rose', '#E77777'),
    _PaletteChoice('Blue', '#66AEEA'),
    _PaletteChoice('Stone', '#B8A39A'),
    _PaletteChoice('Mint', '#CFEAA5'),
    _PaletteChoice('Lilac', '#CFC3E8'),
  ];

  final HighlightGroupsRepository _repository = HighlightGroupsRepository();
  final TextEditingController _nameController = TextEditingController();

  bool _loading = true;
  List<HighlightGroupRecord> _groups = const <HighlightGroupRecord>[];
  Map<int, int> _usageCounts = const <int, int>{};
  _PaletteChoice _selected = _palette.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final groups = await _repository.loadGroups();
    final counts = <int, int>{};
    for (final group in groups) {
      counts[group.id] = await _repository.countHighlightsForGroup(group.id);
    }
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _usageCounts = counts;
      _loading = false;
    });
  }

  Future<void> _addGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final duplicate = _groups.any(
      (group) => group.name.trim().toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A highlight group named "$name" already exists.')),
      );
      return;
    }
    await _repository.createGroup(
      name: name,
      colorHex: _selected.hex,
    );
    _nameController.clear();
    await _load();
  }

  Future<void> _deleteGroup(HighlightGroupRecord group) async {
    final usedCount = _usageCounts[group.id] ?? 0;
    if (usedCount > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This group is currently in use and cannot be deleted.'),
        ),
      );
      return;
    }
    await _repository.deleteGroup(group.id);
    await _load();
  }

  Future<void> _showGroupUsage(HighlightGroupRecord group) async {
    if (!mounted) return;
    await showViewerSearchDialog(
      context,
      fontScale: 1.0,
      initialHighlightGroupId: group.id,
      startInHighlightMode: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sepiaTheme = Theme.of(context);
    final nightTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark().copyWith(
        surface: const Color(0xFF0E0E0E),
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF000000),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Markup Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              children: [
                Text(
                  'Highlight Groups',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                const Text('Step 1: Choose a color'),
                const Text('Step 2: Name the group'),
                const Text('Step 3: Tap Add'),
                const SizedBox(height: 18),
                Text(
                  'Create Group',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _palette.map((choice) {
                    final selected = choice == _selected;
                    return GestureDetector(
                      onTap: () => setState(() => _selected = choice),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: choice.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Group Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _addGroup,
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Live Preview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _PreviewCard(
                        title: 'Sepia',
                        backgroundColor:
                            sepiaTheme.scaffoldBackgroundColor,
                        child: _buildPreviewVerse(
                          _selected.color,
                          '12',
                          'Thy word have I hid in mine heart, that I might not sin against thee.',
                          false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PreviewCard(
                        title: 'Night',
                        backgroundColor:
                            nightTheme.scaffoldBackgroundColor,
                        child: _buildPreviewVerse(
                          _selected.color,
                          '12',
                          'Thy word have I hid in mine heart, that I might not sin against thee.',
                          true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ..._groups.map((group) {
                  final usedCount = _usageCounts[group.id] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildPreviewChip(group.color, group.name, false),
                                const SizedBox(height: 6),
                                Text(
                                  '$usedCount use${usedCount == 1 ? '' : 's'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Review highlights',
                            onPressed: () => _showGroupUsage(group),
                            icon: const Icon(Icons.visibility_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete group',
                            onPressed: () => _deleteGroup(group),
                            icon: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _buildPreviewChip(Color sourceColor, String label, bool isNight) {
    final spec = _resolveHighlightPreview(sourceColor, isNight);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: spec.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: sourceColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: spec.textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewVerse(
    Color sourceColor,
    String verseNumber,
    String verseText,
    bool isNight,
  ) {
    final spec = _resolveHighlightPreview(sourceColor, isNight);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: spec.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: spec.textColor,
            fontSize: 14,
            height: 1.35,
          ),
          children: [
            TextSpan(
              text: '$verseNumber ',
              style: TextStyle(
                color: spec.textColor.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: verseText,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.title,
    required this.backgroundColor,
    required this.child,
  });

  final String title;
  final Color backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title Theme',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark && title == 'Night'
                  ? Colors.white
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PaletteChoice {
  const _PaletteChoice(this.name, this.hex);

  final String name;
  final String hex;

  Color get color {
    final normalized = hex.replaceFirst('#', '');
    return Color(0xFF000000 | int.parse(normalized, radix: 16));
  }
}

class _HighlightPreviewSpec {
  const _HighlightPreviewSpec({
    required this.backgroundColor,
    required this.textColor,
  });

  final Color backgroundColor;
  final Color textColor;
}

_HighlightPreviewSpec _resolveHighlightPreview(Color sourceColor, bool isNight) {
  final spec = resolveHighlightRender(sourceColor, isNight);
  return _HighlightPreviewSpec(
    backgroundColor: spec.backgroundColor,
    textColor: spec.textColor,
  );
}
