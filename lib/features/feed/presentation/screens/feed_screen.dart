import 'dart:async';
import 'package:mooddare/features/profile/data/social_repository.dart';
import 'package:mooddare/features/profile/presentation/screens/find_people_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/core/widgets/mooddare_wordmark.dart';
import 'package:mooddare/models/post_model.dart';
import '../../data/repositories/post_repository.dart';
import '../widgets/dare_proof_card.dart';
import '../widgets/mood_filter_sheet.dart';

class FeedScreen extends StatefulWidget {
  final PostRepository? repository;
  const FeedScreen({super.key, this.repository});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _pages = PageController();
  final _hidden = <String>{};
  late Stream<List<PostModel>> _posts;
  late final PostRepository _repository;
  Timer? _clock;
  StreamSubscription<Set<String>>? _blocks;
  Set<String> _blocked = {};
  int _index = 0;
  String? _moodId, _moodName;
  final List<PostModel> _loaded = [];
  final _moodOptions = <String, String>{};
  bool _exitArmed = false;

  void _disarmExit() {
    _exitArmed = false;
  }

  void _refresh() {
    if (_pages.hasClients) _pages.jumpToPage(0);
    setState(() {
      _index = 0;
      _posts = _repository.getPosts(moodId: _moodId);
    });
  }

  void _back() {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (_exitArmed) {
      _disarmExit();
      SystemNavigator.pop();
      return;
    }
    _refresh();
    _exitArmed = true;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Feed refreshed. Press back again to exit.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _filters() async {
    _disarmExit();
    final moods = <String, String>{
      if (_moodOptions.isEmpty)
        for (final mood in [
          ...DaresRepository.starterMoods,
          ...DaresRepository.seasonalMoods,
        ])
          mood.id: mood.name,
      ..._moodOptions,
      for (final post in _loaded)
        if (post.moodId != null && post.moodName != null)
          post.moodId!: post.moodName!,
    }.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MoodFilterSheet(moods: moods, selectedId: _moodId),
    );
    if (!mounted || selected == null) return;
    _selectMood(
      selected.isEmpty ? null : selected,
      name: selected.isEmpty
          ? null
          : moods.firstWhere((mood) => mood.key == selected).value,
    );
  }

  void _selectMood(String? id, {String? name}) {
    _disarmExit();
    if (_pages.hasClients) _pages.jumpToPage(0);
    setState(() {
      _moodId = id;
      _moodName = name;
      _index = 0;
      _posts = _repository.getPosts(moodId: _moodId);
    });
  }

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PostRepository();
    _posts = _repository.getPosts(moodId: _moodId);
    _repository
        .getMoodOptions()
        .then((moods) {
          if (mounted) setState(() => _moodOptions.addAll(moods));
        })
        .catchError((Object _) {
          /* Local choices remain available offline. */
        });
    _blocks = _repository.blockedAuthors().listen(
      (authors) {
        if (mounted) setState(() => _blocked = authors);
      },
      onError: (Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Could not load blocked accounts. Please retry."),
            ),
          );
        }
      },
    );
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _blocks?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: Listener(
      // Android cancels the pointer when it takes over a system back swipe.
      // Only completed feed interactions should clear the second-back action.
      onPointerUp: (_) => _disarmExit(),
      child: Scaffold(
        appBar: AppBar(
          title: MoodDareWordmark(
            width: MediaQuery.sizeOf(context).width < 400 ? 124 : 148,
          ),
          bottom: _moodId == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(
                        key: const ValueKey('active_mood_filter'),
                        label: Text(
                          _moodName ?? _moodId!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: .14),
                        side: BorderSide.none,
                        onPressed: _filters,
                        onDeleted: () => _selectMood(null),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        deleteButtonTooltipMessage: 'Clear mood filter',
                      ),
                    ),
                  ),
                ),
          actions: [
            IconButton(
              tooltip: 'Find people',
              icon: const Icon(Icons.person_search_rounded),
              onPressed: () {
                _disarmExit();
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        FindPeopleScreen(repository: SocialRepository()),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Filter by mood',
              onPressed: _filters,
              icon: const Icon(Icons.filter_list_rounded),
            ),
          ],
        ),
        body: StreamBuilder<List<PostModel>>(
          stream: _posts,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load moments',
                message: 'Check your connection and try again.',
                actionLabel: 'Retry',
                onAction: () => setState(
                  () => _posts = _repository.getPosts(moodId: _moodId),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            for (final post in snapshot.data!) {
              if (!_loaded.any((p) => p.moodId == post.moodId)) {
                _loaded.add(post);
              }
            }
            final posts = snapshot.data!
                .where(
                  (p) =>
                      (_moodId == null || p.moodId == _moodId) &&
                      !_hidden.contains(p.id) &&
                      !_blocked.contains(p.authorId) &&
                      p.expiresAt.toDate().isAfter(DateTime.now()),
                )
                .toList();
            if (posts.isEmpty) {
              if (_moodId != null) {
                return AppEmptyState(
                  icon: Icons.filter_alt_outlined,
                  title: 'No moments in this mood yet',
                  message: 'Try another mood or see what everyone is sharing.',
                  actionLabel: 'Show all moods',
                  onAction: () => _selectMood(null),
                );
              }
              return const AppEmptyState(
                icon: Icons.auto_awesome_outlined,
                title: 'The first moment could be yours',
                message:
                    'Choose a mood in Discover, try a dare and share your capture. Moments stay in the feed for 24 hours.',
              );
            }
            final active = _index.clamp(0, posts.length - 1);
            return PageView.builder(
              key: ValueKey(_moodId),
              controller: _pages,
              scrollDirection: Axis.vertical,
              itemCount: posts.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => DareProofCard(
                key: ValueKey(posts[i].id),
                post: posts[i],
                repository: _repository,
                isActive: i == active,
                onHidden: () => setState(() => _hidden.add(posts[i].id)),
              ),
            );
          },
        ),
      ),
    ),
  );
}
