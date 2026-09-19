import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/features/main/presentation/screens/main_screen.dart';
import 'screens/username_screen.dart';
import 'screens/welcome_screen.dart';

class AuthGate extends StatefulWidget {
  final FirebaseAuth? auth;
  final Widget Function(BuildContext, User)? signedInBuilder;
  const AuthGate({super.key, this.auth, this.signedInBuilder});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final _firebaseAuth = widget.auth ?? FirebaseAuth.instance;
  late final _auth = _firebaseAuth.userChanges();
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _auth,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      if (user == null) return const WelcomeScreen();
      if (user.isAnonymous) {
        return _EndGuestSession(auth: _firebaseAuth);
      }
      if (widget.signedInBuilder != null) {
        return widget.signedInBuilder!(context, user);
      }
      return _ProfileGate(key: ValueKey(user.uid), user: user);
    },
  );
}

/// Clear persisted guest credentials before allowing a new account sign-in.
/// A failed sign-out must never expose the old guest profile or feed.
class _EndGuestSession extends StatefulWidget {
  final FirebaseAuth auth;
  const _EndGuestSession({required this.auth});

  @override
  State<_EndGuestSession> createState() => _EndGuestSessionState();
}

class _EndGuestSessionState extends State<_EndGuestSession> {
  late Future<void> _signOut;

  @override
  void initState() {
    super.initState();
    _signOut = _clearGuest();
  }

  Future<void> _clearGuest() async {
    if (widget.auth.currentUser?.isAnonymous == true) {
      await widget.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _signOut,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: AppEmptyState(
            icon: Icons.login_rounded,
            title: 'Please sign in to continue',
            message: 'Guest access has ended. Try again to finish signing out.',
            actionLabel: 'Retry',
            onAction: () => setState(() {
              _signOut = _clearGuest();
            }),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.done) {
        return const WelcomeScreen();
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
            return const UsernameScreen(isGuest: false);
          }
          return MainScreen(
            isGuest: false,
            profilePhotoUrl: snapshot.data!.data()?['photoUrl'] as String?,
          );
        },
      );
}
