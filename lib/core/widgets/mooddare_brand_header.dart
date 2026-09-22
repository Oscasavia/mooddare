import 'package:flutter/material.dart';
import '../branding/mood_wink.dart';
import 'mooddare_wordmark.dart';

/// A compact, static welcome from Mood Wink, with one accessible brand label.
class MoodDareBrandHeader extends StatelessWidget {
  const MoodDareBrandHeader({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      MoodWink(size: 64),
      SizedBox(height: 12),
      MoodDareWordmark(width: 128),
    ],
  );
}
