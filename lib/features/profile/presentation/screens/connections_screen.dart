import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/features/feed/presentation/widgets/author_identity.dart';
import 'package:mooddare/models/user_model.dart';
import '../../data/social_repository.dart';
import '../widgets/follow_button.dart';

class ConnectionsScreen extends StatefulWidget {
  final String userId;
  final bool followers;
  final SocialRepository repository;
  const ConnectionsScreen({
    super.key,
    required this.userId,
    required this.followers,
    required this.repository,
  });
  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late Stream<Set<String>> _ids;
  final _search = TextEditingController();
  final _hidden = <String>{};
  Set<String> _blocked = {};
  StreamSubscription<Set<String>>? _blockChanges;
  Set<String>? _lastIds;
  Future<List<UserModel>>? _people;
  @override
  void initState() {
    super.initState();
    _load();
    _blockChanges = widget.repository.blocked().listen(
      (ids) {
        if (mounted) setState(() => _blocked = ids);
      },
      onError: (Object _) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not load blocked accounts. Reopen this list to retry.',
              ),
            ),
          );
        }
      },
    );
  }

  void _load() {
    _ids = widget.repository.connections(
      widget.userId,
      followers: widget.followers,
    );
    _lastIds = null;
  }

  @override
  void dispose() {
    _blockChanges?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _block(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block @${user.username ?? 'member'}?'),
        content: const Text(
          'You will unfollow each other. You can unblock this account in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.block(user.id);
      if (mounted) setState(() => _hidden.add(user.id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not block this account. Try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.followers ? 'Followers' : 'Following')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search people',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<Set<String>>(
            stream: _ids,
            builder: (_, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Could not load people. Retry'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final ids = snapshot.data!;
              if (_lastIds == null ||
                  ids.length != _lastIds!.length ||
                  !ids.containsAll(_lastIds!)) {
                _lastIds = ids;
                _people = widget.repository.people(ids);
              }
              return FutureBuilder<List<UserModel>>(
                future: _people,
                builder: (_, people) {
                  if (people.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _people = widget.repository.people(ids);
                        }),
                        child: const Text('Could not load profiles. Retry'),
                      ),
                    );
                  }
                  if (!people.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final query = _search.text.trim().toLowerCase().replaceFirst(
                    RegExp(r'^@'),
                    '',
                  );
                  final users = people.data!
                      .where(
                        (u) =>
                            !_hidden.contains(u.id) &&
                            !_blocked.contains(u.id) &&
                            '${u.username ?? ''} ${u.name ?? ''}'
                                .toLowerCase()
                                .contains(query),
                      )
                      .toList();
                  if (users.isEmpty) {
                    return Center(
                      child: Text(
                        query.isEmpty
                            ? 'No people here yet'
                            : 'No matching people',
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (_, index) {
                      final user = users[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 0, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: AuthorIdentity(
                                user: user,
                                onPressed: () => Navigator.pushNamed(
                                  context,
                                  profileRoute,
                                  arguments: user.id,
                                ),
                              ),
                            ),
                            if (user.id != widget.repository.currentUserId) ...[
                              FollowButton(
                                userId: user.id,
                                repository: widget.repository,
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Account options',
                                onSelected: (_) => _block(user),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'block',
                                    child: Text('Block account'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
