import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/features/feed/presentation/widgets/author_identity.dart';
import 'package:mooddare/models/user_model.dart';
import '../../data/social_repository.dart';
import '../../data/recent_search_store.dart';
import '../widgets/follow_button.dart';

class FindPeopleScreen extends StatefulWidget {
  final SocialRepository repository;
  final RecentSearchStore? recentSearches;
  const FindPeopleScreen({
    super.key,
    required this.repository,
    this.recentSearches,
  });
  @override
  State<FindPeopleScreen> createState() => _FindPeopleScreenState();
}

class _FindPeopleScreenState extends State<FindPeopleScreen> {
  final _search = TextEditingController();
  late final _history = widget.recentSearches ?? RecentSearchStore.instance;
  late final _historyUid = widget.repository.currentUserId;
  List<String> _recent = [];
  int _historyVersion = 0;
  bool _historyError = false;
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
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final uid = _historyUid;
    if (uid == null) return;
    final version = _historyVersion;
    try {
      final history = await _history.load(uid);
      if (mounted && version == _historyVersion) {
        setState(() {
          _recent = history;
          _historyError = false;
        });
      }
    } catch (_) {
      if (mounted && version == _historyVersion) {
        setState(() => _historyError = true);
      }
    }
  }

  void _saveHistory(List<String> values) {
    final uid = _historyUid;
    if (uid == null) return;
    _historyVersion++;
    setState(() {
      _recent = RecentSearchStore.clean(values);
      _historyError = false;
    });
    unawaited(
      _history.save(uid, _recent).catchError((Object _) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save recent searches on this device.'),
            ),
          );
        }
      }),
    );
  }

  void _submit(String value) {
    _search.text = value;
    _search.selection = TextSelection.collapsed(offset: value.length);
    _changed(value);
    _debounce?.cancel();
    if (_query.isEmpty) return;
    _saveHistory([_query, ..._recent]);
    FocusManager.instance.primaryFocus?.unfocus();
    // A submitted search replaces any pending request, including pagination.
    _generation++;
    _users.clear();
    _page = null;
    _load();
  }

  Widget _recentSearches() => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    children: [
      if (_historyError)
        TextButton(
          onPressed: _loadHistory,
          child: const Text('Could not load recent searches. Retry'),
        ),
      if (_recent.isEmpty)
        const AppEmptyState(
          illustration: MoodWink(size: 80),
          title: 'Find your people',
          message: 'Search a username to connect and follow along.',
        )
      else ...[
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent searches',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: () => _saveHistory([]),
              child: const Text('Clear all'),
            ),
          ],
        ),
        for (final query in _recent)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_rounded, size: 20),
            title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _submit(query),
            trailing: IconButton(
              tooltip: 'Remove $query from recent searches',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () =>
                  _saveHistory(_recent.where((item) => item != query).toList()),
            ),
          ),
      ],
    ],
  );

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
    final query = text.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    if (query == _query) {
      setState(() {});
      return;
    }
    _debounce?.cancel();
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
        final username = user.username;
        if (username != null && username.isNotEmpty) {
          _saveHistory([username, ..._recent]);
        }
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

  Widget _searchFailure(String label, VoidCallback retry) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MoodWink(size: 64, expression: MoodWinkExpression.error),
          const SizedBox(height: 12),
          TextButton(
            onPressed: retry,
            child: Text(label, textAlign: TextAlign.center),
          ),
        ],
      ),
    ),
  );

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
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
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
                ? _searchFailure(
                    'Could not load blocked accounts. Retry',
                    () => setState(_watchBlocks),
                  )
                : _query.isEmpty
                ? _recentSearches()
                : _blocked == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    key: ValueKey('people_results_$_query'),
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
                        _searchFailure('Could not search people. Retry', _load)
                      else if (people.isEmpty)
                        const AppEmptyState(
                          illustration: MoodWink(
                            size: 80,
                            expression: MoodWinkExpression.thinking,
                          ),
                          title: 'No matching people',
                          message:
                              'Try another username or check the spelling.',
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
