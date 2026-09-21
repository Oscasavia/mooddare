import 'dart:async';
import 'package:mooddare/core/widgets/stable_popup_menu.dart';
import '../widgets/report_user_sheet.dart';
import '../../data/social_repository.dart';
import '../widgets/profile_connections.dart';
import '../widgets/follow_button.dart';
// lib/features/profile/presentation/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:mooddare/models/user_model.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/profile/presentation/widgets/stats_and_badges.dart';
import 'package:mooddare/features/profile/presentation/widgets/my_dares_grid.dart';
import 'package:mooddare/features/profile/presentation/widgets/sign_in_prompt_card.dart';
import 'package:mooddare/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:mooddare/features/profile/presentation/screens/settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool isGuest;
  final String? userId;
  final VoidCallback? onProfileUpdated;
  final UserRepository? repository;
  final PostRepository? postRepository;
  final SocialRepository? socialRepository;

  const ProfileScreen({
    super.key,
    required this.isGuest,
    this.userId,
    this.onProfileUpdated,
    this.repository,
    this.postRepository,
    this.socialRepository,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final _userRepository = widget.repository ?? UserRepository();
  late final _postRepository = widget.postRepository ?? PostRepository();
  late final _social = widget.socialRepository ?? SocialRepository();
  bool get _self => _displayUserId == _userRepository.currentUserId;
  late Stream<UserProfileData> _profileData;
  late String _displayUserId;
  bool _blocked = false, _blocking = false;
  StreamSubscription<Set<String>>? _blocks;
  bool get _canManage =>
      !_self &&
      !widget.isGuest &&
      _displayUserId.isNotEmpty &&
      _userRepository.currentUserId != null;

  Future<void> _reportUser() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) =>
          ReportUserSheet(userId: _displayUserId, repository: _social),
    );
    if (mounted && sent == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Thank you for letting us know.'),
        ),
      );
    }
  }

  Future<void> _blockUser() async {
    if (_blocking || _blocked) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block this account?'),
        content: const Text(
          'You will unfollow each other. You can unblock this account in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _blocking = true);
    try {
      await _social.block(_displayUserId);
      if (mounted) setState(() => _blocked = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not block this account. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _blocking = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _displayUserId = widget.userId ?? _userRepository.currentUserId ?? '';
    _profileData = _loadProfileData();
    if (_canManage) {
      _blocks = _social.blocked().listen(
        (ids) {
          if (mounted) setState(() => _blocked = ids.contains(_displayUserId));
        },
        onError: (Object _) {
          // Keep the last known state; block writes still surface their errors.
        },
      );
    }
  }

  Stream<UserProfileData> _loadProfileData() {
    Future<Map<String, int>>? stats;
    return _userRepository.watchUserModel(_displayUserId).asyncMap((
      user,
    ) async {
      stats ??= _postRepository.getUserStats(_displayUserId);
      return UserProfileData(user: user, stats: await stats!);
    });
  }

  void _refreshProfileData() {
    setState(() {
      _profileData = _loadProfileData();
    });
  }

  @override
  void dispose() {
    _blocks?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_self ? 'My profile' : 'Profile'),
        actions: _self
            ? [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit Profile',
                  onPressed: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(
                          repository: _userRepository,
                          userId: _displayUserId,
                        ),
                      ),
                    );
                    if (mounted && result == true) {
                      widget.onProfileUpdated?.call();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                    if (mounted) {
                      _refreshProfileData();
                      widget.onProfileUpdated?.call();
                    }
                  },
                ),
              ]
            : _canManage
            ? [
                StablePopupMenu<String>(
                  tooltip: 'Profile options',
                  enabled: !_blocking,
                  onSelected: (action) {
                    if (action == 'report') _reportUser();
                    if (action == 'block') _blockUser();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Report user'),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      enabled: !_blocked,
                      child: Text(_blocked ? 'Blocked' : 'Block user'),
                    ),
                  ],
                ),
              ]
            : [],
        backgroundColor: const Color(0xFF0A0A0D),
        elevation: 0,
      ),
      body: _blocked
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You blocked this account. You can unblock it in Settings.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : StreamBuilder<UserProfileData>(
              stream: _profileData,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: _refreshProfileData,
                      child: const Text(
                        'Could not load your profile. Tap to retry.',
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data?.user == null) {
                  return const Center(child: Text('User not found.'));
                }
                final user = snapshot.data!.user!;
                final stats = snapshot.data!.stats;

                return NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverToBoxAdapter(
                        child: _buildProfileHeader(user, stats),
                      ),
                    ];
                  },
                  body: Column(
                    children: [
                      TabBar(
                        splashFactory: NoSplash.splashFactory,
                        overlayColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.pressed)
                              ? Colors.transparent
                              : null,
                        ),
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        indicator: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        tabs: [
                          _buildTab("Dares", Icons.grid_on_outlined),
                          _buildTab("Stats", Icons.bar_chart_outlined),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            MyDaresGrid(
                              userId: _displayUserId,
                              repository: _postRepository,
                            ),
                            StatsAndBadges(
                              daresCompleted: stats['daresCompleted'] ?? 0,
                              totalLikes: stats['totalLikes'] ?? 0,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildProfileHeader(UserModel user, Map<String, int> stats) {
    return Column(
      children: [
        const SizedBox(height: 16),
        GestureDetector(
          key: const ValueKey('profile_photo'),
          onTap: user.photoUrl?.isNotEmpty != true
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(
                        title: Text('@${user.username ?? 'member'}'),
                      ),
                      body: Center(
                        child: InteractiveViewer(
                          minScale: .5,
                          maxScale: 5,
                          child: Image.network(
                            user.photoUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Text('This picture is unavailable.'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.white10,
            foregroundImage: user.photoUrl?.isNotEmpty == true
                ? NetworkImage(user.photoUrl!)
                : null,
            onForegroundImageError: user.photoUrl?.isNotEmpty == true
                ? (_, _) {}
                : null,
            child: const Icon(
              Icons.person_outline,
              size: 50,
              color: Colors.white54,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (user.name?.trim().isNotEmpty ?? false) ...[
          Text(
            user.name!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          '@${user.username ?? 'member'}',
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
        if (user.bio?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(
              user.bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ProfileConnections(
            userId: user.id,
            moments: stats['daresCompleted'] ?? 0,
            repository: _social,
          ),
        ),
        if (!_self)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FollowButton(userId: user.id, repository: _social),
          ),
        const SizedBox(height: 16),
        if (widget.isGuest && widget.userId == null) const SignInPromptCard(),
      ],
    );
  }

  Widget _buildTab(String text, IconData icon) => Tab(text: text);
}

// Helper class to hold combined profile data
class UserProfileData {
  final UserModel? user;
  final Map<String, int> stats;
  UserProfileData({required this.user, required this.stats});
}
