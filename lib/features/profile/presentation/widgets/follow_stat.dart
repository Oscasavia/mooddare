// lib/features/profile/presentation/widgets/follow_stat.dart
import 'package:flutter/material.dart';

class FollowStat extends StatelessWidget {
  final String count;
  final String label;
  const FollowStat({super.key, required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}
