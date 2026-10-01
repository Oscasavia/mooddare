import '../../../links/moment_links.dart';
import '../../../links/shared_moment_screen.dart';
import 'dart:async';
import 'package:mooddare/features/notifications/data/push_service.dart';
import 'package:mooddare/features/notifications/data/notification_repository.dart';
import 'package:mooddare/features/notifications/presentation/notification_inbox.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/features/dares/presentation/screens/dares_screen.dart';
import 'package:mooddare/features/feed/presentation/screens/feed_screen.dart';
import 'package:mooddare/features/profile/presentation/screens/profile_screen.dart';
import '../widgets/profile_navigation_icon.dart';

class MainScreen extends StatefulWidget {
  final bool isGuest;
  final String? profilePhotoUrl;
  const MainScreen({super.key, this.isGuest = false, this.profilePhotoUrl});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _index = 1;
  final _push = PushService.instance;
  bool _openingNotification = false;
  bool _openingLink = false;
  final _links = MomentLinks.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _links.pending.addListener(_openLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLink());
    _push?.pending.addListener(_openPush);
    _push?.foreground.addListener(_foregroundPush);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPush());
  }

  Future<void> _openLink() async {
    final id = _links.pending.value;
    if (!mounted || widget.isGuest || id == null || _openingLink) return;
    _openingLink = true;
    _links.pending.value = null;
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => SharedMomentScreen(postId: id)));
    } finally {
      _openingLink = false;
      if (mounted && _links.pending.value != null) unawaited(_openLink());
    }
  }

  void _foregroundPush() {
    final data = _push?.foreground.value;
    if (!mounted || data == null) return;
    _push?.foreground.value = null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            MoodWink(size: 24),
            SizedBox(width: 12),
            Expanded(child: Text('New activity on MoodDare')),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            _push?.pending.value = data;
          },
        ),
      ),
    );
  }

  Future<void> _openPush() async {
    final data = _push?.pending.value;
    if (!mounted || data == null || _openingNotification) return;
    final repo = NotificationRepository();
    _push?.pending.value = null;
    if (repo.uid != data['recipientId']) return;
    _openingNotification = true;
    try {
      final notification = await repo.get(data['notificationId']!);
      if (mounted) {
        if (notification != null) {
          await openActivity(context, repo, notification);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This notification is no longer available.'),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open notification. Check your connection.',
            ),
          ),
        );
      }
    } finally {
      _openingNotification = false;
      if (mounted && _push?.pending.value != null) unawaited(_openPush());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _push != null) {
      unawaited(_push.refresh().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _links.pending.removeListener(_openLink);
    _push?.pending.removeListener(_openPush);
    _push?.foreground.removeListener(_foregroundPush);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: switch (_index) {
      0 => const FeedScreen(),
      1 => const DaresScreen(),
      _ => ProfileScreen(isGuest: widget.isGuest),
    },
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.dynamic_feed_outlined),
          selectedIcon: Icon(Icons.dynamic_feed),
          label: 'Moments',
        ),
        const NavigationDestination(
          icon: MoodWink(size: 26, wink: 0, color: Colors.white60),
          selectedIcon: MoodWink(size: 26),
          label: 'Discover',
        ),
        NavigationDestination(
          icon: ProfileNavigationIcon(photoUrl: widget.profilePhotoUrl),
          selectedIcon: ProfileNavigationIcon(
            photoUrl: widget.profilePhotoUrl,
            selected: true,
          ),
          label: 'You',
        ),
      ],
    ),
  );
}
