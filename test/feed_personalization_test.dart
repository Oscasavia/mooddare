import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/feed/data/feed_preferences.dart';
import 'package:mooddare/features/feed/data/feed_ranker.dart';
import 'package:mooddare/models/post_model.dart';

final now = DateTime(2026, 10, 1, 12);
PostModel post(
  String id, {
  String author = 'creator',
  String mood = 'creative',
  int age = 0,
  bool deleting = false,
  bool expired = false,
}) => PostModel(
  id: id,
  moodId: mood,
  authorId: author,
  dareText: 'A dare',
  mediaType: 'image',
  mediaUrl: 'https://example.test/$id',
  createdAt: Timestamp.fromDate(now.subtract(Duration(hours: age))),
  expiresAt: Timestamp.fromDate(now.add(Duration(hours: expired ? -1 : 24))),
  likedBy: [],
  deleting: deleting,
);
FeedSignal signal(
  String id, {
  String author = 'creator',
  String mood = 'creative',
  bool liked = false,
  bool saved = false,
  bool viewed = false,
  bool rejected = false,
  DateTime? at,
}) => FeedSignal(
  postId: id,
  authorId: author,
  moodId: mood,
  updatedAt: at ?? now,
  liked: liked,
  saved: saved,
  viewed: viewed,
  notInterested: rejected,
);
List<String> rank(
  List<PostModel> posts, {
  List<FeedSignal> history = const [],
  FeedOrder order = FeedOrder.forYou,
  Set<String> blocked = const {},
  Set<String> following = const {},
}) => FeedRanker.rank(
  posts,
  now: now,
  viewerId: 'me',
  history: history,
  order: order,
  blocked: blocked,
  following: following,
).map((p) => p.id).toList();

void main() {
  test(
    'cold start is fresh and deterministic; candidate duplicates disappear',
    () {
      expect(rank([post('old', age: 10), post('new'), post('new')]), [
        'new',
        'old',
      ]);
    },
  );
  test('likes and saves learn moods across different creators', () {
    expect(
      rank(
        [
          post('fresh', mood: 'relaxed', author: 'a'),
          post('match', author: 'b', age: 2),
        ],
        history: [signal('prior', liked: true, saved: true)],
      ).first,
      'match',
    );
  });
  test(
    'latest bypasses affinity; blocked, expired, deleting and rejected stay out',
    () {
      expect(
        rank(
          [
            post('old', age: 4),
            post('new', mood: 'relaxed'),
            post('blocked', author: 'blocked'),
            post('expired', expired: true),
            post('deleting', deleting: true),
            post('rejected'),
          ],
          history: [
            signal('old', liked: true),
            signal('rejected', rejected: true),
          ],
          order: FeedOrder.latest,
          blocked: {'blocked'},
        ),
        ['new', 'old'],
      );
    },
  );
  test('old, future and own activity cannot bias ranking', () {
    for (final s in [
      signal(
        'x',
        liked: true,
        saved: true,
        at: now.subtract(const Duration(days: 31)),
      ),
      signal('x', liked: true, at: now.add(const Duration(days: 1))),
      signal('x', author: 'me', liked: true),
    ]) {
      expect(
        rank(
          [post('new', mood: 'relaxed'), post('old', age: 3)],
          history: [s],
        ).first,
        'new',
      );
    }
  });
  test('creator diversity, unseen exploration and bounded popularity', () {
    final posts = [
      for (var i = 0; i < 8; i++) post('a$i', author: 'a'),
      post('b', author: 'b', mood: 'relaxed'),
      post('c', author: 'c', mood: 'energetic'),
    ];
    final ids = rank(
      posts,
      history: [signal('prior', author: 'a', liked: true, saved: true)],
    );
    expect(ids.take(3).any((id) => id == 'b' || id == 'c'), isTrue);
    expect(ids.toSet().length, posts.length);
    expect(
      rank(
        [post('seen'), post('unseen')],
        history: [signal('seen', viewed: true)],
      ).first,
      'unseen',
    );
  });
  test(
    'repeated activity does not compound; unlike removes positive weight',
    () {
      var s = signal('x');
      for (var i = 0; i < 100; i++) {
        s = s
            .withActivity(FeedActivity.like, now)
            .withActivity(FeedActivity.completed, now);
      }
      expect(s.weight, 3.8);
      expect(s.withActivity(FeedActivity.unlike, now).weight, .8);
      expect(s.withActivity(FeedActivity.notInterested, now).weight, -5);
    },
  );

  late FakeFirebaseFirestore db;
  late FeedPreferences preferences;
  var current = true;
  setUp(() {
    db = FakeFirebaseFirestore();
    current = true;
    preferences = FeedPreferences(
      db: db,
      uid: 'me',
      isCurrentUser: () => current,
    );
  });
  test(
    'loads only this account, persists distinct actions and restores on another session',
    () async {
      await db.doc('users/me/following/friend').set({});
      await preferences.load();
      await preferences.record(post('one'), FeedActivity.like);
      await preferences.record(post('one'), FeedActivity.viewed);
      await preferences.record(post('one'), FeedActivity.unlike);
      final next = FeedPreferences(
        db: db,
        uid: 'me',
        isCurrentUser: () => true,
      );
      await next.load();
      expect(next.following, {'friend'});
      expect(next.history['one']!.viewed, isTrue);
      expect(next.history['one']!.liked, isFalse);
      final other = FeedPreferences(
        db: db,
        uid: 'other',
        isCurrentUser: () => true,
      );
      await other.load();
      expect(other.history, isEmpty);
    },
  );
  test(
    'latest pauses recording, survives restart and sign-out prevents writes',
    () async {
      await preferences.load();
      await preferences.setOrder(FeedOrder.latest);
      await preferences.record(post('one'), FeedActivity.like);
      expect(preferences.history, isEmpty);
      await preferences.load();
      expect(preferences.order, FeedOrder.latest);
      await preferences.setOrder(FeedOrder.forYou);
      current = false;
      await preferences.record(post('one'), FeedActivity.viewed);
      expect((await db.collection('users/me/feedHistory').get()).docs, isEmpty);
      await expectLater(
        preferences.setOrder(FeedOrder.latest),
        throwsStateError,
      );
      await expectLater(preferences.reset(), throwsStateError);
    },
  );
  test(
    'reset drains pending writes and erases all pages without touching public data',
    () async {
      await preferences.load();
      for (var i = 0; i < 205; i++) {
        await db.doc('users/me/feedHistory/$i').set({'anything': true});
      }
      await db.doc('users/other/feedHistory/keep').set({'anything': true});
      await db.doc('posts/public').set({
        'likedBy': ['me'],
      });
      final writing = preferences.record(post('pending'), FeedActivity.like);
      await preferences.reset();
      await writing;
      expect(preferences.history, isEmpty);
      expect((await db.collection('users/me/feedHistory').get()).docs, isEmpty);
      expect(
        (await db.doc('users/other/feedHistory/keep').get()).exists,
        isTrue,
      );
      expect((await db.doc('posts/public').get()).data()!['likedBy'], ['me']);
    },
  );
  test('memory and load bounded to 200; expired entries are ignored', () async {
    await preferences.load();
    for (var i = 0; i < 205; i++) {
      await preferences.record(post('p$i'), FeedActivity.viewed);
    }
    expect(preferences.history.length, 200);
    await preferences.load();
    expect(preferences.history.length, 200);
    await db.doc('users/me/feedHistory/expired').set({
      'authorId': 'creator',
      'updatedAt': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 31)),
      ),
    });
    await preferences.load();
    expect(preferences.history.containsKey('expired'), isFalse);
  });
}
