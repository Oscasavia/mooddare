import 'package:flutter/material.dart';
import '../../data/social_repository.dart';

class FollowButton extends StatefulWidget {
  final String userId;
  final SocialRepository repository;
  const FollowButton({
    super.key,
    required this.userId,
    required this.repository,
  });
  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  bool _busy = false;
  late final _following = widget.repository.connections(
    widget.repository.currentUserId ?? '',
    followers: false,
  );
  Future<void> _toggle(bool following) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.setFollowing(widget.userId, !following);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update follow. This account may be unavailable or blocked.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Set<String>>(
    stream: _following,
    builder: (_, snapshot) {
      final following = snapshot.data?.contains(widget.userId) ?? false;
      return FilledButton.tonal(
        onPressed: _busy || !snapshot.hasData || snapshot.hasError
            ? null
            : () => _toggle(following),
        child: Text(
          _busy
              ? 'Saving…'
              : following
              ? 'Following'
              : 'Follow',
        ),
      );
    },
  );
}
