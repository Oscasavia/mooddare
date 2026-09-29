import 'weekly_dare_notification_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mooddare/core/app_routes.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/core/comment_time.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/features/dares/presentation/screens/dare_library_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/post_details_screen.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';
import 'package:mooddare/models/user_model.dart';
import '../data/notification_repository.dart';
import 'notification_settings.dart';

Future<void> openActivity(
  BuildContext context,
  NotificationRepository repository,
  ActivityNotification n,
) async {
  try {
    if (n.kind == 'weekly') {
      await repository.markRead(n.id);
      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => WeeklyDareNotificationScreen(
              weekId: n.weeklyDareId!,
              repository: repository,
            ),
          ),
        );
      }
      return;
    }
    // Resolve the current account and content, never trust a push payload URL.
    final actor = await repository.actor(n.actorId);
    if (actor == null) throw StateError('This account is no longer available.');
    if (n.kind == 'follow') {
      await repository.markRead(n.id);
      if (context.mounted) {
        await Navigator.pushNamed(context, profileRoute, arguments: n.actorId);
      }
    } else if (n.kind == 'dare') {
      if (!await repository.inviteAvailable(n)) {
        throw StateError('This dare invitation is no longer available.');
      }
      await repository.markRead(n.id);
      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const DareInboxScreen()),
        );
      }
    } else {
      final post = await repository.post(n);
      if (post == null) {
        throw StateError('This moment or comment is no longer available.');
      }
      await repository.markRead(n.id);
      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                PostDetailsScreen(post: post, openComments: n.opensComments),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message.toString()
                : 'Could not open this notification. Please try again.',
          ),
        ),
      );
    }
  }
}

class NotificationBell extends StatefulWidget {
  final NotificationRepository? repository;
  const NotificationBell({super.key, this.repository});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final _repo = widget.repository ?? NotificationRepository();
  late final _unread = _repo.unread();
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _unread,
    builder: (context, s) => IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => NotificationInbox(repository: _repo),
        ),
      ),
      icon: Badge(
        isLabelVisible: s.data == true,
        child: const Icon(Icons.notifications_none_rounded),
      ),
    ),
  );
}

class NotificationInbox extends StatefulWidget {
  final NotificationRepository? repository;
  final SocialRepository? social;
  const NotificationInbox({super.key, this.repository, this.social});
  @override
  State<NotificationInbox> createState() => _NotificationInboxState();
}

class _NotificationInboxState extends State<NotificationInbox> {
  late final _repo = widget.repository ?? NotificationRepository();
  late final _social = widget.social ?? SocialRepository();
  int _limit = 40;
  bool _unreadOnly = false, _busy = false;
  String? _opening;
  late Stream<List<ActivityNotification>> _events = _repo.watch(limit: _limit);
  late Stream<Set<String>> _blocks = _repo.uid == null
      ? Stream.value({})
      : _social.blocked();
  final _actors = <String, Future<UserModel?>>{};
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _reload() => setState(() {
    _events = _repo.watch(limit: _limit);
    _actors.clear();
  });
  Future<void> _readAll() async {
    setState(() => _busy = true);
    try {
      await _repo.markAllRead();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not mark notifications as read. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        IconButton(
          tooltip: 'Notification settings',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => NotificationSettingsScreen(repository: _repo),
            ),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: !_unreadOnly,
                onSelected: (_) => setState(() => _unreadOnly = false),
              ),
              ChoiceChip(
                label: const Text('Unread'),
                selected: _unreadOnly,
                onSelected: (_) => setState(() => _unreadOnly = true),
              ),
              IconButton(
                tooltip: 'Mark all read',
                onPressed: _busy ? null : _readAll,
                icon: const Icon(Icons.done_all_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<Set<String>>(
            stream: _blocks,
            builder: (context, blocks) => StreamBuilder<List<ActivityNotification>>(
              stream: _events,
              builder: (context, s) {
                if (s.hasError || blocks.hasError) {
                  return AppEmptyState.error(
                    title: 'Couldn’t load notifications',
                    message: 'Check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: () {
                      _blocks = _repo.uid == null
                          ? Stream.value({})
                          : _social.blocked();
                      _reload();
                    },
                  );
                }
                if (!s.hasData || !blocks.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = s.data!
                    .where(
                      (n) =>
                          !blocks.data!.contains(n.actorId) &&
                          (!_unreadOnly || !n.read),
                    )
                    .toList();
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (items.isEmpty)
                        SizedBox(
                          height: 330,
                          child: AppEmptyState(
                            illustration: const MoodWink(size: 80),
                            title: _unreadOnly
                                ? 'You’re all caught up'
                                : 'Your next connection starts here',
                            message: _unreadOnly
                                ? 'New activity will appear here.'
                                : 'Follows, likes, comments and dares will find you here.',
                          ),
                        ),
                      for (final n in items)
                        FutureBuilder<UserModel?>(
                          future: n.kind == 'weekly'
                              ? Future<UserModel?>.value(null)
                              : _actors.putIfAbsent(
                                  n.actorId,
                                  () => _repo.actor(n.actorId),
                                ),
                          builder: (context, a) {
                            final user = a.data;
                            final name = user?.username ?? 'Someone';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Material(
                                color: n.read
                                    ? Colors.transparent
                                    : Theme.of(context).colorScheme.primary
                                          .withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: _opening != null
                                      ? null
                                      : () async {
                                          setState(() => _opening = n.id);
                                          await openActivity(context, _repo, n);
                                          if (mounted) {
                                            setState(() => _opening = null);
                                          }
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (n.kind == 'weekly')
                                          const SizedBox(
                                            width: 42,
                                            height: 42,
                                            child: Center(
                                              child: MoodWink(size: 34),
                                            ),
                                          )
                                        else
                                          CircleAvatar(
                                            radius: 21,
                                            backgroundImage:
                                                user?.photoUrl?.isNotEmpty ==
                                                    true
                                                ? NetworkImage(user!.photoUrl!)
                                                : null,
                                            child:
                                                user?.photoUrl?.isNotEmpty ==
                                                    true
                                                ? null
                                                : const Icon(
                                                    Icons
                                                        .person_outline_rounded,
                                                    size: 22,
                                                  ),
                                          ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text.rich(
                                                TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: n.kind == 'weekly'
                                                          ? 'MoodDare '
                                                          : '@$name ',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    TextSpan(text: n.message),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                commentTime(
                                                  n.createdAt,
                                                  DateTime.now(),
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Colors.white54,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (_opening == n.id)
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        else
                                          Icon(
                                            switch (n.kind) {
                                              'follow' =>
                                                Icons.person_add_alt_1_rounded,
                                              'dare' => Icons.inbox_outlined,
                                              'weekly' =>
                                                Icons.calendar_today_outlined,
                                              'postLike' ||
                                              'commentLike' ||
                                              'replyLike' =>
                                                Icons.favorite_outline_rounded,
                                              _ =>
                                                Icons
                                                    .chat_bubble_outline_rounded,
                                            },
                                            size: 19,
                                            color: n.read
                                                ? Colors.white38
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      if (s.data!.length >= _limit)
                        TextButton(
                          onPressed: () {
                            _limit += 40;
                            _reload();
                          },
                          child: const Text('Load more'),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}
