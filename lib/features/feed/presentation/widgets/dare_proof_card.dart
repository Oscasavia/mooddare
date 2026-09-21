import 'package:mooddare/core/widgets/stable_popup_menu.dart';
import 'package:mooddare/core/widgets/share_icon.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mooddare/core/navigation.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/models/user_model.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/core/compact_count.dart';
import '../screens/post_details_screen.dart';
import '../video_sound.dart';
import 'comments_sheet.dart';
import 'author_identity.dart';
import 'post_likes_sheet.dart';

class DareProofCard extends StatefulWidget {
  final PostModel post;
  final bool isFullScreen, isActive;
  final VoidCallback? onHidden;
  final PostRepository? repository;
  const DareProofCard({
    super.key,
    required this.post,
    this.isFullScreen = false,
    this.isActive = false,
    this.onHidden,
    this.repository,
  });
  @override
  State<DareProofCard> createState() => _DareProofCardState();
}

class _DareProofCardState extends State<DareProofCard>
    with WidgetsBindingObserver, RouteAware {
  late final PostRepository _repository;
  late Future<UserModel?> _author;
  late Future<int> _commentCount;
  VideoPlayerController? _video;
  Timer? _timer;
  PageRoute<dynamic>? _route;
  bool _liked = false,
      _liking = false,
      _videoFailed = false,
      _covered = false,
      _foreground = true,
      _opening = false,
      _pausedByUser = false,
      _sharing = false,
      _commenting = false,
      _viewingLikes = false;
  int _likes = 0;
  bool _downloading = false;
  String? get _uid => _repository.currentUserId;
  bool get _shouldPlay =>
      widget.isActive &&
      !_covered &&
      _foreground &&
      !_opening &&
      !_sharing &&
      !_commenting &&
      !_viewingLikes &&
      !_pausedByUser;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    videoMuted.addListener(_soundChanged);
    _repository = widget.repository ?? PostRepository();
    _author = _repository.getAuthor(widget.post.authorId);
    _commentCount = _repository.getCommentCount(widget.post.id);
    _liked = widget.post.likedBy.contains(_uid);
    _likes = widget.post.likedBy.length;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
        if (widget.isActive && !_covered && _foreground) _refreshCommentCount();
      }
    });
    if (widget.post.mediaType == 'video') _loadVideo();
  }

  Future<void> _loadVideo() async {
    final video = VideoPlayerController.networkUrl(
      Uri.parse(widget.post.mediaUrl),
    );
    _video = video;
    try {
      await video.initialize();
      if (!mounted) return;
      await video.setVolume(videoMuted.value ? 0 : 1);
      await video.setLooping(true);
      if (_shouldPlay) await video.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  void _refreshCommentCount() {
    if (mounted) {
      setState(() {
        _commentCount = _repository.getCommentCount(widget.post.id);
      });
    }
  }

  void _openAuthor() => Navigator.pushNamed(
    context,
    profileRoute,
    arguments: widget.post.authorId,
  );

  void _soundChanged() {
    _video?.setVolume(videoMuted.value ? 0 : 1);
  }

  Future<void> _comments() async {
    if (_commenting) return;
    _commenting = true;
    _syncPlayback();
    try {
      await showComments(context, widget.post, _repository);
    } finally {
      _commenting = false;
      if (mounted) {
        _syncPlayback();
        _refreshCommentCount();
      }
    }
  }

  Future<void> _showLikes() async {
    if (_viewingLikes) return;
    _viewingLikes = true;
    _syncPlayback();
    try {
      await showPostLikes(context, widget.post.id, _repository);
    } finally {
      _viewingLikes = false;
      if (mounted) _syncPlayback();
    }
  }

  void _syncPlayback() {
    if (!(_video?.value.isInitialized ?? false)) return;
    if (_shouldPlay) {
      _video!.play();
    } else {
      _video!.pause();
    }
  }

  @override
  void didPushNext() {
    _covered = true;
    _syncPlayback();
  }

  @override
  void didPop() {
    _covered = true;
    _syncPlayback();
  }

  @override
  void didPopNext() {
    _covered = false;
    _syncPlayback();
    _refreshCommentCount();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant DareProofCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_liking) {
      _liked = widget.post.likedBy.contains(_uid);
      _likes = widget.post.likedBy.length;
    }
    if (widget.isActive != oldWidget.isActive) _syncPlayback();
  }

  @override
  void dispose() {
    videoMuted.removeListener(_soundChanged);
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _timer?.cancel();
    unawaited(_video?.dispose());
    super.dispose();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openMoment() async {
    if (widget.isFullScreen) {
      final video = _video;
      if (video != null && video.value.isInitialized) {
        _pausedByUser = video.value.isPlaying;
        _syncPlayback();
      }
      return;
    }
    if (_opening) return;
    _opening = true;
    try {
      // Stop the feed's audio before the detail viewer starts its player.
      await _video?.pause();
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailsScreen(
            post: widget.post,
            repository: _repository,
            onHidden: widget.onHidden,
          ),
        ),
      );
    } finally {
      _opening = false;
      if (mounted) _syncPlayback();
    }
  }

  void _hide() {
    widget.onHidden?.call();
    if (widget.isFullScreen && mounted) Navigator.pop(context);
  }

  Future<void> _like() async {
    final uid = _uid;
    if (uid == null || _liking) return;
    final wasLiked = _liked;
    setState(() {
      _liking = true;
      _liked = !wasLiked;
      _likes += wasLiked ? -1 : 1;
    });
    try {
      await _repository.toggleLike(widget.post.id, uid);
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = wasLiked;
          _likes += wasLiked ? 1 : -1;
        });
      }
      _message('Could not update your like. Try again.');
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _action(String action) async {
    if (!mounted) return;
    if (action == 'download') {
      if (_downloading) return;
      setState(() => _downloading = true);
      try {
        await _repository.downloadPost(widget.post);
        _message('Saved to your device.');
      } catch (_) {
        _message(
          'Could not save this moment. Check your connection and photo library permission, then try again.',
        );
      } finally {
        if (mounted) setState(() => _downloading = false);
      }
      return;
    }
    if (action == 'hide') {
      _hide();
      return;
    }
    try {
      if (action == 'block') {
        await _repository.blockAuthor(widget.post.authorId);
        _message('Account blocked. Manage blocked accounts in Settings.');
        _hide();
        return;
      }
      if (action == 'report') {
        await _repository.reportPost(widget.post.id);
        _message('Report submitted.');
      }
      if (action == 'delete' && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this moment?'),
            content: const Text(
              'This removes the post and its uploaded photo or video.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep it'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await _repository.deletePost(widget.post.id, widget.post.mediaUrl);
        if (mounted && widget.isFullScreen) Navigator.pop(context);
      }
    } catch (_) {
      _message('Could not complete that action. Please try again.');
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    _sharing = true;
    _syncPlayback();
    final box = context.findRenderObject() as RenderBox?;
    try {
      await Share.share(
        '${widget.post.dareText}\n${widget.post.mediaUrl}\n#MoodDare',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      _message('Could not open sharing. Please try again.');
    } finally {
      _sharing = false;
      if (mounted) _syncPlayback();
    }
  }

  Widget _media() {
    if (widget.post.mediaType != 'video') {
      return Image.network(
        widget.post.mediaUrl,
        fit: widget.isFullScreen ? BoxFit.contain : BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined, size: 44)),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (_videoFailed) {
      return const Center(child: Text('This video could not be loaded.'));
    }
    if (!(_video?.value.isInitialized ?? false)) {
      return const Center(child: CircularProgressIndicator());
    }
    return FittedBox(
      fit: widget.isFullScreen ? BoxFit.contain : BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: _video!.value.size.width,
        height: _video!.value.size.height,
        child: VideoPlayer(_video!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.post.expiresAt.toDate().difference(DateTime.now());
    return Padding(
      padding: EdgeInsets.all(widget.isFullScreen ? 0 : 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.isFullScreen ? 0 : 28),
        child: GestureDetector(
          key: ValueKey('moment_surface_${widget.post.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: _openMoment,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Resolve single and double media taps in the same detector.
                  onTap: _openMoment,
                  onDoubleTap: () {
                    if (!_liked) _like();
                  },
                  child: _media(),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [.4, 1],
                        colors: [Colors.transparent, Color(0xE6000000)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: widget.isFullScreen ? 0 : 8,
                  left: widget.isFullScreen ? 0 : null,
                  right: widget.isFullScreen ? 0 : 8,
                  child: SafeArea(
                    top: widget.isFullScreen,
                    bottom: false,
                    child: SizedBox(
                      height: widget.isFullScreen ? kToolbarHeight : 48,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.isFullScreen) ...[
                            const BackButton(color: Colors.white),
                            const Spacer(),
                          ],
                          if (widget.post.mediaType == 'video')
                            ValueListenableBuilder<bool>(
                              valueListenable: videoMuted,
                              builder: (_, muted, _) => IconButton(
                                tooltip: muted ? 'Unmute video' : 'Mute video',
                                onPressed: () => videoMuted.value = !muted,
                                icon: Icon(
                                  muted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          StablePopupMenu<String>(
                            tooltip: 'Moment options',
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                              size: 22,
                            ),
                            onSelected: _action,
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'download',
                                enabled: !_downloading,
                                child: Text(
                                  _downloading ? 'Saving…' : 'Download moment',
                                ),
                              ),
                              if (widget.post.authorId == _uid)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete moment'),
                                ),
                              if (widget.post.authorId != _uid) ...[
                                const PopupMenuItem(
                                  value: 'report',
                                  child: Text('Report moment'),
                                ),
                                const PopupMenuItem(
                                  value: 'block',
                                  child: Text('Block account'),
                                ),
                              ],
                              if (widget.onHidden != null)
                                const PopupMenuItem(
                                  value: 'hide',
                                  child: Text('Hide for now'),
                                ),
                            ],
                          ),
                          if (widget.isFullScreen) const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: widget.isFullScreen
                      ? MediaQuery.paddingOf(context).bottom + 16
                      : 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.post.moodName?.trim().isNotEmpty ?? false) ...[
                        Text(
                          widget.post.moodName!,
                          key: const ValueKey('moment_mood'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        widget.post.dareText,
                        style: const TextStyle(
                          fontSize: 22,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<UserModel?>(
                        future: _author,
                        builder: (context, snapshot) {
                          final author = snapshot.data;
                          return AuthorIdentity(
                            user: author,
                            onPressed: _openAuthor,
                            avatarKey: const ValueKey('moment_author_avatar'),
                            nameKey: const ValueKey('moment_author_name'),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: _liked ? 'Unlike' : 'Like',
                                onPressed: _liking ? null : _like,
                                onLongPress: _showLikes,
                                icon: Icon(
                                  _liked
                                      ? Icons.favorite
                                      : Icons.favorite_outline,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              Text(
                                compactCount(_likes),
                                semanticsLabel: '$_likes likes',
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Comments',
                                onPressed: _comments,
                                icon: const Icon(
                                  Icons.chat_bubble_outline,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              FutureBuilder<int>(
                                future: _commentCount,
                                builder: (_, snapshot) => Text(
                                  snapshot.hasData
                                      ? compactCount(snapshot.data!)
                                      : '—',
                                  key: const ValueKey('moment_comment_count'),
                                  semanticsLabel: snapshot.hasData
                                      ? '${snapshot.data} comments'
                                      : 'Comment count unavailable',
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Share moment',
                            onPressed: _share,
                            icon: const ShareIcon(
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        remaining.isNegative
                            ? 'Archived moment'
                            : remaining.inHours > 0
                            ? '${remaining.inHours}h left in the feed'
                            : '${remaining.inMinutes}m left in the feed',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_video != null)
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _video!,
                    builder: (_, value, _) => IgnorePointer(
                      child: value.isInitialized && !value.isPlaying
                          ? const Center(
                              child: Icon(
                                Icons.play_circle_outline,
                                size: 60,
                                color: Colors.white70,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
