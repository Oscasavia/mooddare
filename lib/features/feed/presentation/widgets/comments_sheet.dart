import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:mooddare/core/app_routes.dart';
import 'author_identity.dart';
import 'package:mooddare/core/compact_count.dart';
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
  final _focus = FocusNode();
  final _liking = <String>{};
  CommentModel? _editing;
  String _draft = "";
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
    _focus.dispose();
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
      final editing = _editing;
      if (editing == null) {
        await widget.repository.addComment(widget.post.id, _commentId, text);
      } else {
        await widget.repository.editComment(widget.post.id, editing.id, text);
      }
      if (!mounted) return;
      if (_editing != null) {
        _cancelEdit();
      } else {
        _text.clear();
        _commentId = const Uuid().v4();
      }
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _editing == null
              ? 'Could not post your comment. Your draft is saved here—try again.'
              : 'Could not save changes. Your edit is kept here—try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _edit(CommentModel comment) {
    if (_sending || comment.authorId != widget.repository.currentUserId) return;
    if (_editing == null) _draft = _text.text;
    setState(() {
      _editing = comment;
      _error = null;
      _text.text = comment.text;
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    });
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editing = null;
      _text.text = _draft;
      _draft = '';
      _error = null;
    });
  }

  Future<void> _like(CommentModel comment) async {
    if (_liking.contains(comment.id) ||
        widget.repository.currentUserId == null) {
      return;
    }
    setState(() {
      _liking.add(comment.id);
      _error = null;
    });
    try {
      await widget.repository.toggleCommentLike(widget.post.id, comment.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update your like. Try again.');
      }
    } finally {
      if (mounted) setState(() => _liking.remove(comment.id));
    }
  }

  Future<void> _delete(CommentModel comment) async {
    try {
      await widget.repository.deleteComment(widget.post.id, comment.id);
      if (mounted && _editing?.id == comment.id) _cancelEdit();
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
                        _editing == null ? 'Comments' : 'Edit comment',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_editing != null)
                      TextButton(
                        onPressed: _sending ? null : _cancelEdit,
                        child: const Tooltip(
                          message: 'Cancel edit',
                          child: Text('Cancel'),
                        ),
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
                            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              final comment = comments[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FutureBuilder<UserModel?>(
                                            future: _authors.putIfAbsent(
                                              comment.authorId,
                                              () => widget.repository.getAuthor(
                                                comment.authorId,
                                              ),
                                            ),
                                            builder: (context, snapshot) =>
                                                AuthorIdentity(
                                                  user: snapshot.data,
                                                  avatarKey: ValueKey(
                                                    'comment_avatar_${comment.id}',
                                                  ),
                                                  nameKey: ValueKey(
                                                    'comment_author_${comment.id}',
                                                  ),
                                                  onPressed: () {
                                                    _focus.unfocus();
                                                    Navigator.pushNamed(
                                                      context,
                                                      profileRoute,
                                                      arguments:
                                                          comment.authorId,
                                                    );
                                                  },
                                                ),
                                          ),
                                        ),
                                        if (uid != null &&
                                            (uid == comment.authorId ||
                                                uid == widget.post.authorId))
                                          PopupMenuButton<String>(
                                            key: ValueKey(
                                              'comment_menu_${comment.id}',
                                            ),
                                            tooltip: 'Comment options',
                                            onSelected: (action) {
                                              if (action == 'edit') {
                                                _edit(comment);
                                              } else {
                                                _delete(comment);
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              if (uid == comment.authorId)
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('Edit comment'),
                                                ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete comment'),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        right: 12,
                                        top: 4,
                                      ),
                                      child: Text(
                                        comment.text,
                                        key: ValueKey(
                                          'comment_text_${comment.id}',
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Tooltip(
                                          message: comment.likedBy.contains(uid)
                                              ? 'Unlike comment'
                                              : 'Like comment',
                                          child: TextButton.icon(
                                            key: ValueKey(
                                              'comment_like_${comment.id}',
                                            ),
                                            onPressed:
                                                uid == null ||
                                                    _liking.contains(comment.id)
                                                ? null
                                                : () => _like(comment),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              minimumSize: const Size(48, 48),
                                            ),
                                            icon: Icon(
                                              comment.likedBy.contains(uid)
                                                  ? Icons.favorite
                                                  : Icons.favorite_outline,
                                              size: 22,
                                            ),
                                            label: Text(
                                              compactCount(
                                                comment.likedBy.length,
                                              ),
                                              key: ValueKey(
                                                'comment_count_${comment.id}',
                                              ),
                                              semanticsLabel:
                                                  '${comment.likedBy.length} likes',
                                            ),
                                          ),
                                        ),
                                        if (comment.editedAt != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            child: Text(
                                              'Edited',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: Colors.white60,
                                                  ),
                                            ),
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
                              focusNode: _focus,
                              enabled: !_sending,
                              minLines: 1,
                              maxLines: 3,
                              maxLength: 500,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Add a comment…',
                                counterText: '',
                              ),
                              onChanged: (_) => setState(() {
                                if (_editing == null) {
                                  _commentId = const Uuid().v4();
                                }
                              }),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filled(
                            tooltip: _editing == null
                                ? 'Post comment'
                                : 'Save comment',
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
                                : Icon(
                                    _editing == null
                                        ? Icons.arrow_upward
                                        : Icons.check,
                                  ),
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
