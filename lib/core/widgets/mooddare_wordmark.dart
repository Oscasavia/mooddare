import 'package:flutter/material.dart';

/// The approved lettering, with its presentation background removed at paint
/// time. Keeping one source asset preserves the same letterforms on both pages.
class MoodDareWordmark extends StatelessWidget {
  final double width;
  const MoodDareWordmark({super.key, this.width = 148});

  // Measured visible lettering in the approved 2172x724 source, with a
  // two-pixel safety margin. Width now describes lettering, not PNG padding.
  static const _crop = Rect.fromLTWH(198, 190, 1776, 294);

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'MoodDare',
    header: true,
    image: true,
    child: ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * _crop.height / _crop.width,
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: _crop.width,
            height: _crop.height,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: -_crop.left,
                  top: -_crop.top,
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
                      width: 2172,
                      height: 724,
                      filterQuality: FilterQuality.high,
                    ),
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
