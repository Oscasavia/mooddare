import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mooddare/features/feed/data/repositories/post_repository.dart';

/// Client cleanup is retryable while the auth account still exists. Production
/// should additionally run trusted server cleanup for interrupted deletions.
class AccountRepository {
  Future<void> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    final token = await user.getIdTokenResult(true);
    final signedIn = token.authTime;
    if (!user.isAnonymous &&
        (signedIn == null ||
            DateTime.now().difference(signedIn) > const Duration(minutes: 4))) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    final db = FirebaseFirestore.instance;
    final posts = PostRepository();
    while (true) {
      final page = await db
          .collection('posts')
          .where('authorId', isEqualTo: user.uid)
          .limit(50)
          .get();
      if (page.docs.isEmpty) break;
      for (final doc in page.docs) {
        await posts.deletePost(doc.id, doc.data()['mediaUrl'] as String);
      }
    }
    while (true) {
      final page = await db
          .collection('posts')
          .where('likedBy', arrayContains: user.uid)
          .limit(100)
          .get();
      if (page.docs.isEmpty) break;
      final batch = db.batch();
      for (final doc in page.docs) {
        batch.update(doc.reference, {
          'likedBy': FieldValue.arrayRemove([user.uid]),
        });
      }
      await batch.commit();
    }
    while (true) {
      final comments = await db
          .collectionGroup('comments')
          .where('authorId', isEqualTo: user.uid)
          .limit(100)
          .get();
      if (comments.docs.isEmpty) break;
      final batch = db.batch();
      for (final comment in comments.docs) {
        batch.delete(comment.reference);
      }
      await batch.commit();
    }
    final storage = FirebaseStorage.instance;
    // Remove current and legacy avatar locations, plus unfinished uploads.
    for (final folder in [
      'posts/${user.uid}',
      'profile_pictures/${user.uid}',
    ]) {
      final objects = await storage.ref(folder).listAll();
      for (final object in objects.items) {
        await object.delete();
      }
    }
    try {
      await storage.ref('profile_pictures/${user.uid}').delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
    final profile = db.collection('users').doc(user.uid);
    final data = (await profile.get()).data();
    final username = data?['username_lower'] as String?;
    final batch = db.batch();
    if (username != null) {
      final ref = db.collection('usernames').doc(username);
      if ((await ref.get()).data()?['uid'] == user.uid) batch.delete(ref);
    }
    final blocks = await profile.collection('blocked').get();
    for (final block in blocks.docs) {
      await block.reference.delete();
    }
    final reports = await db
        .collection('reports')
        .where('reporterId', isEqualTo: user.uid)
        .get();
    for (final report in reports.docs) {
      await report.reference.delete();
    }
    batch.delete(profile);
    await batch.commit();
    await user.delete();
  }
}
