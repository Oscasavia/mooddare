import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:mooddare/features/links/moment_links.dart';
import 'package:mooddare/features/links/shared_moment_screen.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';
import 'package:mooddare/features/feed/presentation/screens/post_details_screen.dart';
import 'package:mooddare/models/post_model.dart';
import 'support/moments_fakes.dart';

class LinkPosts extends MemoryPosts {
  LinkPosts() : super([]);
  PostModel? result;
  bool fail = false;
  @override
  Future<PostModel?> getSharedPost(String id) async {
    if (fail) throw StateError('offline');
    return result;
  }
}

void main() {
  test(
    'canonical shared links reject foreign hosts, paths, schemes, queries and injection',
    () {
      final url = MomentLinks.url('a-123_ABC');
      expect(url.toString(), 'https://mooddare.web.app/moment/a-123_ABC');
      expect(MomentLinks.parse(url), 'a-123_ABC');
      for (final raw in [
        'http://mooddare.web.app/moment/a',
        'https://evil.invalid/moment/a',
        'https://mooddare.web.app.evil.invalid/moment/a',
        'https://x@mooddare.web.app/moment/a',
        'https://mooddare.web.app:444/moment/a',
        'https://mooddare.web.app/admin/a',
        'https://mooddare.web.app/moment/',
        'https://mooddare.web.app/moment/a/b',
        'https://mooddare.web.app/moment/a?redirect=evil',
        'https://mooddare.web.app/moment/a#fragment',
        'https://mooddare.web.app/moment/%2F',
        'https://mooddare.web.app/moment/${'a' * 129}',
      ]) {
        expect(MomentLinks.parse(Uri.parse(raw)), isNull, reason: raw);
      }
      expect(() => MomentLinks.url('../private'), throwsFormatException);
    },
  );
  test(
    'cold-start links wait for consumption; duplicate delivery does not re-notify; later links work',
    () async {
      final incoming = StreamController<Uri>();
      final links = MomentLinks();
      var changes = 0;
      links.pending.addListener(() => changes++);
      links.start(links: incoming.stream);
      links.start(links: incoming.stream);
      incoming.add(MomentLinks.url('first'));
      await Future<void>.delayed(Duration.zero);
      expect(links.pending.value, 'first');
      expect(changes, 1);
      incoming.add(MomentLinks.url('first'));
      await Future<void>.delayed(Duration.zero);
      expect(changes, 1);
      links.pending.value = null;
      incoming.add(MomentLinks.url('second'));
      incoming.add(Uri.parse('https://evil.invalid/moment/no'));
      await Future<void>.delayed(Duration.zero);
      expect(links.pending.value, 'second');
      await links.dispose();
      await incoming.close();
    },
  );
  test(
    'shared-post lookup checks server state, current account, blocks and removed/deleting records',
    () async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'viewer'),
        signedIn: true,
      );
      final repo = PostRepository(
        firestore: db,
        auth: auth,
        storage: MockFirebaseStorage(),
      );
      final data = {
        'authorId': 'author',
        'dareText': 'Smile',
        'mediaType': 'image',
        'mediaUrl': 'https://example.invalid/photo',
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.fromMillisecondsSinceEpoch(1),
        'likedBy': <String>[],
      };
      await db.doc('posts/one').set(data);
      expect(
        (await repo.getSharedPost('one'))?.id,
        'one',
      ); // Leaving the feed does not remove a profile moment.
      await db.doc('users/viewer/blocked/author').set({});
      expect(await repo.getSharedPost('one'), isNull);
      await db.doc('users/viewer/blocked/author').delete();
      await db.doc('moderationPosts/one').set({});
      expect(await repo.getSharedPost('one'), isNull);
      await db.doc('moderationPosts/one').delete();
      await db.doc('posts/one').update({'deleting': true});
      expect(await repo.getSharedPost('one'), isNull);
      await db.doc('posts/one').delete();
      expect(await repo.getSharedPost('one'), isNull);
      expect(await repo.getSharedPost('../private'), isNull);
      await auth.signOut();
      expect(await repo.getSharedPost('one'), isNull);
    },
  );
  testWidgets(
    'missing shared moments show a helpful state; network failure retries into the existing viewer',
    (tester) async {
      final repo = LinkPosts();
      await tester.pumpWidget(
        MaterialApp(
          home: SharedMomentScreen(postId: 'one', repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Moment unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: SharedMomentScreen(postId: 'one', repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not open this moment'), findsOneWidget);
      repo.fail = false;
      repo.result = moment('one');
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(PostDetailsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
