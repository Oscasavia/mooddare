import 'package:flutter/material.dart';

/// Stable IDs are saved on the profile; arbitrary colors and images are not accepted.
enum ProfileCoverColor {
  lavender('Lavender', Color(0xFF594779)),
  midnight('Midnight', Color(0xFF292E46)),
  rose('Rose', Color(0xFF774B5C)),
  sage('Sage', Color(0xFF405F53)),
  ocean('Ocean', Color(0xFF355E73)),
  sunset('Sunset', Color(0xFF84573E));

  const ProfileCoverColor(this.label, this.color);
  final String label;
  final Color color;

  static ProfileCoverColor fromId(Object? value) =>
      values.firstWhere((tone) => tone.name == value, orElse: () => lavender);
  static bool isValid(Object? value) =>
      values.any((tone) => tone.name == value);
}
