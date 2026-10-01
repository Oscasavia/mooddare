import 'package:flutter/material.dart';
import 'package:mooddare/core/branding/mood_wink.dart';

/// The app's own mascot, with a quiet backdrop and no decorative symbols.
class WelcomeArtwork extends StatelessWidget {
  const WelcomeArtwork({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Mood Wink smiling and winking',
    child: ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1.55,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 360,
            height: 232,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0xFF242031), Color(0x000D0E14)],
                  radius: .7,
                ),
              ),
              child: const Center(child: MoodWink(size: 180)),
            ),
          ),
        ),
      ),
    ),
  );
}
