import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/features/main/presentation/screens/main_screen.dart';
import 'screens/username_screen.dart';
import 'screens/welcome_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final _auth = FirebaseAuth.instance.userChanges();
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _auth,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      if (user == null) return const WelcomeScreen();
      return _ProfileGate(key: ValueKey(user.uid), user: user);
    },
  );
}

class _ProfileGate extends StatefulWidget {
  final User user;
  const _ProfileGate({super.key, required this.user});
  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _profile;
  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _profile = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profile,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: AppEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load your profile',
                message: 'Check your connection and try again.',
                actionLabel: 'Retry',
                onAction: () => setState(_subscribe),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final username = snapshot.data!.data()?['username'] as String?;
          if (username == null || username.isEmpty) {
            return UsernameScreen(isGuest: widget.user.isAnonymous);
          }
          return MainScreen(isGuest: widget.user.isAnonymous);
        },
      );
}
