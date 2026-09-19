import 'dart:async';
import 'package:flutter/material.dart';
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
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? PostRepository();
    _posts = _repository.getPosts();
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('mooddare'),
      actions: [
        IconButton(
          tooltip: 'Refresh feed',
          onPressed: () => setState(() => _posts = _repository.getPosts()),
          icon: const Icon(Icons.refresh),
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
            onAction: () => setState(() => _posts = _repository.getPosts()),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final posts = snapshot.data!
            .where(
              (p) =>
                  !_hidden.contains(p.id) &&
                  !_blocked.contains(p.authorId) &&
                  p.expiresAt.toDate().isAfter(DateTime.now()),
            )
            .toList();
        if (posts.isEmpty) {
          return const AppEmptyState(
            icon: Icons.auto_awesome_outlined,
            title: 'The first moment could be yours',
            message:
                'Choose a mood in Discover, try a dare and share your capture. Moments stay in the feed for 24 hours.',
          );
        }
        final active = _index.clamp(0, posts.length - 1);
        return PageView.builder(
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
  );
}
