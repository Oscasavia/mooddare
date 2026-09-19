// lib/models/user_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserModel {
  final String id;
  final String? email;
  final String? bio;
  final String? name;
  final String? username;
  final String? photoUrl;
  final Timestamp createdAt;

  UserModel({
    required this.id,
    this.email,
    this.bio,
    this.name,
    this.username,
    this.photoUrl,
    required this.createdAt,
  });

  // ADD THIS FACTORY CONSTRUCTOR
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      email: data['email'],
      bio: data['bio'],
      name: data['name'],
      username: data['username'],
      photoUrl: data['photoUrl'],
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  factory UserModel.fromFirebaseUser(
    User user, {
    String? name,
    String? username,
  }) {
    return UserModel(
      id: user.uid,
      email: user.email,
      name: name ?? user.displayName,
      username: username,
      photoUrl: user.photoURL,
      createdAt: Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'bio': bio,
      'name': name,
      'username': username,
      'photoUrl': photoUrl,
      'createdAt': createdAt,
    };
  }
}
