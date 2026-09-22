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

class _MainScreenState extends State<MainScreen> {
  int _index = 1;
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
