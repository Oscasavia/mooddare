import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/profile/presentation/screens/settings_screen.dart';
import 'package:mooddare/features/settings/data/settings_repository.dart';
import 'package:mooddare/features/settings/presentation/help_screen.dart';
import 'package:mooddare/features/settings/presentation/password_screen.dart';
import 'support/settings_fakes.dart';

Future<void> openSettings(
  WidgetTester tester,
  MemorySettings repo, {
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 700);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: SettingsScreen(
        repository: repo,
        signedOutBuilder: (_) =>
            const Scaffold(body: Text('Signed out safely')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapRow(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'settings groups fit narrow phone at scale $scale; dangerous actions are last',
      (tester) async {
        final repo = MemorySettings();
        await openSettings(tester, repo, scale: scale);
        expect(find.text('Sign out'), findsNothing);
        for (final title in [
          'Notifications',
          'Blocked accounts',
          'Help & FAQ',
          'Contact us',
          'Share MoodDare',
          'About & licenses',
          'Sign out',
          'Delete account',
        ]) {
          await tester.scrollUntilVisible(
            find.text(title),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final tiles = tester
            .widgetList<ListTile>(find.byType(ListTile))
            .toList();
        expect((tiles[tiles.length - 2].title as Text).data, 'Sign out');
        expect((tiles.last.title as Text).data, 'Delete account');
        expect(repo.deletions + repo.signOuts, 0);
      },
    );
  }
  for (final delete in [false, true]) {
    final label = delete ? 'Delete account' : 'Sign out';
    testWidgets(
      '$label cancels safely, failure can retry, and pending action blocks duplicates/back',
      (tester) async {
        final repo = MemorySettings()..failAction = true;
        await openSettings(tester, repo);
        await tapRow(tester, label);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repo.deletions + repo.signOuts, 0);
        await tapRow(tester, label);
        await tester.tap(find.widgetWithText(FilledButton, label));
        await tester.pumpAndSettle();
        expect(find.textContaining('Something went wrong'), findsOneWidget);
        expect(find.byType(SettingsScreen), findsOneWidget);
        repo.failAction = false;
        final gate = Completer<void>();
        repo.actionGate = gate.future;
        await tapRow(tester, label);
        await tester.tap(find.widgetWithText(FilledButton, label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text('Finishing up. Please keep the app open.'),
          findsOneWidget,
        );
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(
          tester
              .widgetList<ListTile>(find.byType(ListTile))
              .every((tile) => tile.onTap == null),
          isTrue,
        );
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.text('Signed out safely'), findsOneWidget);
        expect(delete ? repo.deletions : repo.signOuts, 2);
      },
    );
  }
  testWidgets(
    'password validation, error retry and successful change preserve exact input',
    (tester) async {
      final repo = MemorySettings()..failPassword = true;
      await openSettings(tester, repo);
      await tapRow(tester, 'Change password');
      await tester.enterText(
        find.byKey(const ValueKey('current_password')),
        ' old password ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new_password')),
        'short',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm_password')),
        'different',
      );
      await tapRow(tester, 'Save password');
      expect(repo.changes, 0);
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(find.text('The passwords do not match.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('new_password')),
        ' new password ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm_password')),
        ' new password ',
      );
      await tapRow(tester, 'Save password');
      expect(find.text('Wrong current password.'), findsOneWidget);
      repo.failPassword = false;
      await tapRow(tester, 'Save password');
      expect(find.byType(PasswordScreen), findsNothing);
      expect(find.text('Password updated.'), findsOneWidget);
      expect(repo.currentPassword, ' old password ');
      expect(repo.newPassword, ' new password ');
    },
  );
  testWidgets('reset email is explicit and cannot be sent repeatedly', (
    tester,
  ) async {
    final repo = MemorySettings();
    await openSettings(tester, repo, scale: 2);
    await tapRow(tester, 'Change password');
    await tapRow(tester, 'Forgot your current password?');
    expect(repo.resets, 1);
    expect(find.textContaining('Password reset email sent'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Forgot your current password?'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Google account uses provider management; guest warned before signout',
    (tester) async {
      final repo = MemorySettings()
        ..account = const SettingsAccount(google: true);
      await openSettings(tester, repo);
      await tapRow(tester, 'Change password');
      expect(find.byType(PasswordScreen), findsNothing);
      await tester.tap(find.text('Google account'));
      await tester.pumpAndSettle();
      expect(
        repo.urls.single.toString(),
        'https://myaccount.google.com/security',
      );
      expect(repo.changes, 0);
      repo.account = const SettingsAccount(guest: true);
      await tapRow(tester, 'Sign out');
      expect(
        find.textContaining('Signing out can lose access'),
        findsOneWidget,
      );
      expect(repo.signOuts, 0);
    },
  );
  testWidgets(
    'notification settings opens OS controls and shows fallback on failure',
    (tester) async {
      final repo = MemorySettings()..failOpen = true;
      await openSettings(tester, repo);
      await tapRow(tester, 'Notifications');
      expect(find.byType(Switch), findsNothing);
      expect(
        find.textContaining('Push notifications are coming later'),
        findsOneWidget,
      );
      await tapRow(tester, 'Open phone settings');
      expect(
        find.textContaining('Could not open notification settings'),
        findsOneWidget,
      );
      repo.failOpen = false;
      await tapRow(tester, 'Open phone settings');
      expect(repo.notifications, 2);
      expect(
        find.textContaining('Could not open notification settings'),
        findsNothing,
      );
    },
  );
  testWidgets(
    'FAQ expands and links to working contact draft with email fallback',
    (tester) async {
      final repo = MemorySettings()..failOpen = true;
      await openSettings(tester, repo, scale: 2);
      await tapRow(tester, 'Help & FAQ');
      await tapRow(tester, 'How do I edit or delete a comment?');
      expect(
        find.textContaining('Open comments and use the menu'),
        findsOneWidget,
      );
      await tapRow(tester, 'Still need help? Contact us');
      expect(find.byType(ContactScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'The screen freezes & stops\nPlease help!',
      );
      await tapRow(tester, 'Open email draft');
      final url = repo.urls.single;
      expect(url.scheme, 'mailto');
      expect(url.path, SettingsRepository.supportEmail);
      expect(
        url.queryParameters['body'],
        contains('The screen freezes & stops\nPlease help!'),
      );
      expect(url.queryParameters['body'], contains('1.0.0 (42)'));
      expect(
        find.textContaining('Could not open your email app'),
        findsOneWidget,
      );
      await tapRow(tester, 'Copy support draft');
      expect(repo.copied, contains('The screen freezes & stops'));
      expect(repo.copied, contains(SettingsRepository.supportEmail));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'share has a nonempty popover origin, retry and clearly labelled placeholder',
    (tester) async {
      final repo = MemorySettings()..failShare = true;
      await openSettings(tester, repo);
      await tapRow(tester, 'Share MoodDare');
      expect(find.textContaining('Could not open sharing'), findsOneWidget);
      expect(find.text('Preview link · download coming soon'), findsOneWidget);
      repo.failShare = false;
      await tapRow(tester, 'Share MoodDare');
      expect(repo.shares, 2);
      expect(repo.shareOrigin!.isEmpty, isFalse);
      await tapRow(tester, 'About & licenses');
      expect(find.text('1.0.0 (42)'), findsWidgets);
    },
  );
}
