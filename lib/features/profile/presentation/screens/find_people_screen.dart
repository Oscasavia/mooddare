import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/features/feed/presentation/widgets/author_identity.dart';
import 'package:mooddare/models/user_model.dart';
import '../../data/social_repository.dart';
import '../widgets/follow_button.dart';

class FindPeopleScreen extends StatefulWidget {
  final SocialRepository repository;
  const FindPeopleScreen({super.key, required this.repository});
  @override
  State<FindPeopleScreen> createState() => _FindPeopleScreenState();
}

class _FindPeopleScreenState extends State<FindPeopleScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  StreamSubscription<Set<String>>? _blocks;
  Set<String>? _blocked;
  bool _blockError = false, _busy = false, _error = false;
  int _generation = 0;
  String _query = '';
  PeoplePage? _page;
  final _users = <UserModel>[];

  @override
  void initState() {
    super.initState();
    _watchBlocks();
  }

  void _watchBlocks() {
    _blocks?.cancel();
    _blockError = false;
    _blocks = widget.repository.blocked().listen(
      (ids) {
        if (mounted) {
          setState(() {
            _blocked = ids;
            _blockError = false;
          });
        }
      },
      onError: (Object _) {
        if (mounted) setState(() => _blockError = true);
      },
    );
  }

  void _changed(String text) {
    _debounce?.cancel();
    final query = text.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    if (query == _query) {
      setState(() {});
      return;
    }
    _generation++;
    setState(() {
      _query = query;
      _users.clear();
      _page = null;
      _error = false;
      _busy = query.isNotEmpty;
    });
    if (query.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), _load);
    }
  }

  Future<void> _load() async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final page = await widget.repository.searchPeople(
        _query,
        after: _page?.next,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final known = _users.map((user) => user.id).toSet();
        _users.addAll(page.users.where((user) => known.add(user.id)));
        _page = page;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _error = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _blocks?.cancel();
    _search.dispose();
    super.dispose();
  }

  Widget _person(UserModel user) {
    final identity = AuthorIdentity(
      user: user,
      onPressed: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.pushNamed(context, profileRoute, arguments: user.id);
      },
    );
    final follow = FollowButton(
      key: ValueKey('follow_${user.id}'),
      userId: user.id,
      repository: widget.repository,
    );
    if (MediaQuery.textScalerOf(context).scale(14) > 20) {
      return Column(
        children: [
          identity,
          Align(alignment: Alignment.centerRight, child: follow),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: identity),
        const SizedBox(width: 8),
        follow,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = _users
        .where(
          (user) =>
              user.id != widget.repository.currentUserId &&
              !(_blocked?.contains(user.id) ?? true),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Find people')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              controller: _search,
              onChanged: _changed,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Search by username',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _changed('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _blockError
                ? Center(
                    child: TextButton(
                      onPressed: () => setState(_watchBlocks),
                      child: const Text(
                        'Could not load blocked accounts. Retry',
                      ),
                    ),
                  )
                : _query.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Find your people\nSearch a username to connect and follow along.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _blocked == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      for (final user in people)
                        Padding(
                          key: ValueKey('person_${user.id}'),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: _person(user),
                        ),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error)
                        Center(
                          child: TextButton(
                            onPressed: _load,
                            child: const Text('Could not search people. Retry'),
                          ),
                        )
                      else if (people.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No matching people',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (!_busy && !_error && _page?.next != null)
                        Center(
                          child: TextButton(
                            onPressed: _load,
                            child: const Text('Show more'),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
