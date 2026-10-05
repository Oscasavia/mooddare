import 'package:cloud_firestore/cloud_firestore.dart';

class PostModel {
  final String id;
  final String? moodId, moodName;
  final String dareText;
  final String mediaUrl;
  final String mediaType;
  final String authorId;
  final bool deleting;
  final int shareCount;
  final Timestamp createdAt;
  final Timestamp expiresAt;
  final List<String> likedBy; // Changed from reactions map

  PostModel({
    required this.id,
    this.moodId,
    this.moodName,
    required this.dareText,
    required this.mediaUrl,
    required this.mediaType,
    required this.authorId,
    this.deleting = false,
    this.shareCount = 0,
    required this.createdAt,
    required this.expiresAt,
    required this.likedBy,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PostModel(
      id: doc.id,
      moodId: data['moodId'] as String?,
      moodName: data['moodName'] as String?,
      dareText: data['dareText'] ?? '',
      mediaUrl: data['mediaUrl'] ?? '',
      mediaType: data['mediaType'] ?? '',
      authorId: data['authorId'] ?? '',
      deleting: data['deleting'] == true,
      shareCount: data['shareCount'] is int && data['shareCount'] >= 0
          ? data['shareCount']
          : 0,
      createdAt: data['createdAt'] ?? Timestamp.now(),
      expiresAt: data['expiresAt'] ?? Timestamp.now(),
      likedBy: List<String>.from(data['likedBy'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'dareText': dareText,
      if (moodId != null) 'moodId': moodId,
      if (moodName != null) 'moodName': moodName,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'authorId': authorId,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
      'likedBy': likedBy,
    };
  }
}
