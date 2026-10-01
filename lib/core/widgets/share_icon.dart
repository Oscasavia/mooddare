import 'package:flutter/material.dart';

/// Sharing outside MoodDare is distinct from the paper-plane Send dare action.
class ShareIcon extends StatelessWidget {
  final Color? color;
  final double size;
  const ShareIcon({super.key, this.color, this.size = 18});
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.share_outlined, color: color, size: size);
}
