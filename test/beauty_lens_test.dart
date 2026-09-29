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

  test(
    'curated looks blend independent makeup and preserve established presets',
    () {
      expect(BeautyLens.collection.map((l) => l.name), [
        'Natural',
        'Peach',
        'Soft Glam',
        'Golden Hour',
      ]);
      expect(
        BeautyLens.all.map((l) => l.name).toSet().length,
        BeautyLens.all.length,
      );
      final natural = BeautyLens.collection.first;
      expect(natural.eyeSize, 0);
      expect(natural.faceSlim, 0);
      for (final lens in BeautyLens.collection) {
        expect(BeautyLens.all, contains(lens));
        expect(lens.hasMakeup, isTrue);
        final half = lens.settings(.5);
        expect(half['lipIntensity'], lens.lips! * .5);
        expect(half['blushIntensity'], lens.blush! * .5);
        expect(half['lipShade'], lens.lipShade.name);
        expect(half['eyeSize'], lens.eyeSize * .5);
        expect(half['faceSlim'], lens.faceSlim * .5);
        expect(half['original'], isFalse);
        expect(lens.settings(.5, original: true), {...half, 'original': true});
        expect(lens.settings(double.nan), lens.settings(0));
        expect(lens.settings(double.infinity), lens.settings(0));
      }
      final rosy = BeautyLens.all
          .firstWhere((l) => l.name == 'Rosy')
          .settings(.65);
      expect(rosy['makeup'], .65);
      expect(rosy['lipIntensity'], .65);
      expect(rosy['blushIntensity'], .65);
      expect(rosy['lipShade'], 'rose');
      for (final lens in BeautyLens.all.where((l) => !l.hasMakeup)) {
        expect(lens.settings(1)['lipIntensity'], 0);
        expect(lens.settings(1)['blushIntensity'], 0);
        expect(lens.settings(1)['lipShade'], 'rose');
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
