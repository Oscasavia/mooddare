import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/auth/presentation/auth_gate.dart';
import 'package:mooddare/features/settings/presentation/delete_account_screen.dart';
import 'guest_session_test.dart' show SessionAuth, SessionUser;
import 'support/settings_fakes.dart';
import 'support/welcome_history_fake.dart';

class RestoringAuth extends SessionAuth {
  @override
  Stream<User?> userChanges() async* {
    yield currentUser;
    yield* changes.stream;
  }
}

class DeletingSettings extends MemorySettings {
  final RestoringAuth sessionAuth;
  DeletingSettings(this.sessionAuth);
  @override
  Future<void> deleteAccount() async {
    await super.deleteAccount();
    sessionAuth.emit(null);
  }
}

void main() {
  late RestoringAuth auth;
  late MemoryWelcomeHistory history;
  setUp(() {
    auth = RestoringAuth();
    history = MemoryWelcomeHistory();
  });
  tearDown(() => auth.changes.close());

  Widget gate({
    bool force = false,
    Widget Function(BuildContext, User)? member,
  }) => AuthGate(
    auth: auth,
    welcomeHistory: history,
    showWelcome: force,
    returningBuilder: (_) => const Scaffold(body: Text('Returning login')),
    signedInBuilder:
        member ?? (_, user) => const Scaffold(body: Text('Member feed')),
  );
  Future<void> mount(
    WidgetTester tester, {
    bool force = false,
    Widget Function(BuildContext, User)? member,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: gate(force: force, member: member),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> restart(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await mount(tester);
  }

  testWidgets(
    'first welcome remains stable through refresh/resume; next cold start is login',
    (tester) async {
      await mount(tester);
      expect(find.text('Get started'), findsOneWidget);
      expect(history.seen, isTrue);
      auth.emit(null);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
      expect(history.reads, 1);
      await restart(tester);
      expect(find.text('Returning login'), findsOneWidget);
      expect(find.text('Get started'), findsNothing);
      await restart(tester);
      expect(find.text('Returning login'), findsOneWidget);
    },
  );

  testWidgets(
    'existing member migrates history, refresh does not rewrite, signout and relaunch use login',
    (tester) async {
      auth.currentUser = SessionUser('existing');
      await mount(tester);
      expect(find.text('Member feed'), findsOneWidget);
      expect(history.members, 1);
      auth.emit(auth.currentUser);
      await tester.pumpAndSettle();
      expect(history.members, 1);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Returning login'), findsOneWidget);
      await restart(tester);
      expect(find.text('Returning login'), findsOneWidget);
      auth.emit(SessionUser('another-account'));
      await tester.pumpAndSettle();
      expect(find.text('Member feed'), findsOneWidget);
      expect(auth.signOuts, 1);
    },
  );

  testWidgets(
    'preference read failure still allows Welcome; returning sessions stay usable',
    (tester) async {
      history.failRead = true;
      await mount(tester);
      expect(find.text('Get started'), findsOneWidget);
      auth.emit(SessionUser('member'));
      await tester.pumpAndSettle();
      expect(find.text('Member feed'), findsOneWidget);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Returning login'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final resetFails in [false, true]) {
    testWidgets(
      'only successful deletion shows welcome, including preference failure=$resetFails',
      (tester) async {
        auth.currentUser = SessionUser('member');
        history.failReset = resetFails;
        final repo = DeletingSettings(auth)..failAction = true;
        await mount(
          tester,
          member: (context, user) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DeleteAccountScreen(
                    repository: repo,
                    welcomeHistory: history,
                    signedOutBuilder: (_) => gate(force: true),
                  ),
                ),
              ),
              child: const Text('Open deletion'),
            ),
          ),
        );
        await tester.tap(find.text('Open deletion'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep my account'));
        await tester.pumpAndSettle();
        expect(history.resets, 0);
        await tester.tap(find.text('Open deletion'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('delete_confirmation')),
          'DELETE',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('confirm_delete_account')));
        await tester.pumpAndSettle();
        expect(find.byType(DeleteAccountScreen), findsOneWidget);
        expect(history.resets, 0);
        expect(repo.deletions, 1);
        repo.failAction = false;
        await tester.tap(find.byKey(const ValueKey('confirm_delete_account')));
        await tester.pumpAndSettle();
        expect(history.resets, 1);
        expect(find.text('Get started'), findsOneWidget);
        expect(find.text('Returning login'), findsNothing);
        expect(find.byType(DeleteAccountScreen), findsNothing);
        expect(repo.deletions, 2);
        await restart(tester);
        expect(find.text('Returning login'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
