import 'package:flutter/material.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key});

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
              spacing: 18,
              children: [
                Text('Reader', style: theme.textTheme.titleLarge),
                Text(
                  'The Bible reader should stay lean: navigation, text rendering, and study overlays can each live in separate files instead of one giant shell.',
                  style: theme.textTheme.bodyLarge,
                ),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Genesis 1:1\n\nIn the beginning God created the heaven and the earth.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('Choose Passage'),
                    ),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('Reader Settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
