import 'package:flutter/material.dart';
import 'stat_item.dart';

class StatsAndBadges extends StatelessWidget {
  final int daresCompleted, totalLikes;
  const StatsAndBadges({
    super.key,
    required this.daresCompleted,
    required this.totalLikes,
  });
  @override
  Widget build(BuildContext context) {
    final points = daresCompleted * 10 + totalLikes * 2;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              alignment: WrapAlignment.spaceAround,
              spacing: 16,
              runSpacing: 16,
              children: [
                StatItem(value: '$daresCompleted', label: 'Moments'),
                StatItem(value: '$totalLikes', label: 'Likes'),
                StatItem(value: '$points', label: 'Points'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Level ${points ~/ 100 + 1}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: (points % 100) / 100,
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 10),
        Text(
          '${100 - points % 100} points to your next level',
          style: const TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 28),
        const Text(
          'Milestones',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        ListTile(
          leading: Icon(
            daresCompleted > 0
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
          ),
          title: const Text('Your first moment'),
          subtitle: const Text('Share a completed dare'),
        ),
        ListTile(
          leading: Icon(
            daresCompleted >= 10
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
          ),
          title: const Text('Making memories'),
          subtitle: const Text('Share 10 moments'),
        ),
        ListTile(
          leading: Icon(
            totalLikes >= 10
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
          ),
          title: const Text('Spreading good energy'),
          subtitle: const Text('Receive 10 likes'),
        ),
      ],
    );
  }
}
