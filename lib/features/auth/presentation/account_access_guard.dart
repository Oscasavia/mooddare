import 'package:mooddare/features/notifications/data/push_service.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/features/profile/data/account_repository.dart';
import '../data/welcome_history.dart';

/// Wraps the navigator so an already-open camera or detail route cannot cover
/// an account restriction. Backend rules independently enforce the restriction.
class AccountAccessGuard extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final Future<void> Function(String)? clearDeletedAccount;
  final VoidCallback? onAccountDeleted;
  const AccountAccessGuard({
    super.key,
    required this.child,
    this.enabled = true,
    this.auth,
    this.firestore,
    this.clearDeletedAccount,
    this.onAccountDeleted,
  });
  @override
  State<AccountAccessGuard> createState() => _AccountAccessGuardState();
}

class _AccountAccessGuardState extends State<AccountAccessGuard>
    with WidgetsBindingObserver {
  late final _auth = widget.auth ?? FirebaseAuth.instance;
  late final _db = widget.firestore ?? FirebaseFirestore.instance;
  StreamSubscription<User?>? _session;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _access;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _deletion;
  bool _erasing = false;
  String? _deletionError;
  Timer? _expiry;
  Map<String, dynamic>? _restriction;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) _start();
  }

  @override
  void didUpdateWidget(covariant AccountAccessGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) _start();
  }

  void _start() {
    _session = _auth.authStateChanges().listen((user) {
      _access?.cancel();
      _deletion?.cancel();
      _expiry?.cancel();
      if (mounted) setState(() => _restriction = null);
      if (user == null) return;
      _deletion = _db.doc('accountDeletions/${user.uid}').snapshots().listen((
        snapshot,
      ) {
        if (snapshot.exists && _auth.currentUser?.uid == user.uid) {
          _endDeletedSession(user.uid);
        }
      }, onError: (Object _) {});
      _checkSession(user);
      _access = _db
          .doc('accountRestrictions/${user.uid}')
          .snapshots()
          .listen(
            (snapshot) {
              if (!mounted || _auth.currentUser?.uid != user.uid) return;
              _expiry?.cancel();
              final data = snapshot.data();
              final until = (data?['until'] as Timestamp?)?.toDate();
              setState(() => _restriction = data);
              if (until != null && until.isAfter(DateTime.now())) {
                _expiry = Timer(until.difference(DateTime.now()), () {
                  if (mounted) setState(() {});
                });
              }
            },
            onError: (Object _) {
              // Do not erase a known restriction after a connection/auth failure.
            },
          );
    });
  }

  Future<void> _checkSession(User user) async {
    try {
      await user.reload();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-not-found' &&
          _auth.currentUser?.uid == user.uid) {
        await _endDeletedSession(user.uid);
      }
    } catch (_) {
      // Offline users retain their session; the server still enforces access.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) return;
    final user = _auth.currentUser;
    if (state == AppLifecycleState.resumed && user != null) _checkSession(user);
  }

  Future<void> _endDeletedSession(String uid) async {
    if (!mounted || _erasing || _auth.currentUser?.uid != uid) return;
    setState(() {
      _erasing = true;
      _deletionError = null;
    });
    try {
      await (widget.clearDeletedAccount ??
          AccountRepository.clearLocalAccountData)(uid);
      try {
        await WelcomeHistory.instance.resetAfterDeletion();
      } catch (_) {}
      if (_auth.currentUser?.uid == uid) {
        await _auth.signOut();
      }
      if (mounted && _auth.currentUser == null) widget.onAccountDeleted?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => _deletionError =
              'Please retry to clear this device’s saved account data.',
        );
      }
    } finally {
      if (mounted) setState(() => _erasing = false);
    }
  }

  @override
  void dispose() {
    _session?.cancel();
    _access?.cancel();
    _deletion?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_erasing || _deletionError != null) {
      return Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const MoodWink(size: 88),
                        const SizedBox(height: 24),
                        Text(
                          _deletionError ?? 'Your account is being deleted.',
                          textAlign: TextAlign.center,
                        ),
                        if (_deletionError != null)
                          TextButton(
                            onPressed: () {
                              final uid = _auth.currentUser?.uid;
                              if (uid != null) _endDeletedSession(uid);
                            },
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final data = _restriction;
    final until = (data?['until'] as Timestamp?)?.toDate();
    final blocked =
        data?['status'] == 'banned' ||
        (data?['status'] == 'suspended' &&
            until != null &&
            until.isAfter(DateTime.now()));
    if (!blocked) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MoodWink(size: 88),
                const SizedBox(height: 24),
                Text(
                  data?['status'] == 'banned'
                      ? 'Your account is restricted'
                      : 'Your account is temporarily suspended',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  data?['reason'] as String? ??
                      'Please contact MoodDare for help.',
                  textAlign: TextAlign.center,
                ),
                if (data?['status'] == 'suspended' && until != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Until ${until.toLocal()}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 16),
                const SelectableText(
                  'For help or to appeal: oscasavia@gmail.com',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () async {
                    await PushService.instance?.detach();
                    await _auth.signOut();
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
