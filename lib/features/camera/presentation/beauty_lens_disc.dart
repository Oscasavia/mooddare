import 'package:flutter/material.dart';
import '../../../core/branding/mood_wink.dart';
import '../domain/beauty_lens.dart';

/// Vector thumbnails share Mood-wink's exact contours at every carousel size.
class BeautyLensDisc extends StatelessWidget {
  final BeautyLens lens;
  const BeautyLensDisc({super.key, required this.lens});

  @override
  Widget build(BuildContext context) {
    if (lens.name == 'Original') {
      return DecoratedBox(
        key: const ValueKey('original_lens_disc'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .25),
        ),
        child: const SizedBox.expand(),
      );
    }
    final (top, bottom, icon) = switch (lens.name) {
      'Soft' => (0xFFF0C9C2, 0xFFAD7593, Icons.blur_on_rounded),
      'Glow' => (0xFFFFE2AA, 0xFFE99773, Icons.wb_sunny_outlined),
      'Wide eyes' => (0xFFB6DCEE, 0xFF697FBD, Icons.visibility_outlined),
      'Sculpt' => (0xFFCDC3F1, 0xFF8774B3, Icons.face_retouching_natural),
      'Studio' => (0xFFF2CEEA, 0xFFA583CB, Icons.auto_awesome),
      'Rosy' => (0xFFFFB8C8, 0xFFC4597C, Icons.local_florist_outlined),
      'Natural' => (0xFFB8CBB9, 0xFF52776C, null),
      'Peach' => (0xFFF4BE9B, 0xFFBD7060, null),
      'Soft Glam' => (0xFFC5A1CC, 0xFF765474, null),
      'Heart Halo' => (0xFFF4B1D2, 0xFF8B66B5, null),
      'Golden Hour' => (0xFFE9C07C, 0xFFAA703E, null),
      _ => (0xFFA9E5D8, 0xFF548EAA, Icons.tune_rounded),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(top), Color(bottom)],
        ),
      ),
      child: icon != null
          ? Icon(icon, color: Colors.white, size: 28)
          : Padding(
              padding: const EdgeInsets.all(10),
              child: CustomPaint(
                key: ValueKey('lens_portrait_${lens.name}'),
                painter: _LensPortraitPainter(lens),
                child: const SizedBox.expand(),
              ),
            ),
    );
  }
}

class _LensPortraitPainter extends CustomPainter {
  final BeautyLens lens;
  const _LensPortraitPainter(this.lens);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    if (lens.heartHalo) {
      for (var i = 0; i < 5; i++) {
        final x = 12.0 + i * 19;
        final y = 10.0 + (i - 2).abs() * 3;
        final heart = Path()
          ..moveTo(x, y + 9)
          ..cubicTo(x - 18, y - 2, x - 6, y - 13, x, y - 5)
          ..cubicTo(x + 6, y - 13, x + 18, y - 2, x, y + 9)
          ..close();
        canvas.drawPath(
          heart,
          Paint()..color = Color(i.isEven ? 0xFFFF87AE : 0xFFD5B8FF),
        );
      }
      canvas.translate(8, 20);
      canvas.scale(.84);
    }
    canvas.drawPath(
      MoodWinkGeometry.path(1),
      Paint()..color = const Color(0xFFFFEBD9),
    );
    final cheek = Paint()
      ..color = const Color(
        0xFFD66B85,
      ).withValues(alpha: .2 + (lens.blush ?? 0) * .5);
    canvas.drawOval(const Rect.fromLTWH(16, 60, 19, 10), cheek);
    canvas.drawOval(const Rect.fromLTWH(73, 51, 17, 9), cheek);
    final mouth = Path();
    for (final command in MoodWinkGeometry.smile) {
      if (command.isEmpty) {
        mouth.close();
      } else if (command.length == 2) {
        mouth.moveTo(command[0], command[1]);
      } else {
        mouth.cubicTo(
          command[0],
          command[1],
          command[2],
          command[3],
          command[4],
          command[5],
        );
      }
    }
    canvas.drawPath(
      mouth,
      Paint()
        ..color = Color(
          lens.lipShade.swatch,
        ).withValues(alpha: .3 + (lens.lips ?? 0) * .7),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LensPortraitPainter oldDelegate) =>
      oldDelegate.lens != lens;
}
