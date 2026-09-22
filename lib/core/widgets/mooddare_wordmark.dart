import 'package:flutter/material.dart';

/// The approved lettering, with its presentation background removed at paint
/// time. Keeping one source asset preserves the same letterforms on both pages.
class MoodDareWordmark extends StatelessWidget {
  final double width;
  const MoodDareWordmark({super.key, this.width = 180});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'MoodDare',
    header: true,
    image: true,
    child: ExcludeSemantics(
      child: ColorFiltered(
        // The approved source has lavender letters on ink. Map that contrast
        // to alpha and a uniform brand color, avoiding an opaque image panel.
        colorFilter: const ColorFilter.matrix([
          0,
          0,
          0,
          0,
          197,
          0,
          0,
          0,
          0,
          180,
          0,
          0,
          0,
          0,
          255,
          0,
          0,
          2.5,
          0,
          -120,
        ]),
        child: Image.asset(
          'assets/branding/mooddare-wordmark.png',
          width: width,
          height: width / 5.6,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -.15),
          filterQuality: FilterQuality.high,
        ),
      ),
    ),
  );
}
