import 'package:flutter/material.dart';
import 'package:mooddare/models/mood_model.dart';

class MoodCard extends StatelessWidget {
  final MoodModel mood;
  final VoidCallback onTap;
  const MoodCard({super.key, required this.mood, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final available = mood.isAvailable;
    final accent = ColorScheme.fromSeed(
      seedColor: mood.color,
      brightness: Brightness.dark,
    ).primary;
    final badge = mood.isSeasonal ? 'Seasonal' : mood.tier.label;
    final count = mood.dareList.length;
    final status = available
        ? '$count ${count == 1 ? 'dare' : 'dares'}'
        : 'Coming soon';
    final scale = MediaQuery.textScalerOf(context).scale(20) / 20;
    return Semantics(
      button: true,
      label: '${mood.name}, $badge, $status',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  mood.color.withValues(alpha: .16),
                  const Color(0xFF191B25),
                ],
              ),
              border: Border.all(color: mood.color.withValues(alpha: .16)),
            ),
            child: InkWell(
              onTap: onTap,
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          mood.icon,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(fontSize: 36),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            badge,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 46 * scale,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          mood.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          available
                              ? Icons.arrow_outward_rounded
                              : Icons.lock_outline_rounded,
                          size: 17,
                          color: available ? accent : Colors.white54,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
