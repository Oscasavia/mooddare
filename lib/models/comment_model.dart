import 'package:cloud_firestore/cloud_firestore.dart';

class CommentModel {
  final String id, authorId, text;
  final DateTime? createdAt, editedAt;
  final List<String> likedBy;
  final String? parentId;
  final bool deleting;
  const CommentModel({
    required this.id,
    required this.authorId,
    required this.text,
    this.createdAt,
    this.editedAt,
    this.likedBy = const [],
    this.parentId,
    this.deleting = false,
  });

  factory CommentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return CommentModel(
      id: doc.id,
      parentId: data['parentId'] as String?,
      deleting: data['deleting'] == true,
      authorId: data['authorId'] as String,
      text: data['text'] as String,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      editedAt: (data['editedAt'] as Timestamp?)?.toDate(),
      likedBy: List<String>.from(data['likedBy'] ?? []),
    );
  }
}
