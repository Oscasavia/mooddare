import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/core/app_theme.dart';
import 'package:mooddare/features/auth/presentation/account_access_guard.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/models/comment_model.dart';
import 'moments_test.dart' show openFeed, tapMedia;
import 'support/moments_fakes.dart';

void main() {
  test(
    'comment and reply reports preserve target and reporter without copying text',
    () async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'reporter'),
      );
      final repo = PostRepository(
        firestore: db,
        auth: auth,
        storage: MockFirebaseStorage(),
      );
      for (final reply in [false, true]) {
        final comment = CommentModel(
          id: 'c',
          authorId: 'author',
          text: 'Private content',
          parentId: reply ? 'root' : null,
        );
        await repo.reportComment('post', comment, 'harassment');
        final row =
            (await db
                    .doc(
                      'reports/reporter_${reply ? 'reply' : 'comment'}_post_c',
                    )
                    .get())
                .data()!;
        expect(row['reporterId'], 'reporter');
        expect(row['isReply'], reply);
        expect(row.containsKey('text'), false);
        await repo.reportComment('post', comment, 'spam');
        expect(
          (await db
                  .doc('reports/reporter_${reply ? 'reply' : 'comment'}_post_c')
                  .get())
              .data()!['reason'],
          'spam',
        );
        await expectLater(
          repo.reportComment('post', comment, 'invalid'),
          throwsFormatException,
        );
      }
      expect((await db.collection('reports').get()).docs.length, 2);
    },
  );
  testWidgets(
    'restriction replaces an already-open route and reinstatement restores access',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'member'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          builder: (_, child) =>
              AccountAccessGuard(auth: auth, firestore: db, child: child!),
          home: const Scaffold(body: Text('Camera open')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Camera open'), findsOneWidget);
      await db.doc('accountRestrictions/member').set({
        'status': 'banned',
        'reason': 'Repeated harassment',
      });
      await tester.pumpAndSettle();
      expect(find.text('Camera open'), findsNothing);
      expect(find.text('Your account is restricted'), findsOneWidget);
      expect(find.text('Repeated harassment'), findsOneWidget);
      await db.doc('accountRestrictions/member').set({'status': 'active'});
      await tester.pumpAndSettle();
      expect(find.text('Camera open'), findsOneWidget);
      await db.doc('accountRestrictions/member').set({
        'status': 'suspended',
        'until': Timestamp.fromMillisecondsSinceEpoch(0),
      });
      await tester.pumpAndSettle();
      expect(find.text('Camera open'), findsOneWidget);
    },
  );
  testWidgets(
    'temporary restriction supports sign-out on a narrow large-text screen',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'member'),
      );
      await db.doc('accountRestrictions/member').set({
        'status': 'suspended',
        'until': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
        'reason': 'Please review the community rules.',
      });
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: AccountAccessGuard(auth: auth, firestore: db, child: child!),
          ),
          home: const Scaffold(body: Text('App')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Your account is temporarily suspended'),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(auth.currentUser, null);
    },
  );
  testWidgets(
    'report option is available on someone else’s comment and submits its reason',
    (tester) async {
      final repo = MemoryPosts([moment('post')])
        ..comments.add(
          const CommentModel(id: 'c', authorId: 'other', text: 'A comment'),
        );
      await openFeed(tester, repo);
      await tester.tap(find.byTooltip('Comments'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Comment options'));
      await tester.pumpAndSettle();
      expect(find.text('Delete comment'), findsNothing);
      await tester.tap(find.text('Report comment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Harassment'));
      await tester.pumpAndSettle();
      expect(repo.reports, 1);
      expect(
        find.text('Report sent. Thank you for letting us know.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('removed comment has no like, edit, reply or original text', (
    tester,
  ) async {
    final repo = MemoryPosts([moment('post')])
      ..comments.add(
        const CommentModel(
          id: 'c',
          authorId: 'other',
          text: 'Original private text',
          moderationRemoved: true,
        ),
      );
    await openFeed(tester, repo);
    await tester.tap(find.byTooltip('Comments'));
    await tester.pumpAndSettle();
    expect(find.text('Original private text'), findsNothing);
    expect(find.text('This comment was removed by MoodDare.'), findsOneWidget);
    expect(find.byKey(const ValueKey('comment_like_c')), findsNothing);
    expect(find.byKey(const ValueKey('comment_reply_c')), findsNothing);
  });
  testWidgets('live removal hides an already-open full-screen moment', (
    tester,
  ) async {
    final repo = MemoryPosts([moment('post')]);
    await openFeed(tester, repo);
    await tapMedia(tester);
    repo.removalChanges.add(true);
    await tester.pumpAndSettle();
    expect(find.text('This moment is no longer available.'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
