import 'package:cloud_firestore/cloud_firestore.dart';

class CommentModel {
  final String id, authorId, text;
  final DateTime? createdAt, editedAt;
  final List<String> likedBy;
  final String? parentId, replyToId, replyToAuthorId;
  final bool deleting, moderationRemoved;
  const CommentModel({
    required this.id,
    required this.authorId,
    required this.text,
    this.createdAt,
    this.editedAt,
    this.likedBy = const [],
    this.parentId,
    this.replyToId,
    this.replyToAuthorId,
    this.deleting = false,
    this.moderationRemoved = false,
  });

  factory CommentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return CommentModel(
      id: doc.id,
      parentId: data['parentId'] as String?,
      replyToId: data['replyToId'] as String?,
      replyToAuthorId: data['replyToAuthorId'] as String?,
      deleting: data['deleting'] == true,
      moderationRemoved: data['moderationRemoved'] == true,
      authorId: data['authorId'] as String,
      text: data['text'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      editedAt: (data['editedAt'] as Timestamp?)?.toDate(),
      likedBy: List<String>.from(data['likedBy'] ?? []),
    );
  }
}
