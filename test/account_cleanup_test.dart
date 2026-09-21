import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/profile/data/account_repository.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';

class RecentToken implements IdTokenResult {
  @override
  DateTime? get authTime => DateTime.now();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// MockUser deliberately exposes mutable account state for tests.
// ignore: must_be_immutable
class RecentUser extends MockUser {
  RecentUser() : super(uid: 'alice', isAnonymous: false);
  bool deleted = false;
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async =>
      RecentToken();
  @override
  Future<void> delete() async {
    deleted = true;
  }
}

void main() {
  test(
    'account cleanup removes own replies, replies to own orphaned threads, follows in both directions and keeps other content',
    () async {
      final db = FakeFirebaseFirestore(), user = RecentUser();
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final storage = MockFirebaseStorage();
      final social = SocialRepository(firestore: db, auth: auth);
      await db.doc('users/alice').set({
        'id': 'alice',
        'username_lower': 'alice',
      });
      await db.doc('usernames/alice').set({'uid': 'alice'});
      await social.setFollowing('bob', true);
      await db.doc('users/bob/following/alice').set({
        'createdAt': Timestamp.now(),
      });
      await db.doc('users/alice/followers/bob').set({
        'createdAt': Timestamp.now(),
      });
      await db.doc('posts/other').set({
        'authorId': 'bob',
        'likedBy': ['alice', 'bob'],
      });
      for (final parent in ['other', 'orphan']) {
        await db.doc('posts/$parent/comments/root').set({
          'authorId': 'alice',
          'text': 'root',
        });
        await db.doc('posts/$parent/replies/r').set({
          'authorId': 'bob',
          'parentId': 'root',
          'rootAuthorId': 'alice',
          'text': 'reply',
        });
      }
      await db.doc('posts/other/comments/keep').set({
        'authorId': 'bob',
        'text': 'keep',
      });
      await db.doc('posts/other/replies/own').set({
        'authorId': 'alice',
        'parentId': 'keep',
        'rootAuthorId': 'bob',
        'text': 'mine',
      });
      await db.doc('posts/other/replies/keep').set({
        'authorId': 'bob',
        'parentId': 'keep',
        'rootAuthorId': 'bob',
        'text': 'keep',
      });
      await db.doc('users/alice/blocked/charlie').set({
        'createdAt': Timestamp.now(),
      });
      await db.doc('reports/alice_other').set({'reporterId': 'alice'});
      await AccountRepository(
        firestore: db,
        auth: auth,
        storage: storage,
      ).deleteAccount();
      expect(user.deleted, true);
      expect((await db.doc('users/alice').get()).exists, false);
      expect((await db.doc('usernames/alice').get()).exists, false);
      expect((await db.collectionGroup('following').get()).docs, isEmpty);
      expect((await db.collectionGroup('followers').get()).docs, isEmpty);
      expect(
        (await db.collectionGroup('comments').get()).docs.map((d) => d.id),
        ['keep'],
      );
      expect(
        (await db.collectionGroup('replies').get()).docs.map((d) => d.id),
        ['keep'],
      );
      expect((await db.doc('posts/other').get()).data()!['likedBy'], ['bob']);
      expect((await db.collectionGroup('blocked').get()).docs, isEmpty);
      expect((await db.collection('reports').get()).docs, isEmpty);
    },
  );
  test(
    'old authentication and signed-out callers cannot start destructive cleanup',
    () async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'alice'),
        signedIn: true,
      );
      final repo = AccountRepository(
        firestore: db,
        auth: auth,
        storage: MockFirebaseStorage(),
      );
      await db.doc('users/alice').set({'id': 'alice'});
      await expectLater(
        repo.deleteAccount(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'requires-recent-login',
          ),
        ),
      );
      expect((await db.doc('users/alice').get()).exists, true);
      await auth.signOut();
      await expectLater(repo.deleteAccount(), throwsStateError);
    },
  );
}
