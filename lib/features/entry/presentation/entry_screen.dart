import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_mode.dart';
import '../../reader/presentation/bible_explorer_screen.dart';

class EntryScreen extends StatefulWidget {
  const EntryScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeChanged;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  void _handleThemeSelected(AppThemeMode mode) {
    widget.onThemeChanged(mode);
  }

  void _showAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About'),
        content: const Text(
          'Biblical Heritage\n'
          'Version 2.0\n'
          '© 2026 Dean Bowen — All Rights Reserved.\n'
          'Built with Flutter.\n\n'
          'Help: open Utilities for setup tools, then Bible Explorer for study controls and tutorials.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _enterApp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BibleExplorerScreen(
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSepiaTheme = widget.themeMode == AppThemeMode.sepia;
    final logoAsset = isSepiaTheme
        ? 'assets/icons/Logo2.png'
        : 'assets/icons/GoldLogo.png';

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 760 || constraints.maxWidth < 760;
            final logoHeight = compact ? 170.0 : 200.0;
            final titleSize = compact ? 34.0 : 40.0;
            final hashSize = compact ? 28.0 : 32.0;
            final quoteSize = compact ? 16.0 : 18.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              PopupMenuButton<AppThemeMode>(
                                tooltip: 'Choose theme',
                                initialValue: widget.themeMode,
                                onSelected: _handleThemeSelected,
                                itemBuilder: (context) => const [
                                  PopupMenuItem<AppThemeMode>(
                                    value: AppThemeMode.sepia,
                                    child: Text('Sepia'),
                                  ),
                                  PopupMenuItem<AppThemeMode>(
                                    value: AppThemeMode.night,
                                    child: Text('Night'),
                                  ),
                                ],
                                padding: EdgeInsets.zero,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Text(
                                  'aA',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Choose theme',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Image.asset(
                          logoAsset,
                          height: logoHeight,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Biblical Heritage',
                          style: TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            letterSpacing: 1.2,
                            height: 1.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          '#StudyBible',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: hashSize,
                            fontWeight: FontWeight.w900,
                            color: colorScheme.primary,
                            letterSpacing: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            children: [
                              Text(
                                '"But sanctify the Lord God in your hearts: and be ready always to give an answer to every man that asketh you a reason of the hope that is in you with meekness and fear:"',
                                style: TextStyle(
                                  fontFamily: 'NotoSerif',
                                  fontStyle: FontStyle.italic,
                                  fontSize: quoteSize,
                                  color: colorScheme.onSurface,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '1 Peter 3:15 (KJV)',
                                style: TextStyle(
                                  fontFamily: 'NotoSerif',
                                  fontSize: 16,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.primary.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Text(
                              'A shareable KJV study Bible for personal and group study with highlights, tags, and interlinear tools.',
                              style: TextStyle(
                                fontFamily: 'NotoSerif',
                                fontSize: 15,
                                color: colorScheme.onSurface.withValues(alpha: 0.92),
                                height: 1.3,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Column(
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 40,
                                      vertical: 20,
                                    ),
                                    textStyle: const TextStyle(fontSize: 20),
                                  ),
                                  onPressed: _enterApp,
                                  child: const Text('Bible Explorer'),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                      vertical: 12,
                                    ),
                                    textStyle: const TextStyle(fontSize: 16),
                                  ),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Utilities screen is next on the rebuild list.',
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text('Utilities'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            onPressed: _showAboutDialog,
                            child: const Text('About'),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
