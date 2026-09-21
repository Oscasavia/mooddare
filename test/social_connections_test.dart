import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/profile/presentation/screens/connections_screen.dart';
import 'package:mooddare/features/profile/presentation/widgets/follow_button.dart';
import 'package:mooddare/features/profile/presentation/widgets/profile_connections.dart';
import 'support/social_fakes.dart';
import 'package:mooddare/models/user_model.dart';

void main() {
  late MemorySocial repo;
  setUp(() {
    repo = MemorySocial();
    for (final name in ['alice', 'bob', 'viewer']) {
      repo.users[name] = UserModel(
        id: name,
        username: name,
        name: 'Name $name',
        createdAt: Timestamp.now(),
      );
    }
  });
  tearDown(() => repo.changed.close());
  testWidgets(
    'follow and unfollow update from the stream; a failed write keeps state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FollowButton(userId: 'alice', repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      repo.fail = true;
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      expect(find.textContaining('Could not update follow'), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
    },
  );
  testWidgets(
    'connection search, profiles, follow and confirmed block work without self-follow',
    (tester) async {
      repo.followers['alice'] = {'alice', 'bob', 'viewer'};
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            opened = settings.arguments as String;
            return MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(),
                body: const Text('Opened profile'),
              ),
            );
          },
          home: ConnectionsScreen(
            userId: 'alice',
            followers: true,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsNWidgets(2));
      await tester.enterText(find.byType(TextField), '@bob');
      await tester.pumpAndSettle();
      expect(find.text('@alice'), findsNothing);
      expect(find.widgetWithText(TextButton, '@bob'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '@bob'));
      await tester.pumpAndSettle();
      expect(opened, 'bob');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(repo.following['viewer'], contains('bob'));
      await tester.tap(find.byTooltip('Account options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, '@bob'), findsOneWidget);
      await tester.tap(find.byTooltip('Account options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(find.text('No matching people'), findsOneWidget);
      expect(repo.following['viewer'], isNot(contains('bob')));
    },
  );
  testWidgets(
    'empty, failed and retried lists; following counts open correct screen',
    (tester) async {
      repo.following['viewer'] = {'bob'};
      repo.failPeople = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileConnections(
              userId: 'viewer',
              moments: 3,
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load profiles. Retry'), findsOneWidget);
      repo.failPeople = false;
      await tester.tap(find.text('Could not load profiles. Retry'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, '@bob'), findsOneWidget);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Following'));
      await tester.pumpAndSettle();
      expect(repo.following['viewer'], isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('No people here yet'), findsOneWidget);
    },
  );
}
