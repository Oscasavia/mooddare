import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/models/mood_model.dart';

class DaresRepository {
  final FirebaseFirestore _firestore;
  DaresRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  Future<Map<String, List<MoodModel>>> getDarePacks() async {
    final snapshot = await _firestore.collection('dares').limit(100).get();
    final moods = snapshot.docs
        .map((doc) => MoodModel.fromFirestore(doc.data(), doc.id))
        .toList();
    return {
      'basic': moods.isEmpty
          ? starterMoods
          : moods.where((m) => !m.isLocked && m.dareList.isNotEmpty).toList(),
    };
  }

  // A useful local starter collection, not a database-writing seed operation.
  static final starterMoods = [
    MoodModel(
      id: 'creative',
      name: 'Creative',
      icon: '🎨',
      pack: 'basic',
      color: const Color(0xFFBCA7F3),
      isLocked: false,
      dareList: [
        'Turn three things on your desk into a tiny sculpture.',
        'Photograph something ordinary from an unexpected angle.',
        'Draw your mood without lifting your pen.',
      ],
    ),
    MoodModel(
      id: 'happy',
      name: 'Happy',
      icon: '☀️',
      pack: 'basic',
      color: const Color(0xFFF0CE7D),
      isLocked: false,
      dareList: [
        'Capture something that made you smile today.',
        'Dance to the chorus of your favorite song.',
        'Send a friend a specific compliment.',
      ],
    ),
    MoodModel(
      id: 'chill',
      name: 'Chill',
      icon: '🌿',
      pack: 'basic',
      color: const Color(0xFF9DC7B2),
      isLocked: false,
      dareList: [
        'Make your favorite drink and take a quiet moment.',
        'Find a little patch of nature and photograph it.',
        'Stretch gently for one minute.',
      ],
    ),
    MoodModel(
      id: 'curious',
      name: 'Curious',
      icon: '🔭',
      pack: 'basic',
      color: const Color(0xFF9EBCE8),
      isLocked: false,
      dareList: [
        'Find an object you have never noticed in your room.',
        'Learn one new word and use it in a sentence.',
        'Photograph an interesting shadow.',
      ],
    ),
    MoodModel(
      id: 'silly',
      name: 'Silly',
      icon: '🪩',
      pack: 'basic',
      color: const Color(0xFFE9A9BD),
      isLocked: false,
      dareList: [
        'Give an everyday object a dramatic movie introduction.',
        'Draw a self-portrait with your other hand.',
        'Invent a five-second celebration dance.',
      ],
    ),
    MoodModel(
      id: 'energized',
      name: 'Energized',
      icon: '⚡',
      pack: 'basic',
      color: const Color(0xFFF0B38D),
      isLocked: false,
      dareList: [
        'Tidy one small corner and capture the result.',
        'Take a short walk and find three different colors.',
        'Try a new pose for your next selfie.',
      ],
    ),
  ];
}
