/// Lens strengths stay normalized; native rendering clamps every input again.
class BeautyLens {
  final String name;
  final String id;
  final double smooth, light, warmth, eyeSize, faceSlim, makeup;
  final double? lips, blush;
  final LipShade lipShade;
  const BeautyLens(
    this.name, {
    this.id = '',
    this.smooth = 0,
    this.light = 0,
    this.warmth = 0,
    this.eyeSize = 0,
    this.faceSlim = 0,
    this.makeup = 0,
    this.lips,
    this.blush,
    this.lipShade = LipShade.rose,
  });

  bool get hasMakeup => (lips ?? makeup) > 0 || (blush ?? makeup) > 0;

  Map<String, Object> settings(double strength, {bool original = false}) {
    final amount = strength.isFinite ? strength.clamp(0.0, 1.0) : 0.0;
    return {
      'smooth': smooth * amount,
      'light': light * amount,
      'warmth': warmth * amount,
      'eyeSize': eyeSize * amount,
      'faceSlim': faceSlim * amount,
      'makeup': makeup * amount,
      'lipIntensity': (lips ?? makeup) * amount,
      'blushIntensity': (blush ?? makeup) * amount,
      'lipShade': lipShade.name,
      'original': original,
    };
  }

  static const custom = BeautyLens('My look', id: 'custom');

  static const collection = [
    BeautyLens(
      'Natural',
      id: 'natural',
      smooth: .3,
      light: .06,
      lips: .16,
      blush: .16,
    ),
    BeautyLens(
      'Peach',
      id: 'peach',
      smooth: .45,
      light: .08,
      warmth: .22,
      eyeSize: .12,
      lips: .8,
      blush: .35,
      lipShade: LipShade.peach,
    ),
    BeautyLens(
      'Soft Glam',
      id: 'soft_glam',
      smooth: .5,
      light: .08,
      eyeSize: .3,
      faceSlim: .25,
      lips: .85,
      blush: .4,
      lipShade: LipShade.berry,
    ),
    BeautyLens(
      'Golden Hour',
      id: 'golden_hour',
      smooth: .35,
      light: .18,
      warmth: .55,
      lips: .35,
      blush: .22,
      lipShade: LipShade.peach,
    ),
  ];

  static const all = [
    BeautyLens('Original', id: 'original'),
    BeautyLens('Soft', id: 'soft', smooth: .85),
    BeautyLens('Glow', id: 'glow', smooth: .65, light: .3, warmth: .3),
    BeautyLens('Wide eyes', id: 'wide_eyes', smooth: .35, eyeSize: 1),
    BeautyLens('Sculpt', id: 'sculpt', smooth: .45, faceSlim: 1),
    BeautyLens(
      'Studio',
      id: 'studio',
      smooth: .65,
      light: .15,
      warmth: .15,
      eyeSize: .65,
      faceSlim: .85,
    ),
    ...collection,
    BeautyLens(
      'Rosy',
      id: 'rosy',
      smooth: .4,
      eyeSize: .2,
      faceSlim: .2,
      makeup: 1,
    ),
    custom,
  ];
}

enum BeautyAdjustment {
  smooth('Smooth'),
  eyes('Eyes'),
  face('Face'),
  lips('Lips'),
  blush('Blush');

  final String label;
  const BeautyAdjustment(this.label);
}

/// Swatches match the native palette; shade changes never change intensity.
enum LipShade {
  rose('Rose', 0xFFC23D5C),
  red('Red', 0xFFBF2433),
  berry('Berry', 0xFF8C365E),
  peach('Peach', 0xFFD97860);

  final String label;
  final int swatch;
  const LipShade(this.label, this.swatch);
}

/// User-controlled amounts are independent of preset lens strength.
class CustomBeautyLook {
  final double smooth, eyes, face, lips, blush;
  final LipShade lipShade;
  const CustomBeautyLook({
    this.smooth = 0,
    this.eyes = 0,
    this.face = 0,
    this.lips = 0,
    this.blush = 0,
    this.lipShade = LipShade.rose,
  });

  static double _bounded(double value) =>
      value.isFinite ? value.clamp(0.0, 1.0) : 0;

  double amount(BeautyAdjustment adjustment) => _bounded(switch (adjustment) {
    BeautyAdjustment.smooth => smooth,
    BeautyAdjustment.eyes => eyes,
    BeautyAdjustment.face => face,
    BeautyAdjustment.lips => lips,
    BeautyAdjustment.blush => blush,
  });

  bool get isOriginal => BeautyAdjustment.values.every((a) => amount(a) == 0);

  CustomBeautyLook withAmount(BeautyAdjustment adjustment, double value) =>
      CustomBeautyLook(
        smooth: adjustment == BeautyAdjustment.smooth
            ? _bounded(value)
            : smooth,
        eyes: adjustment == BeautyAdjustment.eyes ? _bounded(value) : eyes,
        face: adjustment == BeautyAdjustment.face ? _bounded(value) : face,
        lips: adjustment == BeautyAdjustment.lips ? _bounded(value) : lips,
        blush: adjustment == BeautyAdjustment.blush ? _bounded(value) : blush,
        lipShade: lipShade,
      );

  CustomBeautyLook withLipShade(LipShade value) => CustomBeautyLook(
    smooth: smooth,
    eyes: eyes,
    face: face,
    lips: lips,
    blush: blush,
    lipShade: value,
  );

  Map<String, Object> settings({bool original = false}) => {
    'smooth': amount(BeautyAdjustment.smooth),
    'eyeSize': amount(BeautyAdjustment.eyes),
    'faceSlim': amount(BeautyAdjustment.face),
    'light': 0.0,
    'warmth': 0.0,
    'makeup': 0.0,
    'lipIntensity': amount(BeautyAdjustment.lips),
    'blushIntensity': amount(BeautyAdjustment.blush),
    'lipShade': lipShade.name,
    'original': original,
  };
}
