import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';

void main() {
  test('zero strength disables every lens and strength is bounded', () {
    for (final lens in BeautyLens.all) {
      final off = lens.settings(0);
      expect(off.values.whereType<double>(), everyElement(0));
      expect(lens.settings(2), lens.settings(1));
      expect(lens.settings(-1), off);
    }
  });
}
