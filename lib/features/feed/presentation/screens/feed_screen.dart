import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/models/post_model.dart';
import '../../data/repositories/post_repository.dart';
import '../widgets/dare_proof_card.dart';

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
  String? _moodId;
  final List<PostModel> _loaded = [];
  final _moodOptions = <String, String>{};
  Timer? _exitTimer;
  bool _exitArmed = false;

  void _disarmExit() {
    _exitTimer?.cancel();
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
      SystemNavigator.pop();
      return;
    }
    _refresh();
    _exitArmed = true;
    _exitTimer?.cancel();
    _exitTimer = Timer(const Duration(seconds: 2), _disarmExit);
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
      builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  'Filter by mood',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      title: const Text('All moods'),
                      trailing: _moodId == null
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(context, ''),
                    ),
                    for (final mood in moods)
                      ListTile(
                        title: Text(mood.value),
                        trailing: _moodId == mood.key
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, mood.key),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (_pages.hasClients) _pages.jumpToPage(0);
    setState(() {
      _moodId = selected.isEmpty ? null : selected;
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
    _exitTimer?.cancel();
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
      onPointerDown: (_) => _disarmExit(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('mooddare'),
          actions: [
            IconButton(
              tooltip: 'Filter by mood',
              onPressed: _filters,
              icon: Icon(
                _moodId == null ? Icons.tune_rounded : Icons.filter_alt_rounded,
              ),
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
                  onAction: () => setState(() {
                    _moodId = null;
                    _index = 0;
                    _posts = _repository.getPosts();
                  }),
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
