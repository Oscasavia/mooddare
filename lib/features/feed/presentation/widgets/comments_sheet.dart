import 'package:mooddare/core/widgets/stable_popup_menu.dart';
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
  final _deleting = <String>{};
  CommentModel? _editing;
  CommentModel? _replying;
  final _expanded = <String>{};
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
    if (_sending ||
        _deleting.contains(_editing?.id) ||
        text.isEmpty ||
        text.length > 500) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final editing = _editing;
      if (editing == null && _replying != null) {
        await widget.repository.addReply(
          widget.post.id,
          _replying!.id,
          _commentId,
          text,
        );
        _expanded.add(_replying!.id);
        _replying = null;
      } else if (editing == null) {
        await widget.repository.addComment(widget.post.id, _commentId, text);
      } else {
        if (editing.parentId == null) {
          await widget.repository.editComment(widget.post.id, editing.id, text);
        } else {
          await widget.repository.editReply(widget.post.id, editing.id, text);
        }
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
    if (_sending ||
        _deleting.contains(comment.id) ||
        comment.authorId != widget.repository.currentUserId) {
      return;
    }
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
        _deleting.contains(comment.id) ||
        widget.repository.currentUserId == null) {
      return;
    }
    setState(() {
      _liking.add(comment.id);
      _error = null;
    });
    try {
      if (comment.parentId == null) {
        await widget.repository.toggleCommentLike(widget.post.id, comment.id);
      } else {
        await widget.repository.toggleReplyLike(widget.post.id, comment.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update your like. Try again.');
      }
    } finally {
      if (mounted) setState(() => _liking.remove(comment.id));
    }
  }

  Future<void> _delete(CommentModel comment) async {
    if (_sending || _deleting.contains(comment.id)) return;
    setState(() {
      _deleting.add(comment.id);
      _error = null;
    });
    try {
      if (comment.parentId == null) {
        await widget.repository.deleteComment(widget.post.id, comment.id);
      } else {
        await widget.repository.deleteReply(widget.post.id, comment.id);
      }
      if (mounted && _replying?.id == comment.id) {
        setState(() => _replying = null);
      }
      if (mounted && _editing?.id == comment.id) _cancelEdit();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not delete this comment. Try again.');
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(comment.id));
    }
  }

  Widget _comment(CommentModel comment, {String? replyTo}) {
    final uid = widget.repository.currentUserId;
    return Padding(
      key: ValueKey(comment.id),
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
                    () => widget.repository.getAuthor(comment.authorId),
                  ),
                  builder: (context, snapshot) => AuthorIdentity(
                    user: snapshot.data,
                    avatarRadius: 14,
                    avatarKey: ValueKey('comment_avatar_${comment.id}'),
                    nameKey: ValueKey('comment_author_${comment.id}'),
                    onPressed: () {
                      _focus.unfocus();
                      Navigator.pushNamed(
                        context,
                        profileRoute,
                        arguments: comment.authorId,
                      );
                    },
                  ),
                ),
              ),
              if (uid != null &&
                  (uid == comment.authorId || uid == widget.post.authorId))
                StablePopupMenu<String>(
                  enabled: !_sending && !_deleting.contains(comment.id),
                  key: ValueKey('comment_menu_${comment.id}'),
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
              left: AuthorIdentity.textInset,
              right: 12,
              top: 4,
            ),
            child: replyTo == null
                ? Text(
                    comment.text,
                    key: ValueKey('comment_text_${comment.id}'),
                  )
                : FutureBuilder<UserModel?>(
                    future: _authors.putIfAbsent(
                      replyTo,
                      () => widget.repository.getAuthor(replyTo),
                    ),
                    builder: (_, snapshot) {
                      final username = snapshot.data?.username;
                      final recipient = username != null && username.isNotEmpty
                          ? username
                          : 'member';
                      return Text(
                        '@$recipient ${comment.text}',
                        key: ValueKey('comment_text_${comment.id}'),
                      );
                    },
                  ),
          ),
          Row(
            children: [
              Tooltip(
                message: comment.likedBy.contains(uid)
                    ? 'Unlike comment'
                    : 'Like comment',
                child: TextButton.icon(
                  key: ValueKey('comment_like_${comment.id}'),
                  onPressed:
                      uid == null ||
                          _deleting.contains(comment.id) ||
                          _liking.contains(comment.id)
                      ? null
                      : () => _like(comment),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(48, 48),
                  ),
                  icon: Icon(
                    comment.likedBy.contains(uid)
                        ? Icons.favorite
                        : Icons.favorite_outline,
                    size: 22,
                  ),
                  label: Text(
                    compactCount(comment.likedBy.length),
                    key: ValueKey('comment_count_${comment.id}'),
                    semanticsLabel: '${comment.likedBy.length} likes',
                  ),
                ),
              ),
              if (comment.parentId == null && !comment.deleting)
                TextButton(
                  onPressed: uid == null || _sending
                      ? null
                      : () {
                          if (_editing != null) _cancelEdit();
                          setState(() {
                            _replying = comment;
                            _error = null;
                          });
                          _focus.requestFocus();
                        },
                  child: const Text('Reply'),
                ),
              if (comment.editedAt != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'Edited',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: Colors.white60),
                  ),
                ),
            ],
          ),
          if (comment.parentId == null && !comment.deleting)
            _ReplyThread(
              key: ValueKey('thread_${comment.id}'),
              repository: widget.repository,
              postId: widget.post.id,
              parentId: comment.id,
              blocked: _blocked,
              expanded: _expanded.contains(comment.id),
              onToggle: () => setState(() {
                if (!_expanded.remove(comment.id)) _expanded.add(comment.id);
              }),
              buildComment: (reply) =>
                  _comment(reply, replyTo: comment.authorId),
            ),
          if (comment.deleting)
            const Text(
              'Thread deletion interrupted. Use Delete comment to retry.',
              style: TextStyle(color: Colors.white54),
            ),
        ],
      ),
    );
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
                              return _comment(comment);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_replying != null && _editing == null)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FutureBuilder<UserModel?>(
                          future: _authors.putIfAbsent(
                            _replying!.authorId,
                            () => widget.repository.getAuthor(
                              _replying!.authorId,
                            ),
                          ),
                          builder: (_, snapshot) => Text(
                            'Replying to @${snapshot.data?.username ?? 'member'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel reply',
                        onPressed: _sending
                            ? null
                            : () => setState(() => _replying = null),
                        icon: const Icon(Icons.close, size: 18),
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
                            onPressed:
                                _sending ||
                                    _deleting.contains(_editing?.id) ||
                                    _text.text.trim().isEmpty
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

class _ReplyThread extends StatefulWidget {
  final PostRepository repository;
  final String postId, parentId;
  final Set<String> blocked;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget Function(CommentModel) buildComment;
  const _ReplyThread({
    super.key,
    required this.repository,
    required this.postId,
    required this.parentId,
    required this.blocked,
    required this.expanded,
    required this.onToggle,
    required this.buildComment,
  });
  @override
  State<_ReplyThread> createState() => _ReplyThreadState();
}

class _ReplyThreadState extends State<_ReplyThread> {
  int _visible = 5;
  late Stream<List<CommentModel>> _stream = widget.repository.getReplies(
    widget.postId,
    widget.parentId,
  );
  @override
  Widget build(BuildContext context) => StreamBuilder<List<CommentModel>>(
    stream: _stream,
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(() {
            _stream = widget.repository.getReplies(
              widget.postId,
              widget.parentId,
            );
          }),
          child: const Text('Could not load replies. Retry'),
        );
      }
      if (!snapshot.hasData) return const SizedBox.shrink();
      final replies = snapshot.data!
          .where((r) => !widget.blocked.contains(r.authorId))
          .toList();
      if (replies.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: AuthorIdentity.textInset),
            child: TextButton(
              key: ValueKey('replies_${widget.parentId}'),
              onPressed: widget.onToggle,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.expanded ? 'Hide replies' : 'View replies',
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    widget.expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...replies.take(_visible).map(widget.buildComment),
                  if (replies.length > _visible)
                    TextButton(
                      onPressed: () => setState(() => _visible += 5),
                      child: Text(
                        'View ${replies.length - _visible} more replies',
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
