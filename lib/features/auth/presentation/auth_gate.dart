import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mooddare/core/widgets/app_empty_state.dart';
import 'package:mooddare/features/main/presentation/screens/main_screen.dart';
import 'screens/username_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import '../data/welcome_history.dart';

class AuthGate extends StatefulWidget {
  final FirebaseAuth? auth;
  final Widget Function(BuildContext, User)? signedInBuilder;
  final WelcomeHistory? welcomeHistory;
  final WidgetBuilder? returningBuilder;
  final bool showWelcome;
  const AuthGate({
    super.key,
    this.auth,
    this.signedInBuilder,
    this.welcomeHistory,
    this.returningBuilder,
    this.showWelcome = false,
  });
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final _firebaseAuth = widget.auth ?? FirebaseAuth.instance;
  late Stream<User?> _auth = _firebaseAuth.userChanges();
  late final _history = widget.welcomeHistory ?? WelcomeHistory.instance;
  bool _hadMember = false;
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _auth,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return Scaffold(
          body: AppEmptyState.error(
            title: 'Could not restore your session',
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: () => setState(() => _auth = _firebaseAuth.userChanges()),
          ),
        );
      }
      final user = snapshot.data;
      if (user == null) {
        return _SignedOutEntry(
          history: _history,
          returning: _hadMember,
          forceWelcome: widget.showWelcome && !_hadMember,
          returningBuilder: widget.returningBuilder,
        );
      }
      if (user.isAnonymous) {
        return _EndGuestSession(auth: _firebaseAuth);
      }
      if (!_hadMember) {
        _hadMember = true;
        // Remember existing installs too, without delaying session restoration.
        _history.rememberMember().catchError((Object _) {});
      }
      if (widget.signedInBuilder != null) {
        return widget.signedInBuilder!(context, user);
      }
      return _ProfileGate(key: ValueKey(user.uid), user: user);
    },
  );
}

class _SignedOutEntry extends StatefulWidget {
  final WelcomeHistory history;
  final bool returning, forceWelcome;
  final WidgetBuilder? returningBuilder;
  const _SignedOutEntry({
    required this.history,
    required this.returning,
    required this.forceWelcome,
    this.returningBuilder,
  });

  @override
  State<_SignedOutEntry> createState() => _SignedOutEntryState();
}

class _SignedOutEntryState extends State<_SignedOutEntry> {
  // Freeze this decision for the route's lifetime. Opening policies, rebuilding
  // or receiving a repeated signed-out event must not replace Welcome midway.
  late final _showWelcome = widget.returning
      ? Future.value(false)
      : widget.history
            .consumeWelcome(force: widget.forceWelcome)
            .catchError((Object _) => true);

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _showWelcome,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.data!) return const WelcomeScreen();
      return widget.returningBuilder?.call(context) ?? const LoginScreen();
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
      // AuthGate selects the entry screen when Firebase emits the signed-out
      // event; don't briefly flash Welcome over a returning user's Login.
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
              body: AppEmptyState.error(
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
