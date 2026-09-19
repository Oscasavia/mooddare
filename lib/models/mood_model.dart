// lib/models/mood_model.dart
import 'package:flutter/material.dart';

class MoodModel {
  final String id;
  final String name;
  final String icon;
  final String pack;
  final Color color;
  final bool isLocked;
  final List<String> dareList;

  MoodModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.pack,
    required this.color,
    required this.isLocked,
    required this.dareList,
  });

  factory MoodModel.fromFirestore(Map<String, dynamic> data, String id) {
    // Helper to parse color from hex string
    Color colorFromHex(String hexColor) {
      hexColor = hexColor.toUpperCase().replaceAll("#", "");
      if (hexColor.length == 6) {
        hexColor = "FF$hexColor";
      }
      return Color(int.tryParse(hexColor, radix: 16) ?? 0xFFC5B4FF);
    }

    return MoodModel(
      id: id,
      name: data['moodName'] ?? 'Unnamed',
      icon: data['moodIcon'] ?? '❓',
      pack: data['pack'] ?? 'basic',
      color: colorFromHex(data['colorHex'] ?? 'FFFFFFFF'),
      isLocked: data['isLocked'] ?? false,
      dareList: List<String>.from(data['dareList'] ?? []),
    );
  }
}
