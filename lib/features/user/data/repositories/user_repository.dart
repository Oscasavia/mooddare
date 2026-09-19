import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mooddare/core/validation.dart';
import 'package:mooddare/models/user_model.dart';
import 'package:mooddare/models/post_model.dart';

class UserRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  UserRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance;
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<void> upsertUser(User user, {String? name}) async {
    final ref = _users.doc(user.uid);
    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(ref);
      // Preserve edits and avoid copying email addresses into public profiles.
      if (!doc.exists) {
        tx.set(ref, {
          'id': user.uid,
          'name': name ?? user.displayName,
          'photoUrl': user.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> saveProfile({
    required String username,
    String? name,
    String? bio,
    File? imageFile,
  }) async {
    final validation = validateUsername(username);
    if (validation != null) throw FormatException(validation);
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to update your profile.');
    username = username.trim();
    final lower = username.toLowerCase();
    // Compatibility with profiles created before username reservations existed.
    final legacy = await _users
        .where('username_lower', isEqualTo: lower)
        .limit(2)
        .get();
    if (legacy.docs.any((doc) => doc.id != user.uid)) {
      throw const FormatException('That username is already taken.');
    }
    final exact = await _users
        .where('username', isEqualTo: username)
        .limit(2)
        .get();
    if (exact.docs.any((doc) => doc.id != user.uid)) {
      throw const FormatException('That username is already taken.');
    }
    String? photoUrl;
    if (imageFile != null) {
      if (await imageFile.length() > 5 * 1024 * 1024) {
        throw const FormatException(
          'Choose a profile photo smaller than 5 MB.',
        );
      }
      final ref = _storage.ref('profile_pictures/${user.uid}/avatar.jpg');
      await ref.putFile(imageFile, SettableMetadata(contentType: 'image/jpeg'));
      photoUrl = await ref.getDownloadURL();
    }
    final ref = _users.doc(user.uid);
    final claim = _firestore.collection('usernames').doc(lower);
    await _firestore.runTransaction((tx) async {
      final profile = await tx.get(ref);
      final reservation = await tx.get(claim);
      final oldLower = profile.data()?['username_lower'] as String?;
      final oldClaim = oldLower != null && oldLower != lower
          ? _firestore.collection('usernames').doc(oldLower)
          : null;
      final oldReservation = oldClaim == null ? null : await tx.get(oldClaim);
      if (reservation.exists && reservation.data()?['uid'] != user.uid) {
        throw const FormatException('That username is already taken.');
      }
      tx.set(claim, {'uid': user.uid});
      tx.set(ref, {
        if (!profile.exists) 'id': user.uid,
        if (!profile.exists) 'createdAt': FieldValue.serverTimestamp(),
        'username': username,
        'username_lower': lower,
        if (name != null) 'name': name.trim(),
        if (bio != null) 'bio': bio.trim(),
        if (photoUrl != null) 'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (oldClaim != null && oldReservation?.data()?['uid'] == user.uid) {
        tx.delete(oldClaim);
      }
    });
  }

  Future<void> createUserWithUsername(User user, {required String username}) =>
      saveProfile(username: username);
  Future<void> updateUsername(String uid, String username) =>
      saveProfile(username: username);
  Future<void> updateUserProfile({
    required String uid,
    required String username,
    File? imageFile,
  }) => saveProfile(username: username, imageFile: imageFile);
  Future<DocumentSnapshot<Map<String, dynamic>>> getUser(String uid) =>
      _users.doc(uid).get();
  Future<UserModel?> getUserModel(String uid) async {
    final doc = await getUser(uid);
    return doc.exists ? UserModel.fromFirestore(doc) : null;
  }

  Future<bool> isUsernameTaken(String username) async =>
      (await _firestore
              .collection('usernames')
              .doc(username.toLowerCase())
              .get())
          .exists;
  Stream<List<PostModel>> getUserPosts(String uid) => _firestore
      .collection('posts')
      .where('authorId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(60)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(PostModel.fromFirestore).toList());
}
