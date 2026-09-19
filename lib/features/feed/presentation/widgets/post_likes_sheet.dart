import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/models/user_model.dart';
import '../../data/repositories/post_repository.dart';
import 'author_identity.dart';

Future<void> showPostLikes(
  BuildContext context,
  String postId,
  PostRepository repository,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => PostLikesSheet(postId: postId, repository: repository),
);

class PostLikesSheet extends StatefulWidget {
  final String postId;
  final PostRepository repository;
  const PostLikesSheet({
    super.key,
    required this.postId,
    required this.repository,
  });
  @override
  State<PostLikesSheet> createState() => _PostLikesSheetState();
}

class _PostLikesSheetState extends State<PostLikesSheet> {
  late Future<List<String>> _ids;
  final _authors = <String, Future<UserModel?>>{};
  StreamSubscription<Set<String>>? _blocks;
  Set<String> _blocked = {};
  bool _blocksReady = false, _blocksFailed = false;

  @override
  void initState() {
    super.initState();
    _ids = widget.repository.getPostLikerIds(widget.postId);
    _loadBlocks();
  }

  void _loadBlocks() {
    _blocks?.cancel();
    _blocks = widget.repository.blockedAuthors().listen(
      (ids) {
        if (mounted) {
          setState(() {
            _blocked = ids;
            _blocksReady = true;
            _blocksFailed = false;
          });
        }
      },
      onError: (Object _) {
        if (mounted) setState(() => _blocksFailed = true);
      },
    );
  }

  void _retry() {
    setState(() {
      _ids = widget.repository.getPostLikerIds(widget.postId);
      _blocksFailed = false;
    });
    _loadBlocks();
  }

  @override
  void dispose() {
    _blocks?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
            child: Text(
              'Liked by',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _ids,
              builder: (context, snapshot) {
                if (snapshot.hasError || _blocksFailed) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Could not load likes. Retry'),
                    ),
                  );
                }
                if (!snapshot.hasData || !_blocksReady) {
                  return const Center(child: CircularProgressIndicator());
                }
                final ids = snapshot.data!
                    .toSet()
                    .where((id) => !_blocked.contains(id))
                    .toList();
                if (ids.isEmpty) {
                  return const Center(child: Text('No likes to show yet.'));
                }
                // Profile reads are lazy: only visible rows and nearby rows are fetched.
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: ids.length,
                  itemBuilder: (context, index) {
                    final id = ids[index];
                    return FutureBuilder<UserModel?>(
                      future: _authors.putIfAbsent(
                        id,
                        () => widget.repository.getAuthor(id),
                      ),
                      builder: (context, author) {
                        if (author.hasError) {
                          return ListTile(
                            title: const Text('Could not load profile'),
                            trailing: IconButton(
                              tooltip: 'Retry profile',
                              icon: const Icon(Icons.refresh),
                              onPressed: () => setState(() {
                                _authors[id] = widget.repository.getAuthor(id);
                              }),
                            ),
                          );
                        }
                        return AuthorIdentity(
                          user: author.data,
                          fallback:
                              author.connectionState == ConnectionState.waiting
                              ? 'Loading…'
                              : 'Account unavailable',
                          avatarKey: ValueKey('liker_avatar_$id'),
                          nameKey: ValueKey('liker_name_$id'),
                          onPressed: author.data == null
                              ? null
                              : () => Navigator.pushNamed(
                                  context,
                                  profileRoute,
                                  arguments: id,
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
    ),
  );
}
