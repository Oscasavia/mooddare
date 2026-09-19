// lib/features/profile/presentation/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mooddare/models/user_model.dart';
import 'package:mooddare/features/user/data/repositories/user_repository.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/profile/presentation/widgets/stats_and_badges.dart';
import 'package:mooddare/features/profile/presentation/widgets/my_dares_grid.dart';
import 'package:mooddare/features/profile/presentation/widgets/follow_stat.dart';
import 'package:mooddare/features/profile/presentation/widgets/sign_in_prompt_card.dart';
import 'package:mooddare/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:mooddare/features/profile/presentation/screens/settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool isGuest;
  final String? userId;
  final VoidCallback? onProfileUpdated; // Added parameter

  const ProfileScreen({
    super.key,
    required this.isGuest,
    this.userId,
    this.onProfileUpdated, // Added to constructor
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UserRepository _userRepository = UserRepository();
  final PostRepository _postRepository = PostRepository();
  late Future<UserProfileData> _profileDataFuture;
  late String _displayUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _displayUserId =
        widget.userId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    _profileDataFuture = _loadProfileData();
  }

  Future<UserProfileData> _loadProfileData() async {
    final user = await _userRepository.getUserModel(_displayUserId);
    final stats = await _postRepository.getUserStats(_displayUserId);
    return UserProfileData(user: user, stats: stats);
  }

  void _refreshProfileData() {
    setState(() {
      _profileDataFuture = _loadProfileData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userId == null ? 'My Profile' : ''),
        actions: widget.userId == null
            ? [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit Profile',
                  onPressed: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const EditProfileScreen(),
                      ),
                    );
                    if (mounted && result == true) {
                      _refreshProfileData();
                      widget.onProfileUpdated
                          ?.call(); // Call the callback here!
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ]
            : [],
        backgroundColor: const Color(0xFF0A0A0D),
        elevation: 0,
      ),
      body: FutureBuilder<UserProfileData>(
        future: _profileDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: _refreshProfileData,
                child: const Text('Could not load your profile. Tap to retry.'),
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
                SliverToBoxAdapter(child: _buildProfileHeader(user, stats)),
              ];
            },
            body: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  indicator: UnderlineTabIndicator(
                    borderSide: BorderSide(
                      width: 3.0,
                      color: Theme.of(context).primaryColor,
                    ),
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
                      MyDaresGrid(userId: _displayUserId),
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
        CircleAvatar(
          radius: 50,
          backgroundColor: Colors.white10, // Added to match edit screen style
          backgroundImage: user.photoUrl != null
              ? NetworkImage(user.photoUrl!)
              : null,
          child: user.photoUrl == null
              ? const Icon(
                  Icons.person_outline,
                  size: 50,
                  color: Colors.white54,
                )
              : null,
        ),
        const SizedBox(height: 10),
        Text(
          '@${user.username ?? 'member'}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FollowStat(
              count: '${stats['daresCompleted'] ?? 0}',
              label: 'Moments',
            ),
            const SizedBox(width: 40),
            FollowStat(count: '${stats['totalLikes'] ?? 0}', label: 'Likes'),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.isGuest && widget.userId == null) const SignInPromptCard(),
      ],
    );
  }

  Widget _buildTab(String text, IconData icon) {
    return Tab(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(icon), const SizedBox(width: 8), Text(text)],
        ),
      ),
    );
  }
}

// Helper class to hold combined profile data
class UserProfileData {
  final UserModel? user;
  final Map<String, int> stats;
  UserProfileData({required this.user, required this.stats});
}
