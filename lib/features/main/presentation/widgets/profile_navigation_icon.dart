import 'package:flutter/material.dart';

/// The navigation destination supplies the accessible label and selected state.
class ProfileNavigationIcon extends StatelessWidget {
  final String? photoUrl;
  final bool selected;

  const ProfileNavigationIcon({
    super.key,
    this.photoUrl,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    final fallback = Icon(selected ? Icons.person : Icons.person_outline);
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, synchronouslyLoaded) =>
            frame != null || synchronouslyLoaded ? child : fallback,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}
