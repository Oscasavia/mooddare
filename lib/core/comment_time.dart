/// Compact comment ages use local calendar days so “Yesterday” stays meaningful
/// across midnight and daylight-saving changes. Future device clocks clamp to now.
String commentTime(DateTime createdAt, DateTime now) {
  final created = createdAt.toLocal();
  final current = now.toLocal();
  final age = current.difference(created);
  if (age.inSeconds < 60) return 'Just now';
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(created.year, created.month, created.day);
  if (day == today) return '${age.inHours}h';
  if (day == DateTime(current.year, current.month, current.day - 1)) {
    return 'Yesterday';
  }
  return '${created.month}/${created.day}/${created.year}';
}
