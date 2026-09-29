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
        'lipIntensity': 0.0,
        'blushIntensity': 0.0,
        'lipShade': 'rose',
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
          lips: amount,
          blush: amount,
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

  test('lip shade and blush remain independent of each other and shaping', () {
    for (final shade in LipShade.values) {
      final look = const CustomBeautyLook(smooth: .4, eyes: .3, face: .2)
          .withAmount(BeautyAdjustment.lips, .8)
          .withAmount(BeautyAdjustment.blush, .25)
          .withLipShade(shade);
      expect(look.settings()['lipShade'], shade.name);
      expect(look.settings()['lipIntensity'], .8);
      expect(look.settings()['blushIntensity'], .25);
      expect(look.settings()['eyeSize'], .3);
      expect(look.settings()['smooth'], .4);
      expect(look.settings()['faceSlim'], .2);
      expect(look.withAmount(BeautyAdjustment.lips, 0).blush, .25);
      expect(look.withAmount(BeautyAdjustment.blush, 0).lipShade, shade);
      expect(look.settings(original: true)['original'], isTrue);
    }
    expect(const CustomBeautyLook(lips: .1).isOriginal, isFalse);
    expect(const CustomBeautyLook(blush: .1).isOriginal, isFalse);
    expect(const CustomBeautyLook(lipShade: LipShade.red).isOriginal, isTrue);
  });

  test('zero strength disables every lens and strength is bounded', () {
    for (final lens in BeautyLens.all) {
      final off = lens.settings(0);
      expect(off.values.whereType<double>(), everyElement(0));
      expect(lens.settings(2), lens.settings(1));
      expect(lens.settings(-1), off);
    }
  });
}
