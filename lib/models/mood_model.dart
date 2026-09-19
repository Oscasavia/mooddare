import 'package:flutter/material.dart';

enum MoodTier {
  basic('Free'),
  gold('Gold'),
  diamond('Diamond');

  final String label;
  const MoodTier(this.label);

  static MoodTier fromPack(String pack, {bool locked = false}) =>
      switch (pack.trim().toLowerCase()) {
        'gold' || 'daring' || 'premium' => MoodTier.gold,
        'diamond' || 'epic' => MoodTier.diamond,
        _ => locked ? MoodTier.gold : MoodTier.basic,
      };
}

class MoodModel {
  final String id;
  final String name;
  final String icon;
  final String pack;
  final Color color;
  final bool isLocked;
  final List<String> dareList;
  final MoodTier tier;
  final String description;
  final String? season;

  MoodModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.pack,
    required this.color,
    required this.isLocked,
    required List<String> dareList,
    MoodTier? tier,
    this.description = '',
    this.season,
  }) : tier = tier ?? MoodTier.fromPack(pack, locked: isLocked),
       dareList = List.unmodifiable(
         dareList
             .map((dare) => dare.trim())
             .where((dare) => dare.isNotEmpty)
             .toSet(),
       );

  bool get isSeasonal => season?.trim().isNotEmpty ?? false;
  bool get isPremium => tier != MoodTier.basic;
  // No client-side purchase flag grants access. Paid entitlements are future work.
  bool get isAvailable => !isLocked && !isPremium && dareList.isNotEmpty;

  factory MoodModel.fromFirestore(Map<String, dynamic> data, String id) {
    String text(dynamic value, String fallback) =>
        value is String && value.trim().isNotEmpty ? value.trim() : fallback;
    final rawLock = data['isLocked'];
    final locked = rawLock != null && rawLock != false;
    final pack = text(data['pack'], 'basic');
    final rawTier = data['tier'];
    // Unknown explicit tiers must never accidentally become free content.
    final tier = rawTier == null
        ? MoodTier.fromPack(pack, locked: locked)
        : switch (rawTier is String ? rawTier.trim().toLowerCase() : '') {
            'basic' || 'free' => MoodTier.basic,
            'diamond' || 'epic' => MoodTier.diamond,
            _ => MoodTier.gold,
          };
    var hex = text(data['colorHex'], '').replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final color = RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)
        ? Color(int.parse(hex, radix: 16))
        : const Color(0xFFC5B4FF);
    final dares = data['dareList'];
    final season = text(data['season'], '');
    return MoodModel(
      id: id,
      name: text(data['moodName'], 'Unnamed mood'),
      icon: text(data['moodIcon'], '✨'),
      pack: pack,
      color: color,
      isLocked: locked,
      tier: tier,
      dareList: dares is List ? dares.whereType<String>().toList() : [],
      description: text(data['description'], ''),
      season: season.isEmpty ? null : season,
    );
  }
}
