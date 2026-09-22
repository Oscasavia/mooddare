import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../app_theme.dart';

enum MoodWinkExpression { wink, smile, talking, thinking, angrySmile, error }

/// Clean vector reconstruction of the approved Mood Wink concept. Contours
/// are shared by Flutter and the native-resource exporter (M, C, Z commands).
class MoodWinkGeometry {
  static const adaptiveScale = .56;
  static const adaptiveOffset = 26.0;
  static const face = <List<double>>[
    [28, 16],
    [42, 14, 59, 10, 73, 6],
    [86, 1, 91, 9, 94, 24],
    [97, 39, 98, 61, 94, 74],
    [91, 87, 76, 93, 60, 95],
    [45, 98, 26, 100, 16, 92],
    [5, 84, 1, 66, 3, 49],
    [4, 32, 12, 20, 28, 16],
    [],
  ];
  static const leftEye = <List<double>>[
    [31, 31],
    [37, 30, 40, 37, 40, 45],
    [40, 54, 37, 60, 32, 60],
    [27, 60, 25, 53, 25, 46],
    [24, 38, 26, 32, 31, 31],
    [],
  ];
  static const openEye = <List<double>>[
    [67, 29],
    [73, 28, 77, 34, 78, 42],
    [79, 49, 75, 55, 70, 56],
    [64, 57, 61, 50, 61, 42],
    [60, 35, 62, 30, 67, 29],
    [],
  ];
  static const winkEye = <List<double>>[
    [57, 44],
    [63, 35, 73, 33, 80, 37],
    [84, 40, 81, 47, 77, 46],
    [70, 43, 66, 47, 63, 51],
    [59, 55, 53, 50, 57, 44],
    [],
  ];
  static const smile = <List<double>>[
    [34, 72],
    [31, 69, 33, 65, 37, 66],
    [48, 72, 59, 68, 66, 60],
    [70, 55, 76, 61, 72, 66],
    [62, 81, 45, 83, 34, 72],
    [],
  ];

  static const talkingMouth = <List<double>>[
    [35, 66],
    [45, 70, 59, 68, 68, 61],
    [73, 58, 75, 64, 71, 71],
    [64, 84, 44, 87, 35, 75],
    [31, 70, 31, 65, 35, 66],
    [],
  ];

  static const angryLeftEye = <List<double>>[
    [24, 34],
    [30, 36, 38, 41, 45, 43],
    [48, 44, 48, 40, 49, 42],
    [49, 51, 43, 57, 35, 56],
    [26, 55, 21, 47, 22, 37],
    [22, 34, 23, 33, 24, 34],
    [],
  ];
  static const angryRightEye = <List<double>>[
    [78, 31],
    [72, 33, 64, 39, 57, 41],
    [54, 42, 54, 38, 53, 40],
    [53, 49, 59, 55, 67, 54],
    [76, 53, 81, 45, 80, 34],
    [80, 31, 79, 30, 78, 31],
    [],
  ];

  static List<List<double>> rightEye(double wink) => [
    for (var i = 0; i < openEye.length; i++)
      [
        for (var j = 0; j < openEye[i].length; j++)
          ui.lerpDouble(openEye[i][j], winkEye[i][j], wink.clamp(0, 1))!,
      ],
  ];

  static Path path(
    double wink, {
    MoodWinkExpression expression = MoodWinkExpression.wink,
  }) {
    final result = Path()..fillType = PathFillType.evenOdd;
    for (final contour in [
      face,
      if (expression == MoodWinkExpression.wink ||
          expression == MoodWinkExpression.smile ||
          expression == MoodWinkExpression.talking ||
          expression == MoodWinkExpression.angrySmile) ...[
        expression == MoodWinkExpression.angrySmile ? angryLeftEye : leftEye,
        expression == MoodWinkExpression.angrySmile
            ? angryRightEye
            : rightEye(expression == MoodWinkExpression.wink ? wink : 0),
        expression == MoodWinkExpression.talking ? talkingMouth : smile,
      ],
    ]) {
      for (final command in contour) {
        if (command.isEmpty) {
          result.close();
        } else if (command.length == 2) {
          result.moveTo(command[0], command[1]);
        } else {
          result.cubicTo(
            command[0],
            command[1],
            command[2],
            command[3],
            command[4],
            command[5],
          );
        }
      }
    }
    if (expression == MoodWinkExpression.thinking) {
      // An upward glance, lifted brow and small off-center mouth: curious,
      // rather than upset. All features remain cutouts in the original face.
      final features = Path()
        ..addOval(const Rect.fromLTWH(31, 37, 10, 16))
        ..addOval(const Rect.fromLTWH(66, 32, 10, 16))
        ..moveTo(59, 22)
        ..cubicTo(66, 17, 76, 18, 81, 23)
        ..cubicTo(84, 26, 80, 30, 77, 27)
        ..cubicTo(72, 24, 67, 24, 62, 27)
        ..cubicTo(59, 29, 56, 25, 59, 22)
        ..close()
        ..moveTo(39, 71)
        ..lineTo(58, 66)
        ..cubicTo(62, 65, 63, 71, 59, 72)
        ..lineTo(40, 77)
        ..cubicTo(36, 78, 35, 72, 39, 71)
        ..close();
      return Path.combine(PathOperation.difference, result, features);
    }
    if (expression == MoodWinkExpression.error) {
      final features = Path();
      for (final center in [const Offset(33, 44), const Offset(69, 41)]) {
        features.addPolygon([
          for (final point in const [
            Offset(-7, -10),
            Offset(0, -3),
            Offset(7, -10),
            Offset(10, -7),
            Offset(3, 0),
            Offset(10, 7),
            Offset(7, 10),
            Offset(0, 3),
            Offset(-7, 10),
            Offset(-10, 7),
            Offset(-3, 0),
            Offset(-10, -7),
          ])
            center + point,
        ], true);
      }
      features.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(41, 70, 25, 6),
          const Radius.circular(3),
        ),
      );
      return Path.combine(PathOperation.difference, result, features);
    }
    return result;
  }
}

class MoodWink extends StatelessWidget {
  final double size;
  final double wink;
  final Color color;
  final MoodWinkExpression expression;
  const MoodWink({
    super.key,
    this.size = 128,
    this.wink = 1,
    this.color = AppTheme.accent,
    this.expression = MoodWinkExpression.wink,
  });

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: MoodWinkPainter(
          wink: wink,
          color: color,
          expression: expression,
        ),
      ),
    ),
  );
}

class MoodWinkPainter extends CustomPainter {
  final double wink;
  final Color color;
  final MoodWinkExpression expression;
  const MoodWinkPainter({
    required this.wink,
    required this.color,
    this.expression = MoodWinkExpression.wink,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.drawPath(
      MoodWinkGeometry.path(wink, expression: expression),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(MoodWinkPainter oldDelegate) =>
      wink != oldDelegate.wink ||
      color != oldDelegate.color ||
      expression != oldDelegate.expression;
}
