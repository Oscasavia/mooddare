/// Lens strengths stay normalized; native rendering clamps every input again.
class BeautyLens {
  final String name;
  final double smooth, light, warmth, eyeSize, faceSlim, makeup;
  const BeautyLens(
    this.name, {
    this.smooth = 0,
    this.light = 0,
    this.warmth = 0,
    this.eyeSize = 0,
    this.faceSlim = 0,
    this.makeup = 0,
  });

  Map<String, Object> settings(double strength, {bool original = false}) {
    final amount = strength.clamp(0.0, 1.0);
    return {
      'smooth': smooth * amount,
      'light': light * amount,
      'warmth': warmth * amount,
      'eyeSize': eyeSize * amount,
      'faceSlim': faceSlim * amount,
      'makeup': makeup * amount,
      'original': original,
    };
  }

  static const custom = BeautyLens('My look');

  static const all = [
    BeautyLens('Original'),
    BeautyLens('Soft', smooth: .85),
    BeautyLens('Glow', smooth: .65, light: .3, warmth: .3),
    BeautyLens('Wide eyes', smooth: .35, eyeSize: 1),
    BeautyLens('Sculpt', smooth: .45, faceSlim: 1),
    BeautyLens(
      'Studio',
      smooth: .65,
      light: .15,
      warmth: .15,
      eyeSize: .65,
      faceSlim: .85,
    ),
    BeautyLens('Rosy', smooth: .4, eyeSize: .2, faceSlim: .2, makeup: 1),
    custom,
  ];
}

enum BeautyAdjustment {
  smooth('Smooth'),
  eyes('Eyes'),
  face('Face');

  final String label;
  const BeautyAdjustment(this.label);
}

/// User-controlled amounts are independent of preset lens strength.
class CustomBeautyLook {
  final double smooth, eyes, face;
  const CustomBeautyLook({this.smooth = 0, this.eyes = 0, this.face = 0});

  static double _bounded(double value) =>
      value.isFinite ? value.clamp(0.0, 1.0) : 0;

  double amount(BeautyAdjustment adjustment) => _bounded(switch (adjustment) {
    BeautyAdjustment.smooth => smooth,
    BeautyAdjustment.eyes => eyes,
    BeautyAdjustment.face => face,
  });

  bool get isOriginal => BeautyAdjustment.values.every((a) => amount(a) == 0);

  CustomBeautyLook withAmount(BeautyAdjustment adjustment, double value) =>
      CustomBeautyLook(
        smooth: adjustment == BeautyAdjustment.smooth
            ? _bounded(value)
            : smooth,
        eyes: adjustment == BeautyAdjustment.eyes ? _bounded(value) : eyes,
        face: adjustment == BeautyAdjustment.face ? _bounded(value) : face,
      );

  Map<String, Object> settings({bool original = false}) => {
    'smooth': amount(BeautyAdjustment.smooth),
    'eyeSize': amount(BeautyAdjustment.eyes),
    'faceSlim': amount(BeautyAdjustment.face),
    'light': 0.0,
    'warmth': 0.0,
    'makeup': 0.0,
    'original': original,
  };
}
