import 'package:flutter/material.dart';
import 'package:mooddare/models/user_model.dart';

/// Visually grouped identity with separate, accessible avatar/name targets.
class AuthorIdentity extends StatelessWidget {
  final UserModel? user;
  final VoidCallback? onPressed;
  final Key? avatarKey, nameKey;
  final String fallback;
  final double avatarRadius;
  final bool compact;
  final Widget? besideName;
  static const textInset = 50.0;
  const AuthorIdentity({
    super.key,
    required this.user,
    required this.onPressed,
    this.avatarKey,
    this.nameKey,
    this.fallback = 'MoodDare member',
    this.avatarRadius = 18,
    this.compact = false,
    this.besideName,
  });

  @override
  Widget build(BuildContext context) {
    final username = user?.username;
    final label = username != null && username.isNotEmpty
        ? '@$username'
        : user?.name ?? fallback;
    final photo = user?.photoUrl;
    final nameButton = TextButton(
      key: nameKey,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 48),
        alignment: Alignment.centerLeft,
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'View $label profile',
          child: GestureDetector(
            key: avatarKey,
            onTap: onPressed,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Padding(
                padding: compact
                    ? const EdgeInsets.only(right: 4)
                    : EdgeInsets.zero,
                child: Align(
                  alignment: compact ? Alignment.centerRight : Alignment.center,
                  child: CircleAvatar(
                    radius: avatarRadius,
                    foregroundImage: photo != null && photo.isNotEmpty
                        ? NetworkImage(photo)
                        : null,
                    onForegroundImageError: photo != null && photo.isNotEmpty
                        ? (_, _) {}
                        : null,
                    child: Icon(Icons.person_outline, size: avatarRadius + 2),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: besideName == null
              ? nameButton
              : Row(
                  children: [
                    Flexible(child: nameButton),
                    const SizedBox(width: 6),
                    Flexible(child: besideName!),
                  ],
                ),
        ),
      ],
    );
  }
}
