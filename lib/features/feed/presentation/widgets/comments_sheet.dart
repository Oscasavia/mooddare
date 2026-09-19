import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:mooddare/models/comment_model.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/models/user_model.dart';
import '../../data/repositories/post_repository.dart';

Future<void> showComments(
  BuildContext context,
  PostModel post,
  PostRepository repository,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => CommentsSheet(post: post, repository: repository),
);

class CommentsSheet extends StatefulWidget {
  final PostModel post;
  final PostRepository repository;
  const CommentsSheet({
    super.key,
    required this.post,
    required this.repository,
  });
  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _authors = <String, Future<UserModel?>>{};
  late Stream<List<CommentModel>> _comments;
  StreamSubscription<Set<String>>? _blocks;
  Set<String> _blocked = {};
  String _commentId = const Uuid().v4();
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _comments = widget.repository.getComments(widget.post.id);
    _blocks = widget.repository.blockedAuthors().listen(
      (ids) {
        if (mounted) setState(() => _blocked = ids);
      },
      onError: (Object _) {
        if (mounted) {
          setState(
            () => _error =
                'Could not load blocked accounts. Reopen comments to retry.',
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _blocks?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (_sending || text.isEmpty || text.length > 500) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repository.addComment(widget.post.id, _commentId, text);
      if (!mounted) return;
      _text.clear();
      _commentId = const Uuid().v4();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not post your comment. Your draft is saved here—try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(CommentModel comment) async {
    try {
      await widget.repository.deleteComment(widget.post.id, comment.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not delete this comment. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.repository.currentUserId;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .68,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Comments',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close comments',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    if (_error != null)
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: StreamBuilder<List<CommentModel>>(
                        stream: _comments,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: TextButton.icon(
                                onPressed: () => setState(
                                  () => _comments = widget.repository
                                      .getComments(widget.post.id),
                                ),
                                icon: const Icon(Icons.refresh),
                                label: const Text(
                                  'Could not load comments. Retry',
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final comments = snapshot.data!
                              .where((c) => !_blocked.contains(c.authorId))
                              .toList();
                          if (comments.isEmpty) {
                            return const Center(
                              child: Text('Start the conversation ✨'),
                            );
                          }
                          return ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              final comment = comments[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: FutureBuilder<UserModel?>(
                                        future: _authors.putIfAbsent(
                                          comment.authorId,
                                          () => widget.repository.getAuthor(
                                            comment.authorId,
                                          ),
                                        ),
                                        builder: (context, snapshot) => Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              snapshot.data?.username == null
                                                  ? 'MoodDare member'
                                                  : '@${snapshot.data!.username}',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelLarge,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(comment.text),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (uid != null &&
                                        (uid == comment.authorId ||
                                            uid == widget.post.authorId))
                                      PopupMenuButton<String>(
                                        tooltip: 'Comment options',
                                        onSelected: (_) => _delete(comment),
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete comment'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                child: uid == null
                    ? const Text('Sign in to join the conversation.')
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _text,
                              enabled: !_sending,
                              minLines: 1,
                              maxLines: 3,
                              maxLength: 500,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Add a comment…',
                                counterText: '',
                              ),
                              onChanged: (_) => setState(
                                () => _commentId = const Uuid().v4(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filled(
                            tooltip: 'Post comment',
                            onPressed: _sending || _text.text.trim().isEmpty
                                ? null
                                : _send,
                            icon: _sending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_upward),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
