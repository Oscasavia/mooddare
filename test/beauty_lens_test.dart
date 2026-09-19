import 'package:flutter_test/flutter_test.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';

void main() {
  test(
    'custom controls map independently to the native photo and video effects',
    () {
      const original = CustomBeautyLook();
      final look = original
          .withAmount(BeautyAdjustment.smooth, .8)
          .withAmount(BeautyAdjustment.eyes, .35)
          .withAmount(BeautyAdjustment.face, .6);
      expect(original.isOriginal, isTrue);
      expect(look.isOriginal, isFalse);
      expect(look.settings(), {
        'smooth': .8,
        'eyeSize': .35,
        'faceSlim': .6,
        'light': 0.0,
        'warmth': 0.0,
        'makeup': 0.0,
        'original': false,
      });
      expect(
        look.withAmount(BeautyAdjustment.eyes, 0).settings()['smooth'],
        .8,
      );
      expect(
        look.withAmount(BeautyAdjustment.eyes, 0).settings()['faceSlim'],
        .6,
      );
      expect(look.settings(original: true), {
        ...look.settings(),
        'original': true,
      });
      expect(look.amount(BeautyAdjustment.eyes), .35);
    },
  );

  test(
    'custom values are finite and bounded before reaching native rendering',
    () {
      for (final amount in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1.0,
        2.0,
      ]) {
        final expected = amount.isFinite ? amount.clamp(0.0, 1.0) : 0.0;
        final look = CustomBeautyLook(
          smooth: amount,
          eyes: amount,
          face: amount,
        );
        for (final adjustment in BeautyAdjustment.values) {
          expect(look.amount(adjustment), expected);
          expect(
            const CustomBeautyLook()
                .withAmount(adjustment, amount)
                .amount(adjustment),
            expected,
          );
        }
      }
    },
  );

  test('zero strength disables every lens and strength is bounded', () {
    for (final lens in BeautyLens.all) {
      final off = lens.settings(0);
      expect(off.values.whereType<double>(), everyElement(0));
      expect(lens.settings(2), lens.settings(1));
      expect(lens.settings(-1), off);
    }
  });
}
