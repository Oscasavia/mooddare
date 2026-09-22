import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/auth/presentation/auth_gate.dart';

class SessionUser implements User {
  @override
  final bool isAnonymous;
  @override
  final String uid;
  SessionUser(this.uid, {this.isAnonymous = false});
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SessionAuth implements FirebaseAuth {
  @override
  User? currentUser;
  final changes = StreamController<User?>.broadcast();
  Completer<void>? signOutGate;
  bool failSignOut = false;
  int signOuts = 0;

  @override
  Stream<User?> userChanges() => changes.stream;

  void emit(User? user) {
    currentUser = user;
    changes.add(user);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    await signOutGate?.future;
    if (failSignOut) throw FirebaseAuthException(code: 'internal-error');
    emit(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SessionAuth auth;
  late List<String> admitted;
  setUp(() {
    auth = SessionAuth();
    admitted = [];
  });
  tearDown(() => auth.changes.close());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          auth: auth,
          signedInBuilder: (_, user) {
            admitted.add(user.uid);
            return const Scaffold(body: Text('Member feed'));
          },
        ),
      ),
    );
  }

  testWidgets('persisted guest is signed out before welcome is shown', (
    tester,
  ) async {
    auth.signOutGate = Completer<void>();
    await mount(tester);
    auth.emit(SessionUser('old-guest', isAnonymous: true));
    await tester.pump();
    await tester.pump();
    expect(auth.signOuts, 1);
    expect(admitted, isEmpty);
    expect(find.text('Find your next dare'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Repeated SDK events must not launch concurrent sign-outs.
    auth.emit(auth.currentUser);
    await tester.pump();
    expect(auth.signOuts, 1);
    auth.signOutGate!.complete();
    await tester.pumpAndSettle();
    expect(auth.currentUser, isNull);
    expect(find.text('Find your next dare'), findsOneWidget);
    expect(admitted, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed guest sign-out blocks access and can be retried', (
    tester,
  ) async {
    auth.failSignOut = true;
    await mount(tester);
    auth.emit(SessionUser('old-guest', isAnonymous: true));
    await tester.pumpAndSettle();
    expect(
      find.text('Guest access has ended. Try again to finish signing out.'),
      findsOneWidget,
    );
    expect(find.text('Find your next dare'), findsNothing);
    expect(admitted, isEmpty);
    auth.failSignOut = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(auth.signOuts, 2);
    expect(auth.currentUser, isNull);
    expect(find.text('Find your next dare'), findsOneWidget);
    expect(admitted, isEmpty);
  });

  testWidgets('signed-out and member sessions are never signed out', (
    tester,
  ) async {
    await mount(tester);
    auth.emit(null);
    await tester.pumpAndSettle();
    expect(find.text('Find your next dare'), findsOneWidget);
    for (final uid in ['email-member', 'google-member']) {
      auth.emit(SessionUser(uid));
      await tester.pumpAndSettle();
      expect(find.text('Member feed'), findsOneWidget);
      expect(auth.currentUser!.uid, uid);
    }
    expect(admitted, ['email-member', 'google-member']);
    expect(auth.signOuts, 0);
  });

  testWidgets(
    'member session survives backgrounding, auth refresh and rebuilt app UI',
    (tester) async {
      await mount(tester);
      final member = SessionUser('member');
      auth.emit(member);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      auth.emit(member);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      auth.emit(auth.currentUser);
      await tester.pumpAndSettle();
      expect(find.text('Member feed'), findsOneWidget);
      expect(auth.signOuts, 0);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Find your next dare'), findsOneWidget);
    },
  );

  testWidgets(
    'session stream errors show retry without signing out or presenting login',
    (tester) async {
      await mount(tester);
      auth.emit(SessionUser('member'));
      await tester.pumpAndSettle();
      auth.changes.addError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Could not restore your session'), findsOneWidget);
      expect(find.text('Find your next dare'), findsNothing);
      expect(auth.signOuts, 0);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      auth.emit(auth.currentUser);
      await tester.pumpAndSettle();
      expect(find.text('Member feed'), findsOneWidget);
    },
  );

  testWidgets('new member can sign in after an old guest is cleared', (
    tester,
  ) async {
    await mount(tester);
    auth.emit(SessionUser('old-guest', isAnonymous: true));
    await tester.pumpAndSettle();
    auth.emit(SessionUser('member'));
    await tester.pumpAndSettle();
    expect(admitted, ['member']);
    expect(auth.signOuts, 1);
    expect(find.text('Member feed'), findsOneWidget);
  });
}
