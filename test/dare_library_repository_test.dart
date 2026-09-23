import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/dares/data/repositories/dare_library_repository.dart';
import 'package:mooddare/features/profile/data/social_repository.dart';

const prompt = DarePrompt(
  text: 'Capture something that made you smile today.',
  moodId: 'happy',
  moodName: 'Happy',
);
void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth alice, bob;
  late DareLibraryRepository a, b;
  late SocialRepository sa, sb;
  setUp(() async {
    db = FakeFirebaseFirestore();
    alice = MockFirebaseAuth(mockUser: MockUser(uid: 'alice'), signedIn: true);
    bob = MockFirebaseAuth(mockUser: MockUser(uid: 'bob'), signedIn: true);
    a = DareLibraryRepository(firestore: db, auth: alice);
    b = DareLibraryRepository(firestore: db, auth: bob);
    sa = SocialRepository(firestore: db, auth: alice);
    sb = SocialRepository(firestore: db, auth: bob);
    for (final id in ['alice', 'bob', 'charlie']) {
      await db.doc('users/$id').set({'id': id, 'username': id});
    }
  });
  Future<void> mutual() async {
    await sa.setFollowing('bob', true);
    await sb.setFollowing('alice', true);
  }

  test(
    'prompt validation, stable keys, nullable legacy mood and round trip',
    () {
      expect(prompt.isValid, isTrue);
      expect(DarePrompt.fromMap(prompt.toMap()).key, prompt.key);
      expect(
        const DarePrompt(text: ' A dare ').key,
        const DarePrompt(text: 'A dare').key,
      );
      expect(
        const DarePrompt(
          text: 'A dare',
          moodId: 'other',
          moodName: 'Other',
        ).key,
        isNot(const DarePrompt(text: 'A dare').key),
      );
      for (final value in [
        const DarePrompt(text: ''),
        const DarePrompt(text: '  '),
        DarePrompt(text: 'a' * 501),
        const DarePrompt(text: 'Dare', moodId: 'missing-name'),
        const DarePrompt(text: 'Dare', moodName: 'missing-id'),
        const DarePrompt(text: 'Dare', moodId: 'a/b', moodName: 'Name'),
      ]) {
        expect(value.isValid, isFalse);
      }
      expect(const DarePrompt(text: 'Old dare').toMap(), {
        'dareText': 'Old dare',
      });
    },
  );
  test(
    'saving is private by path, idempotent and independent of source posts',
    () async {
      await a.save(prompt);
      final first = (await db.collection('users/alice/savedDares').get())
          .docs
          .single
          .data();
      await a.save(prompt);
      expect((await a.saved().first).length, 1);
      expect(await b.saved().first, isEmpty);
      expect(
        (await db.collection('users/alice/savedDares').get()).docs.single
            .data(),
        first,
      );
      expect(
        first.keys,
        unorderedEquals(['dareText', 'moodId', 'moodName', 'createdAt']),
      );
      expect(await a.isSaved(prompt).first, isTrue);
      final restored = DareLibraryRepository(firestore: db, auth: alice);
      expect((await restored.saved().first).single.prompt.text, prompt.text);
      await restored.unsave(prompt);
      expect(await a.isSaved(prompt).first, isFalse);
      await expectLater(
        a.save(const DarePrompt(text: ' ')),
        throwsArgumentError,
      );
    },
  );
  test(
    'sending requires mutual following and does not send to self or invalid ids',
    () async {
      for (final id in ['alice', '', 'a/b']) {
        await expectLater(a.send(prompt, id), throwsArgumentError);
      }
      await expectLater(a.send(prompt, 'bob'), throwsStateError);
      await sa.setFollowing('bob', true);
      await expectLater(a.send(prompt, 'bob'), throwsStateError);
      await sb.setFollowing('alice', true);
      expect(await a.send(prompt, 'bob'), isTrue);
      expect(await a.send(prompt, 'bob'), isFalse);
      expect(await a.inbox().first, isEmpty);
      final received = (await b.inbox().first).single;
      expect(received.senderId, 'alice');
      expect(received.prompt.toMap(), prompt.toMap());
      expect(received.opened, isFalse);
      expect(await b.hasUnread().first, isTrue);
      await b.markOpened(received.id);
      expect(await b.hasUnread().first, isFalse);
      await b.save(received.prompt);
      await b.dismiss(received.id);
      expect(await b.inbox().first, isEmpty);
      expect((await b.saved().first).single.prompt.text, prompt.text);
      expect(await a.send(prompt, 'bob'), isTrue);
    },
  );
  test(
    'unfollow between opening picker and sending rejects stale selection',
    () async {
      await mutual();
      await sb.setFollowing('alice', false);
      await expectLater(a.send(prompt, 'bob'), throwsStateError);
      expect(await b.inbox().first, isEmpty);
    },
  );
  test(
    'blocked recipients are excluded even if stale follow documents exist',
    () async {
      await mutual();
      await db.doc('users/alice/blocked/bob').set({
        'createdAt': Timestamp.now(),
      });
      await expectLater(a.send(prompt, 'bob'), throwsStateError);
      expect(await sa.mutuals().first, isEmpty);
    },
  );
  test('mutual stream reacts to follows, unfollows and blocks', () async {
    final events = <Set<String>>[];
    final sub = sa.mutuals().listen(events.add);
    await Future<void>.delayed(Duration.zero);
    expect(events.last, isEmpty);
    await mutual();
    await Future<void>.delayed(Duration.zero);
    expect(events.last, {'bob'});
    await sa.block('bob');
    await Future<void>.delayed(Duration.zero);
    expect(events.last, isEmpty);
    await sub.cancel();
  });
  test(
    'signed out repositories return empty collections and prevent mutations',
    () async {
      await alice.signOut();
      expect(await a.saved().first, isEmpty);
      expect(await a.inbox().first, isEmpty);
      expect(await a.hasUnread().first, isFalse);
      expect(await a.isSaved(prompt).first, isFalse);
      expect(await sa.mutuals().first, isEmpty);
      await expectLater(a.save(prompt), throwsStateError);
      await expectLater(a.send(prompt, 'bob'), throwsStateError);
    },
  );
  test(
    'paging returns newest snapshots without silently dropping older saved dares',
    () async {
      for (var i = 0; i < 45; i++) {
        await db.doc('users/alice/savedDares/d$i').set({
          'dareText': 'Dare $i',
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(i),
        });
      }
      expect((await a.saved().first).length, 40);
      expect((await a.saved(limit: 80).first).length, 45);
      expect((await a.saved().first).first.prompt.text, 'Dare 44');
    },
  );
  test(
    'account cleanup removes saved dares and both directions of invitations, preserving others',
    () async {
      await mutual();
      await a.send(prompt, 'bob');
      await b.send(prompt, 'alice');
      for (var i = 0; i < 105; i++) {
        await a.save(DarePrompt(text: 'Saved $i'));
      }
      await b.save(prompt);
      await a.removeAccountData('alice');
      expect(await a.saved(limit: 200).first, isEmpty);
      expect(await a.inbox().first, isEmpty);
      expect(await b.inbox().first, isEmpty);
      expect(await b.saved().first, hasLength(1));
    },
  );
}
