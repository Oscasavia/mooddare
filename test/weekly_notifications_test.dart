import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/core/branding/mood_wink.dart';
import 'package:mooddare/features/dares/data/repositories/weekly_dare_repository.dart';
import 'package:mooddare/features/notifications/data/notification_repository.dart';
import 'package:mooddare/features/notifications/presentation/notification_inbox.dart';
import 'package:mooddare/features/notifications/presentation/notification_settings.dart';
import 'package:mooddare/features/notifications/presentation/weekly_dare_notification_screen.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late NotificationRepository repo;
  final monday = DateTime.utc(2026, 10, 5);
  Map<String, dynamic> schedule(DateTime now) => {
    'title': 'A little joy',
    'dareText': 'Capture something that made you smile.',
    'moodId': 'happy',
    'moodName': 'Happy',
    'startsAt': Timestamp.fromDate(WeeklyDare.weekStart(now)),
    'endsAt': Timestamp.fromDate(
      WeeklyDare.weekStart(now).add(const Duration(days: 7)),
    ),
  };
  Future<void> seed(String week) =>
      db.doc('users/alice/notifications/weekly').set({
        'kind': 'weekly',
        'weeklyDareId': week,
        'createdAt': Timestamp.now(),
        'read': false,
      });
  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'alice'));
    repo = NotificationRepository(firestore: db, auth: auth);
  });
  test(
    'weekly events parse without a fake user, reject invalid week paths, and keep existing defaults',
    () async {
      await seed('2026-10-05');
      final n = (await repo.get('weekly'))!;
      expect(n.actorId, '');
      expect(n.weeklyDareId, '2026-10-05');
      expect(n.message, contains('community dare'));
      await seed('../private');
      expect(await repo.get('weekly'), null);
      await db.doc('users/alice/notifications/weekly').update({
        'weeklyDareId': 123,
      });
      expect(await repo.get('weekly'), null);
      expect(await repo.watchWeekly('../private').first, null);
      expect((await repo.preferences().first)['weeklyDares'], true);
      await repo.setPreference('weeklyDares', false);
      expect((await repo.preferences().first)['weeklyDares'], false);
      expect((await repo.preferences().first)['dares'], true);
    },
  );
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
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
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'weekly inbox row uses Mood-wink and opens the announced dare without an actor profile',
    (tester) async {
      final id = WeeklyDare.weekId(DateTime.now());
      await seed(id);
      await db.doc('weeklyDares/$id').set(schedule(DateTime.now()));
      await pump(
        tester,
        NotificationInbox(
          repository: repo,
          social: SocialRepository(firestore: db, auth: auth),
        ),
      );
      expect(
        find.textContaining('MoodDare', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(MoodWink), findsOneWidget);
      expect(find.textContaining('@Someone', findRichText: true), findsNothing);
      await tester.tap(
        find.textContaining('community dare', findRichText: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('A little joy'), findsOneWidget);
      expect(find.text('Join this week'), findsOneWidget);
      expect((await repo.get('weekly'))!.read, true);
    },
  );
  testWidgets(
    'joining carries the exact weekly id, mood and prompt into capture',
    (tester) async {
      await db.doc('weeklyDares/2026-10-05').set(schedule(monday));
      WeeklyDare? selected;
      await pump(
        tester,
        WeeklyDareNotificationScreen(
          weekId: '2026-10-05',
          repository: repo,
          now: () => monday,
          cameraBuilder: (d) {
            selected = d;
            return const Scaffold(body: Text('Capture'));
          },
        ),
      );
      await tester.tap(find.text('Join this week'));
      await tester.pumpAndSettle();
      expect(selected!.id, '2026-10-05');
      expect(selected!.prompt.moodId, 'happy');
      expect(selected!.prompt.text, 'Capture something that made you smile.');
      expect(find.text('Capture'), findsOneWidget);
    },
  );
  testWidgets(
    'expired or missing notifications never switch silently to the new week',
    (tester) async {
      await db.doc('weeklyDares/2026-10-05').set(schedule(monday));
      await db
          .doc('weeklyDares/2026-10-12')
          .set(schedule(monday.add(const Duration(days: 7))));
      await pump(
        tester,
        WeeklyDareNotificationScreen(
          weekId: '2026-10-05',
          repository: repo,
          now: () => monday.add(const Duration(days: 7)),
        ),
      );
      expect(find.text('This weekly dare is no longer active'), findsOneWidget);
      expect(find.text('Join this week'), findsNothing);
      await db.doc('weeklyDares/2026-10-05').delete();
      await tester.pumpAndSettle();
      expect(find.text('Join this week'), findsNothing);
    },
  );
  testWidgets('rollover between viewing and joining blocks capture', (
    tester,
  ) async {
    var now = monday;
    var captures = 0;
    await db.doc('weeklyDares/2026-10-05').set(schedule(now));
    await pump(
      tester,
      WeeklyDareNotificationScreen(
        weekId: '2026-10-05',
        repository: repo,
        now: () => now,
        cameraBuilder: (_) {
          captures++;
          return const SizedBox();
        },
      ),
    );
    now = monday.add(const Duration(days: 7));
    await tester.tap(find.text('Join this week'));
    await tester.pumpAndSettle();
    expect(captures, 0);
    expect(find.text('This weekly dare is no longer active'), findsOneWidget);
  });
  testWidgets('weekly preference is separate from friend invitations', (
    tester,
  ) async {
    await pump(tester, NotificationSettingsScreen(repository: repo));
    await tester.tap(find.text('Weekly community dare'));
    await tester.pumpAndSettle();
    expect(
      (await db.doc('users/alice/preferences/notifications').get())
          .data()?['weeklyDares'],
      false,
    );
    expect(
      (await db.doc('users/alice/preferences/notifications').get())
          .data()?['dares'],
      null,
    );
  });
  testWidgets('weekly detail remains scrollable at large text size', (
    tester,
  ) async {
    await db.doc('weeklyDares/2026-10-05').set(schedule(monday));
    await pump(
      tester,
      WeeklyDareNotificationScreen(
        weekId: '2026-10-05',
        repository: repo,
        now: () => monday,
      ),
      scale: 2,
    );
    await tester.scrollUntilVisible(find.text('Join this week'), 300);
    expect(tester.takeException(), null);
  });
}
