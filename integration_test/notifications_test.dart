import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/dares/data/repositories/weekly_dare_repository.dart';
import 'package:mooddare/features/notifications/data/notification_repository.dart';
import 'package:mooddare/features/notifications/presentation/notification_inbox.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'notification inbox on Android handles activity, read state and preferences',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'viewer'),
      );
      final repo = NotificationRepository(firestore: db, auth: auth);
      final names = ['aria', 'jules', 'kai', 'mila'];
      for (var i = 0; i < names.length; i++) {
        await db.doc('users/${names[i]}').set({
          'id': names[i],
          'username': names[i],
        });
        await db.doc('users/viewer/notifications/$i').set({
          'actorId': names[i],
          'kind': ['follow', 'postLike', 'reply', 'dare'][i],
          'read': i > 1,
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(Duration(minutes: 10 * (i + 1))),
          ),
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: NotificationInbox(
            repository: repo,
            social: SocialRepository(firestore: db, auth: auth),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('@aria', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(find.textContaining('@kai', findRichText: true), findsNothing);
      await tester.tap(find.byTooltip('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.text('You’re all caught up'), findsOneWidget);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Notification settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New followers'));
      await tester.pumpAndSettle();
      expect(
        (await db.doc('users/viewer/preferences/notifications').get())
            .data()?['follows'],
        false,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      if (const bool.fromEnvironment('NOTIFICATION_REVIEW')) {
        debugPrint('Notification review screen ready');
        await Future<void>.delayed(const Duration(seconds: 35));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('weekly announcement opens its dare and handles removal', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'viewer'),
    );
    final repo = NotificationRepository(firestore: db, auth: auth);
    final start = WeeklyDare.weekStart(DateTime.now());
    final id = WeeklyDare.weekId(start);
    await db.doc('weeklyDares/$id').set({
      'title': 'A little joy',
      'dareText': 'Capture something that made you smile.',
      'moodId': 'happy',
      'moodName': 'Happy',
      'startsAt': Timestamp.fromDate(start),
      'endsAt': Timestamp.fromDate(start.add(const Duration(days: 7))),
    });
    await db.doc('users/viewer/notifications/weekly').set({
      'kind': 'weekly',
      'weeklyDareId': id,
      'createdAt': Timestamp.now(),
      'read': false,
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: NotificationInbox(
          repository: repo,
          social: SocialRepository(firestore: db, auth: auth),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('community dare', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('A little joy'), findsOneWidget);
    expect(find.text('Join this week'), findsOneWidget);
    expect((await repo.get('weekly'))!.read, true);
    await db.doc('weeklyDares/$id').delete();
    await tester.pumpAndSettle();
    expect(find.text('This weekly dare is no longer active'), findsOneWidget);
    expect(find.text('Join this week'), findsNothing);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
