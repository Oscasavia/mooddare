import 'package:flutter/material.dart';
import 'package:mooddare/core/branding/profile_cover_color.dart';

/// The avatar center sits on the cover's lower edge, with a surface-colored rim.
class ProfileCoverHeader extends StatelessWidget {
  final ProfileCoverColor color;
  final Widget avatar;
  final double horizontalInset;
  const ProfileCoverHeader({
    super.key,
    required this.color,
    required this.avatar,
    this.horizontalInset = 12,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 174,
    child: Stack(
      children: [
        Positioned(
          top: 0,
          left: horizontalInset,
          right: horizontalInset,
          height: 120,
          child: DecoratedBox(
            key: const ValueKey('profile_cover_background'),
            decoration: BoxDecoration(
              color: color.color,
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Positioned(
          top: 66,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                shape: BoxShape.circle,
              ),
              child: avatar,
            ),
          ),
        ),
      ],
    ),
  );
}
