import 'package:flutter/material.dart';
import 'package:mooddare/core/compact_count.dart';
import '../../data/social_repository.dart';
import '../screens/connections_screen.dart';
import 'follow_stat.dart';

class ProfileConnections extends StatefulWidget {
  final String userId;
  final int moments;
  final SocialRepository repository;
  const ProfileConnections({
    super.key,
    required this.userId,
    required this.moments,
    required this.repository,
  });
  @override
  State<ProfileConnections> createState() => _ProfileConnectionsState();
}

class _ProfileConnectionsState extends State<ProfileConnections> {
  late final _followers = widget.repository.connections(
    widget.userId,
    followers: true,
  );
  late final _following = widget.repository.connections(
    widget.userId,
    followers: false,
  );
  Widget _count(bool followers) => StreamBuilder<Set<String>>(
    stream: followers ? _followers : _following,
    builder: (_, snapshot) => TextButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ConnectionsScreen(
            userId: widget.userId,
            followers: followers,
            repository: widget.repository,
          ),
        ),
      ),
      child: FollowStat(
        count: snapshot.hasData ? compactCount(snapshot.data!.length) : '—',
        label: followers ? 'Followers' : 'Following',
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: FollowStat(
          count: compactCount(widget.moments),
          label: 'Moments',
        ),
      ),
      Expanded(child: _count(true)),
      Expanded(child: _count(false)),
    ],
  );
}
