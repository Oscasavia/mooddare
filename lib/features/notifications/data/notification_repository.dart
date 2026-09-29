import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/models/user_model.dart';

class ActivityNotification {
  final String id, kind, actorId;
  final String? postId, commentId, parentId, inviteId;
  final DateTime createdAt;
  final bool read;
  const ActivityNotification({
    required this.id,
    required this.kind,
    required this.actorId,
    required this.createdAt,
    this.read = false,
    this.postId,
    this.commentId,
    this.parentId,
    this.inviteId,
  });
  static const messages = {
    'follow': 'started following you',
    'postLike': 'liked your moment',
    'comment': 'commented on your moment',
    'reply': 'replied in your thread',
    'commentLike': 'liked your comment',
    'replyLike': 'liked your reply',
    'dare': 'sent you a dare',
  };
  String get message => messages[kind] ?? 'shared an update';
  bool get opensComments =>
      ['comment', 'reply', 'commentLike', 'replyLike'].contains(kind);
  static ActivityNotification? parse(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    if (d == null ||
        !messages.containsKey(d['kind']) ||
        d['actorId'] is! String ||
        d['createdAt'] is! Timestamp) {
      return null;
    }
    return ActivityNotification(
      id: doc.id,
      kind: d['kind'],
      actorId: d['actorId'],
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      read: d['read'] == true,
      postId: d['postId'] as String?,
      commentId: d['commentId'] as String?,
      parentId: d['parentId'] as String?,
      inviteId: d['inviteId'] as String?,
    );
  }
}

class NotificationRepository {
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  NotificationRepository({this.firestore, this.auth});
  FirebaseFirestore get db => firestore ?? FirebaseFirestore.instance;
  String? get uid => auth != null
      ? auth!.currentUser?.uid
      : (Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid);
  Stream<List<ActivityNotification>> watch({int limit = 40}) {
    final user = uid;
    if (user == null) return Stream.value([]);
    return db
        .collection('users/$user/notifications')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (s) => s.docs
              .map(ActivityNotification.parse)
              .whereType<ActivityNotification>()
              .toList(),
        );
  }

  Stream<bool> unread() {
    final user = uid;
    if (user == null) return Stream.value(false);
    return db
        .collection('users/$user/notifications')
        .where('read', isEqualTo: false)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty);
  }

  Stream<Map<String, bool>> preferences() {
    final user = uid;
    if (user == null) return Stream.value({});
    return db
        .doc('users/$user/preferences/notifications')
        .snapshots()
        .map(
          (d) => {
            for (final key in ['follows', 'likes', 'comments', 'dares', 'push'])
              key: d.data()?[key] != false,
          },
        );
  }

  Future<void> setPreference(String key, bool value) {
    if (!['follows', 'likes', 'comments', 'dares', 'push'].contains(key) ||
        uid == null) {
      throw StateError('Invalid preference.');
    }
    return db.doc('users/$uid/preferences/notifications').set({
      key: value,
    }, SetOptions(merge: true));
  }

  Future<void> markRead(String id) =>
      db.doc('users/$uid/notifications/$id').update({'read': true});
  Future<void> markAllRead() async {
    final user = uid;
    if (user == null) return;
    // Snapshot a cutoff so new arrivals are never swallowed by this action.
    final cutoff = DateTime.now();
    while (true) {
      final page = await db
          .collection('users/$user/notifications')
          .where('read', isEqualTo: false)
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(cutoff))
          .limit(200)
          .get();
      final docs = page.docs
          .where(
            (d) =>
                (d.data()['createdAt'] as Timestamp).toDate().isBefore(cutoff),
          )
          .toList();
      if (docs.isEmpty) return;
      final batch = db.batch();
      for (final d in docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
      if (page.docs.length < 200) return;
    }
  }

  Future<UserModel?> actor(String id) async {
    final d = await db.doc('users/$id').get();
    return d.exists ? UserModel.fromFirestore(d) : null;
  }

  Future<ActivityNotification?> get(String id) async {
    if (uid == null || id.contains('/')) return null;
    return ActivityNotification.parse(
      await db.doc('users/$uid/notifications/$id').get(),
    );
  }

  Future<PostModel?> post(ActivityNotification n) async {
    if (n.postId == null) return null;
    final doc = await db.doc('posts/${n.postId}').get();
    if (!doc.exists || doc.data()?['deleting'] == true) return null;
    final post = PostModel.fromFirestore(doc);
    if (n.commentId != null) {
      final type = n.kind == 'reply' || n.kind == 'replyLike'
          ? 'replies'
          : 'comments';
      final comment = await doc.reference
          .collection(type)
          .doc(n.commentId)
          .get();
      if (!comment.exists || comment.data()?['deleting'] == true) return null;
    }
    return post;
  }

  Future<bool> inviteAvailable(ActivityNotification n) async {
    if (n.inviteId == null) return false;
    final d = await db.doc('dareInvites/${n.inviteId}').get();
    return d.exists && d.data()?['recipientId'] == uid;
  }
}
