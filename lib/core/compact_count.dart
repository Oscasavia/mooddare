/// One decimal place, without rounding up an engagement milestone.
String compactCount(int count) {
  if (count < 1000) return '${count < 0 ? 0 : count}';
  final (unit, suffix) = count >= 1000000000
      ? (1000000000, 'b')
      : count >= 1000000
      ? (1000000, 'm')
      : (1000, 'k');
  final tenths = count * 10 ~/ unit;
  final fraction = tenths % 10;
  return '${tenths ~/ 10}${fraction == 0 ? '' : '.$fraction'}$suffix';
}
