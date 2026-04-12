import 'package:flutter/material.dart';

class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key});

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
              spacing: 16,
              children: [
                Text('Study Workspace', style: theme.textTheme.titleLarge),
                Text(
                  'Notes, Strong\'s lookups, cross references, and commentary links can plug into this area without turning the reader itself into the control center for everything.',
                  style: theme.textTheme.bodyLarge,
                ),
                const _StudyTile(
                  icon: Icons.note_alt_outlined,
                  title: 'Notes',
                  subtitle: 'Per-verse annotations and notebook views',
                ),
                const _StudyTile(
                  icon: Icons.travel_explore_outlined,
                  title: 'Cross references',
                  subtitle: 'Parallel passages and topical trails',
                ),
                const _StudyTile(
                  icon: Icons.translate_outlined,
                  title: 'Word study',
                  subtitle: 'Strong\'s, morphology, and lexical detail',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StudyTile extends StatelessWidget {
  const _StudyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
