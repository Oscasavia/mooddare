import 'dart:io';
import 'package:mooddare/models/comment_model.dart';
import 'package:mooddare/features/dares/data/repositories/dares_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mooddare/models/post_model.dart';
import 'package:mooddare/models/user_model.dart';
import 'package:uuid/uuid.dart';

class PostRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  PostRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  Future<UserModel?> getAuthor(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.exists ? UserModel.fromFirestore(doc) : null;
  }

  Future<void> createPost({
    required String dareText,
    required File mediaFile,
    required String mediaType,
    String? postId,
    String? moodId,
    String? moodName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before posting.');
    if (!['image', 'video'].contains(mediaType) ||
        dareText.trim().isEmpty ||
        dareText.length > 500) {
      throw const FormatException('Invalid capture.');
    }
    if ((moodId == null) != (moodName == null) ||
        (moodId != null && (moodId.isEmpty || moodId.length > 128)) ||
        (moodName != null && (moodName.isEmpty || moodName.length > 80))) {
      throw const FormatException('Invalid mood metadata.');
    }
    if (!await mediaFile.exists() ||
        await mediaFile.length() > 30 * 1024 * 1024) {
      throw const FormatException('Choose a capture smaller than 30 MB.');
    }
    final id = postId ?? const Uuid().v4();
    final doc = _firestore.collection('posts').doc(id);
    // Retrying an acknowledged or ambiguously completed post never duplicates it.
    if ((await doc.get()).exists) return;
    final path =
        'posts/${user.uid}/$id.${mediaType == 'image' ? 'jpg' : 'mp4'}';
    final ref = _storage.ref(path);
    await ref.putFile(
      mediaFile,
      SettableMetadata(
        contentType: mediaType == 'image' ? 'image/jpeg' : 'video/mp4',
      ),
    );
    final url = await ref.getDownloadURL();
    await doc.set({
      'dareText': dareText.trim(),
      if (moodId != null && moodName != null) ...{
        'moodId': moodId,
        'moodName': moodName,
      },
      'mediaUrl': url,
      'mediaPath': path,
      'mediaType': mediaType,
      'authorId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
      'likedBy': <String>[],
    });
  }

  Future<Map<String, String>> getMoodOptions() async {
    final catalog = await DaresRepository(firestore: _firestore).getCatalog();
    return {
      for (final mood in catalog.moods)
        if (mood.isAvailable) mood.id: mood.name,
    };
  }

  Stream<List<PostModel>> getPosts({String? moodId}) {
    Query<Map<String, dynamic>> query = _firestore.collection('posts');
    if (moodId != null) query = query.where('moodId', isEqualTo: moodId);
    return query
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt', descending: true)
        .limit(60)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(PostModel.fromFirestore).toList());
  }

  Stream<List<PostModel>> getUserPosts(String uid) => _firestore
      .collection('posts')
      .where('authorId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(60)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(PostModel.fromFirestore).toList());

  Future<Map<String, int>> getUserStats(String uid) async {
    final snapshot = await _firestore
        .collection('posts')
        .where('authorId', isEqualTo: uid)
        .get();
    return {
      'daresCompleted': snapshot.docs.length,
      'totalLikes': snapshot.docs.fold(
        0,
        (total, doc) => total + ((doc.data()['likedBy'] as List?)?.length ?? 0),
      ),
    };
  }

  Stream<List<CommentModel>> getComments(String postId) => _firestore
      .collection('posts')
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(CommentModel.fromFirestore).toList(),
      );

  // Aggregate over every comment, not just the latest 100 shown in the sheet.
  Future<int> getCommentCount(String postId) async =>
      (await _firestore
              .collection('posts')
              .doc(postId)
              .collection('comments')
              .count()
              .get())
          .count ??
      0;

  Future<void> editComment(String postId, String commentId, String text) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Sign in to edit your comment.');
    text = text.trim();
    if (text.isEmpty || text.length > 500) {
      throw const FormatException('Write a comment of 1–500 characters.');
    }
    final ref = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);
    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists || doc.data()?['authorId'] != uid) {
        throw StateError('You can only edit your own comments.');
      }
      tx.update(ref, {'text': text, 'editedAt': FieldValue.serverTimestamp()});
    });
  }

  Future<void> toggleCommentLike(String postId, String commentId) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Sign in to like a comment.');
    final ref = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);
    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) throw StateError('This comment is no longer available.');
      final likes = List<String>.from(doc.data()?['likedBy'] ?? []);
      tx.update(ref, {
        'likedBy': likes.contains(uid)
            ? FieldValue.arrayRemove([uid])
            : FieldValue.arrayUnion([uid]),
      });
    });
  }

  Future<void> addComment(String postId, String commentId, String text) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Sign in to comment.');
    text = text.trim();
    if (text.isEmpty || text.length > 500) {
      throw const FormatException('Write a comment of 1–500 characters.');
    }
    final post = _firestore.collection('posts').doc(postId);
    final comment = post.collection('comments').doc(commentId);
    // Stable IDs make retries safe even if the first acknowledgement was lost.
    await _firestore.runTransaction((tx) async {
      final parent = await tx.get(post);
      final existing = await tx.get(comment);
      if (!parent.exists) {
        throw StateError('This moment is no longer available.');
      }
      if (existing.exists) return;
      tx.set(comment, {
        'authorId': uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> deleteComment(String postId, String commentId) => _firestore
      .collection('posts')
      .doc(postId)
      .collection('comments')
      .doc(commentId)
      .delete();

  Future<void> toggleLike(String postId, String userId) async {
    if (_auth.currentUser?.uid != userId) {
      throw StateError('Sign in to like a dare.');
    }
    final ref = _firestore.collection('posts').doc(postId);
    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) throw StateError('This dare is no longer available.');
      final likes = List<String>.from(doc.data()?['likedBy'] ?? []);
      tx.update(ref, {
        'likedBy': likes.contains(userId)
            ? FieldValue.arrayRemove([userId])
            : FieldValue.arrayUnion([userId]),
      });
    });
  }

  Future<void> deletePost(String postId, String mediaUrl) async {
    final ref = _firestore.collection('posts').doc(postId);
    final doc = await ref.get();
    if (!doc.exists) return;
    if (doc.data()?['authorId'] != _auth.currentUser?.uid) {
      throw StateError('You can only delete your own posts.');
    }
    // Use the stored URL, never an arbitrary URL supplied by the caller.
    try {
      await _storage.refFromURL(doc.data()!['mediaUrl'] as String).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
    // Firestore does not cascade deletion to subcollections.
    while (true) {
      final page = await ref.collection('comments').limit(100).get();
      if (page.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final comment in page.docs) {
        batch.delete(comment.reference);
      }
      await batch.commit();
    }
    await ref.delete();
  }

  Stream<Set<String>> blockedAuthors() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(<String>{});
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('blocked')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  Future<void> blockAuthor(String authorId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid == authorId) throw StateError('Invalid account');
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('blocked')
        .doc(authorId)
        .set({'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> unblockAuthor(String authorId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('blocked')
        .doc(authorId)
        .delete();
  }

  Future<void> reportPost(String postId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to report a post.');
    await _firestore.collection('reports').doc('${uid}_$postId').set({
      'postId': postId,
      'reporterId': uid,
      'reason': 'inappropriate',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
