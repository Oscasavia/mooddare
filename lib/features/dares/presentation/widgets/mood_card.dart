import 'package:flutter/material.dart';
import 'package:mooddare/models/mood_model.dart';

class MoodCard extends StatelessWidget {
  final MoodModel mood;
  final VoidCallback onTap;
  const MoodCard({super.key, required this.mood, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: mood.color.withValues(alpha: .13),
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: mood.isLocked ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mood.icon, style: const TextStyle(fontSize: 38)),
            const Spacer(),
            Text(
              mood.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: mood.color,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${mood.dareList.length} little adventures',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
                Icon(Icons.arrow_outward, size: 16, color: mood.color),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
