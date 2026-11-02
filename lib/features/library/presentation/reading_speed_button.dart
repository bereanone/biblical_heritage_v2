import 'package:flutter/material.dart';

String readingSpeedLabel(double speed) =>
    '${speed.toStringAsFixed(speed * 10 == (speed * 10).round() ? 1 : 2)}×';

/// Always visible beside the transport, independently of scrolling controls.
class ReadingSpeedButton extends StatelessWidget {
  const ReadingSpeedButton({
    super.key,
    required this.speed,
    required this.onChanged,
  });
  final double speed;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => PopupMenuButton<double>(
    tooltip: 'Reading speed',
    initialValue: speed,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final rate in const [.75, .9, 1.0, 1.1, 1.25, 1.5])
        PopupMenuItem(
          value: rate,
          child: Text(rate == 1 ? '1.0× (Normal)' : readingSpeedLabel(rate)),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed, size: 20),
          const SizedBox(width: 6),
          Text('Speed ${readingSpeedLabel(speed)}'),
        ],
      ),
    ),
  );
}
