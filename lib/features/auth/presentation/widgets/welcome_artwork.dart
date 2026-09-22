import 'package:flutter/material.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/branding/mood_wink.dart';

/// A static family of expressions, all drawn from the actual app-icon geometry.
class WelcomeArtwork extends StatelessWidget {
  const WelcomeArtwork({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Mood Wink with curious and cheerful expressions',
    child: ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1.55,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 360,
            height: 232,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xFF302840), Color(0x000D0E14)],
                        radius: .7,
                      ),
                    ),
                  ),
                ),
                const Positioned(left: 97, top: 29, child: MoodWink(size: 170)),
                Positioned(
                  left: 18,
                  top: 9,
                  child: Transform.rotate(
                    angle: -.12,
                    child: const _MoodBubble(
                      expression: MoodWinkExpression.thinking,
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 8,
                  child: Transform.rotate(
                    angle: .12,
                    child: const _MoodBubble(
                      expression: MoodWinkExpression.talking,
                    ),
                  ),
                ),
                const Positioned(
                  right: 25,
                  top: 20,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 24,
                    color: AppTheme.accent,
                  ),
                ),
                const Positioned(
                  left: 56,
                  bottom: 30,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFF74658F),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(dimension: 7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MoodBubble extends StatelessWidget {
  final MoodWinkExpression expression;
  const _MoodBubble({required this.expression});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: MoodWink(size: 48, expression: expression),
    ),
  );
}
