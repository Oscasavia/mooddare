import 'dart:async';
import 'package:mooddare/features/profile/data/social_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/profile/presentation/screens/profile_screen.dart';
import 'package:mooddare/features/profile/presentation/screens/connections_screen.dart';
import 'entry_polish_test.dart' show mount;
import 'profile_updates_test.dart' show ProfileChanges, ProfilePosts, profile;
import 'support/social_fakes.dart';

void main() {
  Future<void> openOther(
    WidgetTester tester,
    MemorySocial social, {
    double scale = 1,
  }) async {
    final users = ProfileChanges();
    addTearDown(users.updates.close);
    addTearDown(social.changed.close);
    await mount(
      tester,
      ProfileScreen(
        isGuest: false,
        userId: 'other',
        repository: users,
        postRepository: ProfilePosts(),
        socialRepository: social,
      ),
      scale: scale,
    );
  }

  Future<void> option(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Profile options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'profile block supports cancel, failure, retry and hides blocked content',
    (tester) async {
      final social = MemorySocial();
      await openOther(tester, social);
      await option(tester, 'Block user');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(social.blockedIds, isEmpty);
      social.fail = true;
      await option(tester, 'Block user');
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not block this account. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Follow'), findsOneWidget);
      social.fail = false;
      await option(tester, 'Block user');
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(social.blockedIds, contains('other'));
      expect(find.text('Follow'), findsNothing);
      expect(
        find.text('You blocked this account. You can unblock it in Settings.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Profile options'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.ancestor(
                of: find.text('Blocked'),
                matching: find.byType(PopupMenuItem<String>),
              ),
            )
            .enabled,
        isFalse,
      );
    },
  );
  testWidgets('existing block hides profile and report remains available', (
    tester,
  ) async {
    final social = MemorySocial()..blockedIds.add('other');
    await openOther(tester, social);
    expect(find.text('Follow'), findsNothing);
    await option(tester, 'Report user');
    expect(
      find.text(
        'Why are you reporting this account? Your report is not shared with them.',
      ),
      findsOneWidget,
    );
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'report at scale $scale requires a reason and preserves it through retry',
      (tester) async {
        final social = MemorySocial()..fail = true;
        await openOther(tester, social, scale: scale);
        await option(tester, 'Report user');
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit report'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Spam'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Submit report'));
        await tester.tap(find.text('Submit report'));
        await tester.pumpAndSettle();
        expect(
          find.text('Could not send your report. Please try again.'),
          findsOneWidget,
        );
        social.fail = false;
        social.reportGate = Completer<void>();
        await tester.ensureVisible(find.text('Submit report'));
        await tester.tap(find.text('Submit report'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Sending…'),
              )
              .onPressed,
          isNull,
        );
        social.reportGate!.complete();
        await tester.pumpAndSettle();
        expect(social.reports, [('other', UserReportReason.spam)]);
        expect(
          find.text('Report submitted. Thank you for letting us know.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('dismissing a pending report is safe', (tester) async {
    final social = MemorySocial()..reportGate = Completer<void>();
    await openOther(tester, social);
    await option(tester, 'Report user');
    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.ensureVisible(find.text('Submit report'));
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    social.reportGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'profile social stats and clean tabs fit a narrow phone at scale $scale',
      (tester) async {
        final users = ProfileChanges(),
            posts = ProfilePosts(),
            social = MemorySocial();
        addTearDown(users.updates.close);
        addTearDown(social.changed.close);
        await mount(
          tester,
          ProfileScreen(
            isGuest: false,
            repository: users,
            postRepository: posts,
            socialRepository: social,
          ),
          scale: scale,
        );
        expect(find.text('Followers'), findsOneWidget);
        expect(find.text('Following'), findsOneWidget);
        expect(find.text('Likes'), findsNothing);
        expect(find.text('Moments'), findsOneWidget);
        final tabs = tester.widget<TabBar>(find.byType(TabBar));
        expect(tabs.splashFactory, NoSplash.splashFactory);
        expect(
          tabs.overlayColor!.resolve({WidgetState.pressed}),
          Colors.transparent,
        );
        await tester.tap(find.text('Stats'));
        await tester.pumpAndSettle();
        expect(tabs.controller!.index, 2);
        await tester.tap(find.text('Dares'));
        await tester.pumpAndSettle();
        expect(tabs.controller!.index, 0);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Followers'));
        await tester.pumpAndSettle();
        expect(find.byType(ConnectionsScreen), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byTooltip('Edit Profile'), findsOneWidget);
        expect(find.byTooltip('Profile options'), findsNothing);
      },
    );
  }
  testWidgets(
    'avatar opens full picture with zoom and gracefully handles unavailable images',
    (tester) async {
      final users = ProfileChanges()
        ..current = profile(photo: 'https://example.invalid/avatar.jpg');
      final social = MemorySocial();
      addTearDown(users.updates.close);
      addTearDown(social.changed.close);
      await mount(
        tester,
        ProfileScreen(
          isGuest: false,
          repository: users,
          postRepository: ProfilePosts(),
          socialRepository: social,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('profile_photo')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Followers'), findsOneWidget);
    },
  );
  testWidgets(
    'another profile offers follow and same profile by explicit ID retains edit controls',
    (tester) async {
      final users = ProfileChanges(), social = MemorySocial();
      addTearDown(users.updates.close);
      addTearDown(social.changed.close);
      await mount(
        tester,
        ProfileScreen(
          isGuest: false,
          userId: 'other',
          repository: users,
          postRepository: ProfilePosts(),
          socialRepository: social,
        ),
      );
      expect(find.text('Follow'), findsOneWidget);
      expect(find.byTooltip('Edit Profile'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        ProfileScreen(
          isGuest: false,
          userId: 'viewer',
          repository: users,
          postRepository: ProfilePosts(),
          socialRepository: social,
        ),
      );
      expect(find.byTooltip('Edit Profile'), findsOneWidget);
      expect(find.byTooltip('Profile options'), findsNothing);
      expect(find.text('Follow'), findsNothing);
    },
  );
}
