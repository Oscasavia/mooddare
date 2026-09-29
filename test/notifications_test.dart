import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/notifications/data/notification_repository.dart';
import 'package:mooddare/features/notifications/presentation/notification_inbox.dart';
import 'package:mooddare/features/notifications/presentation/notification_settings.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late NotificationRepository repo;
  Future<void> seed(
    String id, {
    String kind = 'follow',
    String actor = 'bob',
    bool read = false,
    DateTime? time,
    Map<String, dynamic> extra = const {},
  }) => db.doc('users/alice/notifications/$id').set({
    'kind': kind,
    'actorId': actor,
    'read': read,
    'createdAt': Timestamp.fromDate(time ?? DateTime.now()),
    ...extra,
  });
  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'alice'));
    repo = NotificationRepository(firestore: db, auth: auth);
  });
  test(
    'inbox is newest-first, bounded, excludes unknown kinds, and unread reacts',
    () async {
      await seed('old', time: DateTime(2026));
      await seed('new', kind: 'reply');
      await seed('unknown', kind: 'unknown');
      expect((await repo.watch(limit: 2).first).map((n) => n.id), ['new']);
      expect(await repo.unread().first, true);
      await repo.markRead('new');
      expect((await repo.get('new'))!.read, true);
      await repo.markAllRead();
      expect(await repo.unread().first, false);
      expect((await repo.get('old'))!.message, 'started following you');
    },
  );
  test(
    'mark all handles more than one batch and preserves newer arrivals',
    () async {
      for (var i = 0; i < 205; i++) {
        await seed('$i', time: DateTime(2026));
      }
      await seed('future', time: DateTime.now().add(const Duration(days: 1)));
      await repo.markAllRead();
      expect(
        (await db
                .collection('users/alice/notifications')
                .where('read', isEqualTo: true)
                .get())
            .docs
            .length,
        205,
      );
      expect((await repo.get('future'))!.read, false);
    },
  );
  test(
    'settings default enabled and persist independently, invalid keys rejected',
    () async {
      expect((await repo.preferences().first)['push'], true);
      await repo.setPreference('likes', false);
      await repo.setPreference('push', false);
      final prefs = await repo.preferences().first;
      expect(prefs['likes'], false);
      expect(prefs['push'], false);
      expect(prefs['comments'], true);
      expect(() => repo.setPreference('unknown', false), throwsStateError);
    },
  );
  test(
    'signed-out inbox and unread are empty without Firebase access',
    () async {
      await auth.signOut();
      expect(await repo.watch().first, isEmpty);
      expect(await repo.unread().first, false);
      expect(await repo.get('x'), null);
    },
  );
  test(
    'destination resolution handles missing and deleting posts, deleted comments, and archived profile moments',
    () async {
      await seed(
        'n',
        kind: 'comment',
        extra: {'postId': 'p', 'commentId': 'c'},
      );
      final n = (await repo.get('n'))!;
      expect(await repo.post(n), null);
      await db.doc('posts/p').set({
        'authorId': 'bob',
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 1)),
        ),
      });
      expect(await repo.post(n), null);
      await db.doc('posts/p/comments/c').set({'authorId': 'bob'});
      expect((await repo.post(n))!.id, 'p');
      await db.doc('posts/p').update({'deleting': true});
      expect(await repo.post(n), null);
      await db.doc('posts/p').update({
        'deleting': false,
        'expiresAt': Timestamp.fromDate(DateTime(2020)),
      });
      expect((await repo.post(n))!.id, 'p');
    },
  );
  test('actor and invitations resolve only current existing content', () async {
    expect(await repo.actor('bob'), null);
    await db.doc('users/bob').set({'id': 'bob', 'username': 'Bob'});
    expect((await repo.actor('bob'))!.username, 'Bob');
    await seed('d', kind: 'dare', extra: {'inviteId': 'd'});
    final n = (await repo.get('d'))!;
    expect(await repo.inviteAvailable(n), false);
    await db.doc('dareInvites/d').set({'recipientId': 'someone'});
    expect(await repo.inviteAvailable(n), false);
    await db.doc('dareInvites/d').update({'recipientId': 'alice'});
    expect(await repo.inviteAvailable(n), true);
  });
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
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inbox displays activity, unread filter, timestamps and mark all read',
    (tester) async {
      await db.doc('users/bob').set({'id': 'bob', 'username': 'Bob'});
      await seed('follow');
      await seed('like', kind: 'postLike', read: true);
      await pump(
        tester,
        NotificationInbox(
          repository: repo,
          social: SocialRepository(firestore: db, auth: auth),
        ),
      );
      expect(
        find.textContaining('started following you', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Just now'), findsNWidgets(2));
      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('liked your moment', findRichText: true),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.text('You’re all caught up'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'blocked activity is hidden and missing destination shows useful message',
    (tester) async {
      await seed('blocked', actor: 'blocked');
      await seed('missing');
      await db.doc('users/alice/blocked/blocked').set({});
      await pump(
        tester,
        NotificationInbox(
          repository: repo,
          social: SocialRepository(firestore: db, auth: auth),
        ),
      );
      expect(
        find.textContaining('started following you', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(
        find.textContaining('started following you', findRichText: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('This account is no longer available.'), findsOneWidget);
    },
  );
  testWidgets('empty branded inbox and settings navigation', (tester) async {
    await pump(
      tester,
      NotificationInbox(
        repository: repo,
        social: SocialRepository(firestore: db, auth: auth),
      ),
    );
    expect(find.text('Your next connection starts here'), findsOneWidget);
    await tester.tap(find.byTooltip('Notification settings'));
    await tester.pumpAndSettle();
    expect(find.text('Your activity, your way'), findsOneWidget);
    await tester.tap(find.text('New followers'));
    await tester.pumpAndSettle();
    expect(
      (await db.doc('users/alice/preferences/notifications').get())
          .data()?['follows'],
      false,
    );
  });
  testWidgets('bell unread badge follows server state', (tester) async {
    await pump(
      tester,
      Scaffold(
        appBar: AppBar(actions: [NotificationBell(repository: repo)]),
      ),
    );
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, false);
    await seed('n');
    await tester.pumpAndSettle();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, true);
    await repo.markRead('n');
    await tester.pumpAndSettle();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, false);
  });
  testWidgets('preferences tolerate large text on a narrow screen', (
    tester,
  ) async {
    await pump(tester, NotificationSettingsScreen(repository: repo), scale: 2);
    await tester.scrollUntilVisible(find.text('Open phone settings'), 300);
    expect(tester.takeException(), null);
  });
}
