import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Original, offline artwork: mood stickers rather than a camera illustration.
class WelcomeArtwork extends StatelessWidget {
  const WelcomeArtwork({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'A playful collage of curious, bold and joyful moods',
    child: ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1.6,
        child: FittedBox(
          fit: BoxFit.contain,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.noScaling),
            child: SizedBox(
              width: 360,
              height: 225,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(48),
                        gradient: const RadialGradient(
                          colors: [Color(0xFF30263F), Color(0x000D0E14)],
                          radius: .8,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 34,
                    top: 31,
                    child: Transform.rotate(
                      angle: -.13,
                      child: Container(
                        width: 162,
                        height: 170,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC5B4FF),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 24,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CURIOUS',
                              style: TextStyle(
                                color: Color(0xFF302448),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: SizedBox(
                                  width: 100,
                                  height: 100,
                                  child: CustomPaint(painter: _SmilePainter()),
                                ),
                              ),
                            ),
                            Text(
                              'What if…?',
                              style: TextStyle(
                                color: Color(0xFF302448),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    top: 44,
                    child: Transform.rotate(
                      angle: .16,
                      child: Container(
                        width: 132,
                        height: 144,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFBFE4D2),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x44000000),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BOLD',
                              style: TextStyle(
                                color: Color(0xFF203C35),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Icon(
                                  Icons.bolt_rounded,
                                  size: 72,
                                  color: Color(0xFF203C35),
                                ),
                              ),
                            ),
                            Text(
                              'Go for it.',
                              style: TextStyle(
                                color: Color(0xFF203C35),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 137,
                    bottom: 4,
                    child: Transform.rotate(
                      angle: -.08,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC9AE),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x44000000),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.wb_sunny_outlined,
                              size: 20,
                              color: Color(0xFF613B2D),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'A little joy',
                              style: TextStyle(
                                color: Color(0xFF613B2D),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    right: 30,
                    top: 4,
                    child: Icon(
                      Icons.auto_awesome,
                      color: Color(0xFFFFC9AE),
                      size: 28,
                    ),
                  ),
                  const Positioned(
                    left: 6,
                    bottom: 32,
                    child: Icon(
                      Icons.add_rounded,
                      color: Color(0xFFBFE4D2),
                      size: 24,
                    ),
                  ),
                  Positioned(
                    left: 9,
                    top: 38,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFC5B4FF),
                        shape: BoxShape.circle,
                      ),
                    ),
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

class _SmilePainter extends CustomPainter {
  const _SmilePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF302448)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(size.center(Offset.zero), 41, paint);
    canvas.drawLine(const Offset(36, 37), const Offset(36, 47), paint);
    canvas.drawLine(const Offset(64, 37), const Offset(64, 47), paint);
    canvas.drawArc(
      const Rect.fromLTWH(29, 43, 42, 30),
      .15,
      math.pi - .3,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SmilePainter oldDelegate) => false;
}
