import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mooddare/models/user_model.dart';

class SocialRepository {
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  SocialRepository({this.firestore, this.auth});
  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;
  String? get currentUserId => (auth ?? FirebaseAuth.instance).currentUser?.uid;

  Stream<Set<String>> connections(String uid, {required bool followers}) => _db
      .collection('users')
      .doc(uid)
      .collection(followers ? 'followers' : 'following')
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toSet());

  Stream<Set<String>> blocked() {
    final uid = currentUserId;
    if (uid == null) return Stream.value({});
    return _db
        .collection('users/$uid/blocked')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  Future<List<UserModel>> people(Set<String> ids) async {
    final users = <UserModel>[];
    final list = ids.toList();
    for (var offset = 0; offset < list.length; offset += 30) {
      final docs = await _db
          .collection('users')
          .where(
            FieldPath.documentId,
            whereIn: list.skip(offset).take(30).toList(),
          )
          .get();
      users.addAll(docs.docs.map(UserModel.fromFirestore));
    }
    users.sort(
      (a, b) => (a.username ?? '').toLowerCase().compareTo(
        (b.username ?? '').toLowerCase(),
      ),
    );
    return users;
  }

  Future<void> setFollowing(String target, bool follow) async {
    final uid = currentUserId;
    if (uid == null || uid == target) throw StateError('Invalid follow.');
    final outgoing = _db.doc('users/$uid/following/$target');
    final incoming = _db.doc('users/$target/followers/$uid');
    await _db.runTransaction((tx) async {
      final exists = (await tx.get(outgoing)).exists;
      if (follow == exists) return;
      if (follow) {
        final value = {'createdAt': FieldValue.serverTimestamp()};
        tx.set(outgoing, value);
        tx.set(incoming, value);
      } else {
        tx.delete(outgoing);
        tx.delete(incoming);
      }
    });
  }

  Future<void> block(String target) async {
    final uid = currentUserId;
    if (uid == null || uid == target) throw StateError('Invalid account.');
    final batch = _db.batch();
    batch.set(_db.doc('users/$uid/blocked/$target'), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    for (final pair in [(uid, target), (target, uid)]) {
      batch.delete(_db.doc('users/${pair.$1}/following/${pair.$2}'));
      batch.delete(_db.doc('users/${pair.$2}/followers/${pair.$1}'));
    }
    await batch.commit();
  }

  Future<void> removeConnections(String uid) async {
    for (final followers in [true, false]) {
      final collection = _db.collection(
        'users/$uid/${followers ? 'followers' : 'following'}',
      );
      while (true) {
        final page = await collection.limit(100).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
          batch.delete(
            _db.doc(
              'users/${doc.id}/${followers ? 'following' : 'followers'}/$uid',
            ),
          );
        }
        await batch.commit();
      }
    }
  }
}
