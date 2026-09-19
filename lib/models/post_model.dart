import 'package:cloud_firestore/cloud_firestore.dart';

class PostModel {
  final String id;
  final String dareText;
  final String mediaUrl;
  final String mediaType;
  final String authorId;
  final Timestamp createdAt;
  final Timestamp expiresAt;
  final List<String> likedBy; // Changed from reactions map

  PostModel({
    required this.id,
    required this.dareText,
    required this.mediaUrl,
    required this.mediaType,
    required this.authorId,
    required this.createdAt,
    required this.expiresAt,
    required this.likedBy,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PostModel(
      id: doc.id,
      dareText: data['dareText'] ?? '',
      mediaUrl: data['mediaUrl'] ?? '',
      mediaType: data['mediaType'] ?? '',
      authorId: data['authorId'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      expiresAt: data['expiresAt'] ?? Timestamp.now(),
      likedBy: List<String>.from(data['likedBy'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'dareText': dareText,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'authorId': authorId,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
      'likedBy': likedBy,
    };
  }
}
