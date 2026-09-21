import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/profile/presentation/screens/profile_screen.dart';
import 'package:mooddare/features/profile/presentation/screens/connections_screen.dart';
import 'entry_polish_test.dart' show mount;
import 'profile_updates_test.dart' show ProfileChanges, ProfilePosts, profile;
import 'support/social_fakes.dart';

void main() {
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
        expect(tabs.controller!.index, 1);
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
      expect(find.text('Follow'), findsNothing);
    },
  );
}
