import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mooddare/models/mood_model.dart';
import '../../domain/mood_catalog.dart';

class DaresRepository {
  final Future<List<MoodModel>> Function() _loadMoods;
  DaresRepository({
    FirebaseFirestore? firestore,
    Future<List<MoodModel>> Function()? loadMoods,
  }) : _loadMoods =
           loadMoods ??
           (() async {
             final snapshot = await (firestore ?? FirebaseFirestore.instance)
                 .collection('dares')
                 .limit(100)
                 .get();
             return snapshot.docs
                 .map((doc) => MoodModel.fromFirestore(doc.data(), doc.id))
                 .toList();
           });

  Future<MoodCatalog> getCatalog() async {
    try {
      final remote = await _loadMoods().timeout(const Duration(seconds: 10));
      return assemble(remote);
    } catch (_) {
      return assemble([], loadFailed: true);
    }
  }

  static MoodCatalog assemble(
    List<MoodModel> remote, {
    bool loadFailed = false,
  }) {
    // Remote entries take precedence; never duplicate a local preview of the same mood.
    final usable = remote
        .where((m) => m.isPremium || m.isLocked || m.dareList.isNotEmpty)
        .toList();
    final result = <MoodModel>[];
    final ids = <String>{};
    final names = <String>{};
    void add(MoodModel mood) {
      final name = mood.name.trim().toLowerCase();
      if (ids.contains(mood.id) || names.contains(name)) return;
      ids.add(mood.id);
      names.add(name);
      result.add(mood);
    }

    usable.forEach(add);
    if (!result.any((m) => m.isAvailable && !m.isSeasonal)) {
      starterMoods.forEach(add);
    }
    premiumPreviews.forEach(add);
    seasonalMoods.forEach(add);
    result.sort((a, b) {
      final groupA = a.isSeasonal ? 3 : a.tier.index;
      final groupB = b.isSeasonal ? 3 : b.tier.index;
      return groupA == groupB
          ? a.name.compareTo(b.name)
          : groupA.compareTo(groupB);
    });
    return MoodCatalog(result, loadFailed: loadFailed);
  }

  // Restored names from the original Daring and Epic packs. Metadata only;
  // subscriptions and paid dare delivery are not enabled by these previews.
  static final premiumPreviews = [
    for (final entry in [
      ('Brave', '🦁'),
      ('Adventurous', '🧭'),
      ('Spontaneous', '⚡'),
      ('Social', '🥳'),
      ('Rebellious', '😈'),
      ('Confident', '😎'),
      ('Romantic', '😍'),
      ('Flirty', '😉'),
    ])
      MoodModel(
        id: 'preview-daring-${entry.$1.toLowerCase()}',
        name: entry.$1,
        icon: entry.$2,
        pack: 'daring',
        color: const Color(0xFFE8C47B),
        isLocked: true,
        dareList: [],
        description: 'A new way to step outside your everyday routine.',
      ),
    for (final entry in [
      ('Spicy', '🌶️'),
      ('Mysterious', '🤫'),
      ('Legendary', '🦄'),
      ('Unstoppable', '🚀'),
      ('Visionary', '💡'),
      ('Main Character', '🌟'),
      ('Nostalgic', '📼'),
    ])
      MoodModel(
        id: 'preview-epic-${entry.$1.toLowerCase()}',
        name: entry.$1,
        icon: entry.$2,
        pack: 'epic',
        color: const Color(0xFFA7C9F5),
        isLocked: true,
        dareList: [],
        description: 'More imaginative challenges for memorable moments.',
      ),
  ];

  // Year-round collections for now; seasonal scheduling can be added separately.
  static final seasonalMoods = [
    MoodModel(
      id: 'season-christmas',
      name: 'Christmas',
      icon: '🎄',
      pack: 'basic',
      color: const Color(0xFF9DC7B2),
      isLocked: false,
      season: 'Christmas',
      description:
          'Festive details, thoughtful gestures, and a little holiday magic.',
      dareList: [
        'Capture a decoration that makes a place feel festive.',
        'Make a small handmade decoration using something you already have.',
        'Write a thoughtful holiday note for someone you appreciate.',
      ],
    ),
    MoodModel(
      id: 'season-new-year',
      name: 'New Year',
      icon: '🎆',
      pack: 'basic',
      color: const Color(0xFFC5B4FF),
      isLocked: false,
      season: 'New Year',
      description:
          'Fresh starts, favorite memories, and something to look forward to.',
      dareList: [
        'Capture one small thing you want to bring into your new year.',
        'Write a kind note to your future self.',
        'Recreate a favorite moment from the past year in a photo or short video.',
      ],
    ),
  ];

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
