import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One share mark across the feed, editor and settings.
class ShareIcon extends StatelessWidget {
  final Color? color;
  final double size;
  const ShareIcon({super.key, this.color, this.size = 22});
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -math.pi / 4,
    child: Icon(Icons.send_outlined, color: color, size: size),
  );
}
