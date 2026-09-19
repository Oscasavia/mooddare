import 'package:flutter/material.dart';

/// Only the photo determines the frame's size. Controls float inside its clip.
class PhotoReviewFrame extends StatelessWidget {
  final Widget photo;
  final Widget? controls;

  const PhotoReviewFrame({super.key, required this.photo, this.controls});

  @override
  Widget build(BuildContext context) => Center(
    child: ClipRRect(
      key: const ValueKey('photo_review_frame'),
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          photo,
          if (controls != null)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .66,
                    ),
                    child: DecoratedBox(
                      key: const ValueKey('photo_controls_overlay'),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0xB3000000),
                            Color(0xDB000000),
                          ],
                          stops: [0, .3, 1],
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                        child: controls!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
