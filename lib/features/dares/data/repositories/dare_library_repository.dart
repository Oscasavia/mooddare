import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:mooddare/models/post_model.dart';

/// A prompt snapshot, independent of the lifetime or media of a post.
class DarePrompt {
  final String text;
  final String? moodId, moodName;
  const DarePrompt({required this.text, this.moodId, this.moodName});
  factory DarePrompt.fromPost(PostModel post) => DarePrompt(
    text: post.dareText,
    moodId: post.moodId,
    moodName: post.moodName,
  );
  factory DarePrompt.fromMap(Map<String, dynamic> data) => DarePrompt(
    text: data['dareText'] as String,
    moodId: data['moodId'] as String?,
    moodName: data['moodName'] as String?,
  );
  String get key =>
      const Uuid().v5(Namespace.url.value, jsonEncode([moodId, text.trim()]));
  bool get isValid =>
      text.trim().isNotEmpty &&
      text.trim().length <= 500 &&
      ((moodId == null && moodName == null) ||
          (moodId != null &&
              moodId!.isNotEmpty &&
              moodId!.length <= 128 &&
              !moodId!.contains('/') &&
              moodName != null &&
              moodName!.trim().isNotEmpty &&
              moodName!.length <= 80));
  Map<String, dynamic> toMap() => {
    'dareText': text.trim(),
    if (moodId != null) 'moodId': moodId,
    if (moodName != null) 'moodName': moodName,
  };
}

class DareEntry {
  final String id;
  final DarePrompt prompt;
  final String? senderId;
  final bool opened;
  const DareEntry({
    required this.id,
    required this.prompt,
    this.senderId,
    this.opened = false,
  });
  factory DareEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return DareEntry(
      id: doc.id,
      prompt: DarePrompt.fromMap(data),
      senderId: data['senderId'] as String?,
      opened: data['opened'] == true,
    );
  }
}

class DareLibraryRepository {
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  DareLibraryRepository({this.firestore, this.auth});
  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;
  String? get currentUserId {
    // Also permits previews/tests before Firebase is initialized.
    if (auth == null && Firebase.apps.isEmpty) return null;
    return (auth ?? FirebaseAuth.instance).currentUser?.uid;
  }

  String get _uid => currentUserId ?? (throw StateError('Please sign in.'));
  Stream<bool> isSaved(DarePrompt prompt) {
    final uid = currentUserId;
    if (uid == null) return Stream.value(false);
    return _db
        .doc('users/$uid/savedDares/${prompt.key}')
        .snapshots()
        .map((d) => d.exists);
  }

  Future<void> save(DarePrompt prompt) async {
    if (!prompt.isValid) throw ArgumentError('Invalid dare.');
    final ref = _db.doc('users/$_uid/savedDares/${prompt.key}');
    await _db.runTransaction((tx) async {
      if (!(await tx.get(ref)).exists) {
        tx.set(ref, {
          ...prompt.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> unsave(DarePrompt prompt) =>
      _db.doc('users/$_uid/savedDares/${prompt.key}').delete();
  Stream<List<DareEntry>> saved({int limit = 40}) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('users/$uid/savedDares')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(DareEntry.fromDoc).toList());
  }

  Stream<List<DareEntry>> inbox({int limit = 40}) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('dareInvites')
        .where('recipientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(DareEntry.fromDoc).toList());
  }

  Stream<bool> hasUnread() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(false);
    return _db
        .collection('dareInvites')
        .where('recipientId', isEqualTo: uid)
        .where('opened', isEqualTo: false)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty);
  }

  /// One pending copy per sender, recipient and prompt. Repeated taps are idempotent.
  Future<bool> send(DarePrompt prompt, String recipient) async {
    final uid = _uid;
    if (!prompt.isValid ||
        recipient.isEmpty ||
        recipient.contains('/') ||
        recipient == uid) {
      throw ArgumentError('Invalid recipient or dare.');
    }
    final id = const Uuid().v5(
      Namespace.url.value,
      jsonEncode([uid, recipient, prompt.key]),
    );
    final ref = _db.doc('dareInvites/$id');
    return _db.runTransaction((tx) async {
      // Rules independently enforce these relationships at commit time.
      final forward = await tx.get(_db.doc('users/$uid/following/$recipient'));
      final reverse = await tx.get(_db.doc('users/$recipient/following/$uid'));
      final blocked = await tx.get(_db.doc('users/$uid/blocked/$recipient'));
      if (!forward.exists || !reverse.exists || blocked.exists) {
        throw StateError('You must follow each other to send a dare.');
      }
      if ((await tx.get(ref)).exists) return false;
      tx.set(ref, {
        ...prompt.toMap(),
        'senderId': uid,
        'recipientId': recipient,
        'opened': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  Future<void> markOpened(String id) =>
      _db.collection('dareInvites').doc(id).update({'opened': true});
  Future<void> dismiss(String id) =>
      _db.collection('dareInvites').doc(id).delete();

  Future<void> removeAccountData(String uid) async {
    Future<void> clear(Query<Map<String, dynamic>> query) async {
      while (true) {
        final page = await query.limit(100).get();
        if (page.docs.isEmpty) return;
        final batch = _db.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }

    await clear(_db.collection('users/$uid/savedDares'));
    for (final field in ['senderId', 'recipientId']) {
      await clear(_db.collection('dareInvites').where(field, isEqualTo: uid));
    }
  }
}
