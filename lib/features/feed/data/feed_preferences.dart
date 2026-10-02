import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mooddare/models/post_model.dart';
import 'feed_ranker.dart';

/// Private, account-scoped recommendation history, independent of public likes.
/// Activity is best effort: a preferences outage must never prevent posting.
class FeedPreferences {
  final FirebaseFirestore db;
  final String uid;
  final bool Function() isCurrentUser;
  FeedPreferences({
    required this.db,
    required this.uid,
    required this.isCurrentUser,
  });
  factory FeedPreferences.current() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FeedPreferences(
      db: FirebaseFirestore.instance,
      uid: uid,
      isCurrentUser: () => FirebaseAuth.instance.currentUser?.uid == uid,
    );
  }
  final Map<String, FeedSignal> history = {};
  Set<String> following = {};
  FeedOrder order = FeedOrder.forYou;
  bool ready = false;
  Future<void> _writes = Future.value();
  CollectionReference<Map<String, dynamic>> get _history =>
      db.collection('users/$uid/feedHistory');
  DocumentReference<Map<String, dynamic>> get _preference =>
      db.doc('users/$uid/preferences/feed');

  Future<void> load() async {
    if (!isCurrentUser()) return;
    final results = await Future.wait([
      _history.orderBy('updatedAt', descending: true).limit(200).get(),
      db.collection('users/$uid/following').get(),
    ]);
    final preferences = await _preference.get();
    if (!isCurrentUser()) return;
    history.clear();
    for (final doc in results.first.docs) {
      final data = doc.data();
      final date = (data['updatedAt'] as Timestamp?)?.toDate();
      if (date == null ||
          DateTime.now().difference(date).inDays >= FeedRanker.historyDays) {
        continue;
      }
      history[doc.id] = FeedSignal(
        postId: doc.id,
        authorId: data['authorId'] as String,
        moodId: data['moodId'] as String?,
        updatedAt: date,
        viewed: data['viewed'] == true,
        completed: data['completed'] == true,
        liked: data['liked'] == true,
        saved: data['saved'] == true,
        notInterested: data['notInterested'] == true,
      );
    }
    following = results.last.docs.map((d) => d.id).toSet();
    order = preferences.data()?['order'] == 'latest'
        ? FeedOrder.latest
        : FeedOrder.forYou;
    ready = true;
  }

  Future<void> record(PostModel post, FeedActivity activity) {
    if (!ready ||
        !isCurrentUser() ||
        order != FeedOrder.forYou ||
        post.authorId == uid) {
      return Future.value();
    }
    final now = DateTime.now();
    final before =
        history[post.id] ??
        FeedSignal(
          postId: post.id,
          authorId: post.authorId,
          moodId: post.moodId,
          updatedAt: now,
        );
    final after = before.withActivity(activity, now);
    if (before.viewed == after.viewed &&
        before.completed == after.completed &&
        before.liked == after.liked &&
        before.saved == after.saved &&
        before.notInterested == after.notInterested) {
      return Future.value();
    }
    history[post.id] = after;
    // Keep in-memory history bounded too, even during a long session.
    if (history.length > 200) {
      final oldest = history.values.reduce(
        (a, b) => a.updatedAt.isBefore(b.updatedAt) ? a : b,
      );
      history.remove(oldest.postId);
    }
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (!isCurrentUser()) return;
      await _history.doc(post.id).set({
        'authorId': post.authorId,
        'moodId': post.moodId,
        'viewed': after.viewed,
        'completed': after.completed,
        'liked': after.liked,
        'saved': after.saved,
        'notInterested': after.notInterested,
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          now.add(const Duration(days: FeedRanker.historyDays)),
        ),
      });
    });
    return _writes;
  }

  Future<void> setOrder(FeedOrder value) async {
    if (!isCurrentUser()) throw StateError('Account changed');
    await _preference.set({'order': value.name});
    order = value;
  }

  Future<void> reset() async {
    // Drain in-flight activity before deletion so it cannot restore cleared data.
    ready = false;
    try {
      await _writes.catchError((Object _) {});
      while (true) {
        if (!isCurrentUser()) throw StateError('Account changed');
        final page = await _history.limit(200).get();
        if (page.docs.isEmpty) break;
        final batch = db.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      history.clear();
    } finally {
      ready = true;
    }
  }
}
