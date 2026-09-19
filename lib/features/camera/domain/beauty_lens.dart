/// Lens strengths stay normalized; native rendering clamps every input again.
class BeautyLens {
  final String name;
  final double smooth, light, warmth, eyeSize, faceSlim;
  const BeautyLens(
    this.name, {
    this.smooth = 0,
    this.light = 0,
    this.warmth = 0,
    this.eyeSize = 0,
    this.faceSlim = 0,
  });

  Map<String, Object> settings(double strength, {bool original = false}) {
    final amount = strength.clamp(0.0, 1.0);
    return {
      'smooth': smooth * amount,
      'light': light * amount,
      'warmth': warmth * amount,
      'eyeSize': eyeSize * amount,
      'faceSlim': faceSlim * amount,
      'original': original,
    };
  }

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
  ];
}
