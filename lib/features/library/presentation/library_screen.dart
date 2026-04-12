import 'package:flutter/material.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _FeatureCard(
      eyebrow: 'Library',
      title: 'Commentaries and reference works',
      description:
          'This screen can stay focused on browsing sources, downloads, and recent books without sharing state with the reader.',
      items: const [
        'Collections',
        'Recent books',
        'Pinned resources',
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.items,
  });

  final String eyebrow;
  final String title;
  final String description;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 14,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                Text(title, style: theme.textTheme.titleLarge),
                Text(description, style: theme.textTheme.bodyLarge),
                for (final item in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.arrow_forward_rounded),
                    title: Text(item),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
