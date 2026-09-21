import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late MockFirebaseStorage storage;
  late PostRepository posts;
  late SocialRepository social;
  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'alice'), signedIn: true);
    storage = MockFirebaseStorage();
    posts = PostRepository(firestore: db, auth: auth, storage: storage);
    social = SocialRepository(firestore: db, auth: auth);
  });
  test(
    'user reports save authenticated identity, reason, server time and reuse one record',
    () async {
      await social.reportUser('bob', UserReportReason.harassment);
      await social.reportUser('bob', UserReportReason.spam);
      final reports = (await db.collection('reports').get()).docs;
      expect(reports, hasLength(1));
      expect(reports.single.id, 'alice_user_bob');
      expect(reports.single.data(), {
        'userId': 'bob',
        'reporterId': 'alice',
        'reason': 'spam',
        'createdAt': isA<Timestamp>(),
      });
      for (final target in ['alice', '', 'users/bob']) {
        await expectLater(
          social.reportUser(target, UserReportReason.other),
          throwsStateError,
        );
      }
      await auth.signOut();
      await expectLater(
        social.reportUser('bob', UserReportReason.other),
        throwsStateError,
      );
    },
  );

  Future<void> seed() async {
    await db.doc('posts/p').set({
      'authorId': 'alice',
      'createdAt': Timestamp.now(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
      'mediaUrl':
          'https://firebasestorage.googleapis.com/v0/b/some-bucket/o/posts%2Falice%2Fp.jpg',
      'likedBy': [],
    });
  }

  test(
    'root and reply retries are idempotent, counts include replies, and thread deletion removes every reply',
    () async {
      await seed();
      await posts.addComment('p', 'root', ' hello ');
      await posts.addComment('p', 'root', 'ignored retry');
      expect((await posts.getComments('p').first).single.text, 'hello');
      await posts.addReply('p', 'root', 'child', ' reply ');
      await posts.addReply('p', 'root', 'child', 'ignored retry');
      expect((await posts.getReplies('p', 'root').first).single.text, 'reply');
      expect(await posts.getCommentCount('p'), 2);
      await posts.editReply('p', 'child', 'new text');
      await posts.toggleReplyLike('p', 'child');
      expect((await posts.getReplies('p', 'root').first).single.likedBy, [
        'alice',
      ]);
      await posts.toggleReplyLike('p', 'child');
      expect(
        (await posts.getReplies('p', 'root').first).single.likedBy,
        isEmpty,
      );
      await posts.editComment('p', 'root', 'root edit');
      await posts.toggleCommentLike('p', 'root');
      expect((await posts.getComments('p').first).single.likedBy, ['alice']);
      await posts.toggleCommentLike('p', 'root');
      for (var i = 0; i < 105; i++) {
        await db.doc('posts/p/replies/r$i').set({
          'parentId': 'root',
          'rootAuthorId': 'alice',
          'authorId': 'other',
          'text': 'reply',
          'createdAt': Timestamp.now(),
        });
      }
      await posts.deleteComment('p', 'root');
      expect(await posts.getCommentCount('p'), 0);
      await posts.deleteComment('p', 'root');
    },
  );
  test(
    'reply targets stay in the root thread and survive edits, retries and target deletion',
    () async {
      await seed();
      await posts.addComment('p', 'root', 'Root');
      await posts.addReply('p', 'root', 'first', 'First');
      expect(
        (await posts.getReplies('p', 'root').first).single.replyToAuthorId,
        'alice',
      );
      await db.doc('posts/p/replies/first').update({'authorId': 'bob'});
      await posts.addReply(
        'p',
        'root',
        'second',
        'Answer Bob',
        replyToId: 'first',
      );
      var answer = (await posts.getReplies('p', 'root').first).singleWhere(
        (r) => r.id == 'second',
      );
      expect(answer.parentId, 'root');
      expect(answer.replyToId, 'first');
      expect(answer.replyToAuthorId, 'bob');
      await posts.editReply('p', 'second', 'Edited answer');
      await posts.deleteReply('p', 'first');
      // A retry of an already accepted write is still idempotent.
      await posts.addReply(
        'p',
        'root',
        'second',
        'Duplicate',
        replyToId: 'first',
      );
      answer = (await posts.getReplies('p', 'root').first).single;
      expect(answer.text, 'Edited answer');
      expect(answer.replyToAuthorId, 'bob');
      await posts.addReply(
        'p',
        'root',
        'third',
        'Answer Alice',
        replyToId: 'second',
      );
      final third = (await posts.getReplies('p', 'root').first).singleWhere(
        (r) => r.id == 'third',
      );
      expect(third.parentId, 'root');
      expect(third.replyToAuthorId, 'alice');
      await posts.deleteComment('p', 'root');
      expect(await posts.getCommentCount('p'), 0);
    },
  );

  test(
    'reply targets must exist in the selected thread of the selected post',
    () async {
      await seed();
      await posts.addComment('p', 'root', 'Root');
      await posts.addComment('p', 'other-root', 'Other');
      await posts.addReply('p', 'other-root', 'other', 'Other thread');
      await db.doc('posts/elsewhere/replies/external').set({
        'parentId': 'root',
        'authorId': 'bob',
      });
      for (final target in ['missing', 'other', 'external']) {
        await expectLater(
          posts.addReply('p', 'root', 'bad', 'Wrong target', replyToId: target),
          throwsStateError,
        );
        expect((await db.doc('posts/p/replies/bad').get()).exists, false);
      }
    },
  );

  test(
    'explicit like intent is idempotent and preserves other users for comments and replies',
    () async {
      await seed();
      await posts.addComment('p', 'root', 'Root');
      await posts.addReply('p', 'root', 'child', 'Reply');
      for (final reply in [false, true]) {
        final path = reply ? 'posts/p/replies/child' : 'posts/p/comments/root';
        await db.doc(path).update({
          'likedBy': ['other', 'alice'],
        });
        Future<void> setLike(bool value) => reply
            ? posts.toggleReplyLike('p', 'child', liked: value)
            : posts.toggleCommentLike('p', 'root', liked: value);
        // Already liked elsewhere: a requested like must never toggle it off.
        await setLike(true);
        await setLike(true);
        expect((await db.doc(path).get()).data()!['likedBy'], [
          'other',
          'alice',
        ]);
        await setLike(false);
        await setLike(false);
        expect((await db.doc(path).get()).data()!['likedBy'], ['other']);
      }
    },
  );

  test(
    'reply validation rejects empty/long drafts, missing/deleting roots and unauthorized edits',
    () async {
      await seed();
      await posts.addComment('p', 'root', 'hello');
      for (final value in ['', '  ', 'x' * 501]) {
        await expectLater(
          posts.addReply('p', 'root', 'bad', value),
          throwsFormatException,
        );
        await expectLater(
          posts.editReply('p', 'bad', value),
          throwsFormatException,
        );
        await expectLater(
          posts.addComment('p', 'bad', value),
          throwsFormatException,
        );
        await expectLater(
          posts.editComment('p', 'root', value),
          throwsFormatException,
        );
      }
      await expectLater(
        posts.addReply('p', 'missing', 'bad', 'text'),
        throwsStateError,
      );
      await posts.addReply('p', 'root', 'child', 'text');
      await db.doc('posts/p/replies/child').update({'authorId': 'other'});
      await expectLater(
        posts.editReply('p', 'child', 'edited'),
        throwsStateError,
      );
      await expectLater(
        posts.toggleReplyLike('p', 'missing'),
        throwsStateError,
      );
      await db.doc('posts/p/comments/root').update({'deleting': true});
      await expectLater(
        posts.addReply('p', 'root', 'bad', 'text'),
        throwsStateError,
      );
      await posts.deleteReply('p', 'child');
      expect((await db.doc('posts/p/replies/child').get()).exists, false);
      await auth.signOut();
      await expectLater(
        posts.addReply('p', 'root', 'bad', 'text'),
        throwsStateError,
      );
      await expectLater(posts.toggleReplyLike('p', 'child'), throwsStateError);
      await expectLater(
        posts.addComment('p', 'root', 'text'),
        throwsStateError,
      );
    },
  );
  test(
    'paired follows are idempotent; blocking removes both directions; account cleanup handles multiple pages',
    () async {
      await social.setFollowing('bob', true);
      await social.setFollowing('bob', true);
      expect(await social.connections('alice', followers: false).first, {
        'bob',
      });
      expect(await social.connections('bob', followers: true).first, {'alice'});
      await social.setFollowing('bob', false);
      await social.setFollowing('bob', false);
      expect(await social.connections('bob', followers: true).first, isEmpty);
      await social.setFollowing('bob', true);
      await db.doc('users/bob/following/alice').set({
        'createdAt': Timestamp.now(),
      });
      await db.doc('users/alice/followers/bob').set({
        'createdAt': Timestamp.now(),
      });
      await posts.blockAuthor('bob');
      expect(await posts.blockedAuthors().first, {'bob'});
      for (final uid in ['alice', 'bob']) {
        expect(await social.connections(uid, followers: true).first, isEmpty);
        expect(await social.connections(uid, followers: false).first, isEmpty);
      }
      await posts.unblockAuthor('bob');
      expect(await posts.blockedAuthors().first, isEmpty);
      for (var i = 0; i < 105; i++) {
        await social.setFollowing('u$i', true);
      }
      await social.removeConnections('alice');
      expect(
        await social.connections('alice', followers: false).first,
        isEmpty,
      );
      expect(await social.connections('u104', followers: true).first, isEmpty);
      await expectLater(social.setFollowing('alice', true), throwsStateError);
      await expectLater(social.block('alice'), throwsStateError);
      await auth.signOut();
      await expectLater(social.setFollowing('bob', true), throwsStateError);
      await expectLater(social.block('bob'), throwsStateError);
    },
  );
  test(
    'people searches can load more than a Firestore whereIn batch, sort and omit deleted accounts',
    () async {
      for (var i = 0; i < 65; i++) {
        await db.doc('users/u$i').set({
          'username': 'user${i.toString().padLeft(2, '0')}',
        });
      }
      final people = await social.people({
        ...List.generate(65, (i) => 'u$i'),
        'deleted',
      });
      expect(people.length, 65);
      expect(people.first.id, 'u0');
      expect(people.last.id, 'u64');
      expect(await social.people({}), isEmpty);
    },
  );
  test(
    'post creation validates media, keeps mood metadata, and retries do not overwrite an existing moment',
    () async {
      final directory = await Directory.systemTemp.createTemp('post-test-');
      try {
        final file = await File(
          '${directory.path}/photo.jpg',
        ).writeAsBytes([1, 2, 3]);
        Future<void> create({
          String text = 'Dare',
          String type = 'image',
          String? moodId = 'happy',
          String? moodName = 'Happy',
        }) => posts.createPost(
          dareText: text,
          mediaFile: file,
          mediaType: type,
          postId: 'p',
          moodId: moodId,
          moodName: moodName,
        );
        await expectLater(create(text: ''), throwsFormatException);
        await expectLater(create(type: 'audio'), throwsFormatException);
        await expectLater(create(moodName: null), throwsFormatException);
        await create();
        await create(text: 'Retry changed draft');
        final post = (await posts.getUserPosts('alice').first).single;
        expect(post.dareText, 'Dare');
        expect(post.moodName, 'Happy');
        expect((await posts.getPosts(moodId: 'happy').first).length, 1);
        await posts.toggleLike('p', 'alice');
        expect(await posts.getPostLikerIds('p'), ['alice']);
        await posts.toggleLike('p', 'alice');
        expect(await posts.getPostLikerIds('p'), isEmpty);
        await expectLater(posts.toggleLike('p', 'other'), throwsStateError);
        expect(await posts.getUserStats('alice'), {
          'daresCompleted': 1,
          'totalLikes': 0,
        });
        await posts.reportPost('p');
        expect((await db.doc('reports/alice_p').get()).exists, true);
        expect(await posts.getAuthor('missing'), isNull);
        await posts.addComment('p', 'root', 'hello');
        await posts.addReply('p', 'root', 'reply', 'hello');
        await posts.deletePost('p', 'ignored-untrusted-url');
        expect((await db.doc('posts/p').get()).exists, false);
        expect(await posts.getCommentCount('p'), 0);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
