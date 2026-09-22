import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/settings/data/settings_repository.dart';
import 'package:mooddare/features/settings/presentation/delete_account_screen.dart';
import 'settings_test.dart' show openSettings, tapRow;
import 'support/settings_fakes.dart';

void main() {
  final confirm = find.byKey(const ValueKey('delete_confirmation'));
  final button = find.byKey(const ValueKey('confirm_delete_account'));
  Future<void> open(
    WidgetTester tester,
    MemorySettings repo, {
    double scale = 1,
  }) async {
    await openSettings(tester, repo, scale: scale);
    await tapRow(tester, 'Delete account');
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
  }

  Future<void> press(WidgetTester tester) async {
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'dedicated screen requires DELETE, cancellation is safe and recent sessions delete directly',
    (tester) async {
      final repo = MemorySettings();
      await open(tester, repo);
      for (final text in ['', 'delete', 'DELET', 'not DELETE']) {
        await tester.enterText(confirm, text);
        await tester.pump();
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
      }
      await tester.tap(find.text('Keep my account'));
      await tester.pumpAndSettle();
      expect(repo.deletions, 0);
      await tapRow(tester, 'Delete account');
      await tester.enterText(confirm, 'DELETE');
      await tester.pump();
      await press(tester);
      expect(repo.deletions, 1);
      expect(repo.verifications, 0);
      expect(repo.signOuts, 0);
      expect(find.text('Signed out safely'), findsOneWidget);
    },
  );
  testWidgets(
    'old password session verifies in place; wrong password never retries deletion',
    (tester) async {
      final repo = MemorySettings()
        ..needsVerification = true
        ..rejectVerification = true;
      await open(tester, repo);
      await tester.enterText(confirm, 'DELETE');
      await tester.pump();
      await press(tester);
      expect(repo.deletions, 1);
      final password = find.byKey(const ValueKey('delete_password'));
      expect(password, findsOneWidget);
      await press(tester);
      expect(repo.verifications, 0);
      await tester.enterText(password, ' exact password ');
      await press(tester);
      expect(repo.deletions, 1);
      expect(repo.verifications, 1);
      expect(find.text('The email or password is incorrect.'), findsOneWidget);
      repo.rejectVerification = false;
      await press(tester);
      expect(repo.currentPassword, ' exact password ');
      expect(repo.deletions, 2);
      expect(repo.signOuts, 0);
      expect(find.text('Signed out safely'), findsOneWidget);
    },
  );
  testWidgets(
    'Google verification cancellation retains account and confirmation for retry',
    (tester) async {
      final repo = MemorySettings()
        ..account = const SettingsAccount(google: true)
        ..needsVerification = true
        ..cancelVerification = true;
      await open(tester, repo);
      await tester.enterText(confirm, 'DELETE');
      await tester.pump();
      await press(tester);
      expect(find.byKey(const ValueKey('delete_password')), findsNothing);
      await press(tester);
      expect(repo.deletions, 1);
      expect(repo.signOuts, 0);
      expect(find.textContaining('Verification cancelled'), findsOneWidget);
      repo.cancelVerification = false;
      await press(tester);
      expect(repo.deletions, 2);
      expect(find.text('Signed out safely'), findsOneWidget);
    },
  );
  testWidgets(
    'failure retries, large text fits and pending deletion blocks back and duplicates',
    (tester) async {
      final repo = MemorySettings()..failAction = true;
      await open(tester, repo, scale: 2);
      await tester.enterText(confirm, 'DELETE');
      await tester.pump();
      await press(tester);
      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect(tester.takeException(), isNull);
      repo.failAction = false;
      final gate = Completer<void>();
      repo.actionGate = gate.future;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
      expect(repo.deletions, 2);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Signed out safely'), findsOneWidget);
    },
  );
  testWidgets(
    'changed account identity cannot delete the newly signed-in account',
    (tester) async {
      final repo = MemorySettings()
        ..account = const SettingsAccount(id: 'alice', password: true);
      await open(tester, repo);
      repo.account = const SettingsAccount(id: 'bob', password: true);
      await tester.enterText(confirm, 'DELETE');
      await tester.pump();
      await press(tester);
      expect(repo.deletions, 0);
      expect(find.textContaining('account changed'), findsOneWidget);
    },
  );
}
