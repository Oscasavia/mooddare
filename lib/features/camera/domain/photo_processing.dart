import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Pixel processing stays in a background isolate. Coordinates are normalized
/// against the upright image, never the mirrored camera preview.
class PhotoAdjustments {
  final double smoothing;
  final double brightness;
  final double warmth;
  const PhotoAdjustments({
    this.smoothing = 0,
    this.brightness = 0,
    this.warmth = 0,
  });

  PhotoAdjustments copyWith({
    double? smoothing,
    double? brightness,
    double? warmth,
  }) => PhotoAdjustments(
    smoothing: smoothing ?? this.smoothing,
    brightness: brightness ?? this.brightness,
    warmth: warmth ?? this.warmth,
  );
}

Uint8List normalizePhoto(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException('This photo could not be opened.');
  }
  if (decoded == null) {
    throw const FormatException('This photo could not be opened.');
  }
  var image = img.bakeOrientation(decoded);
  // Bound memory and processing cost on older phones. Never upscale a photo.
  if (math.max(image.width, image.height) > 2048) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 2048 : null,
      height: image.height > image.width ? 2048 : null,
      interpolation: img.Interpolation.average,
    );
  }
  // Strip camera/location metadata after baking the orientation.
  image.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

double _ellipse(
  double x,
  double y,
  double cx,
  double cy,
  double rx,
  double ry,
) =>
    math.pow((x - cx) / rx, 2).toDouble() +
    math.pow((y - cy) / ry, 2).toDouble();

/// A feathered face mask protects the background, hairline, eyes and lips.
/// This deliberately avoids skin-color thresholds, which can exclude skin tones.
double faceMask(double x, double y, Map<String, dynamic> face) {
  final left = (face['x'] as num).toDouble();
  final top = (face['y'] as num).toDouble();
  final width = (face['width'] as num).toDouble();
  final height = (face['height'] as num).toDouble();
  if (width <= 0 || height <= 0) return 0;
  final distance = _ellipse(
    x,
    y,
    left + width * .5,
    top + height * .53,
    width * .44,
    height * .43,
  );
  var mask = ((1 - distance) / .25).clamp(0.0, 1.0);
  for (final key in ['leftEye', 'rightEye', 'mouth', 'nose']) {
    final point = face[key] as List<dynamic>?;
    if (point == null) continue;
    final d = _ellipse(
      x,
      y,
      (point[0] as num).toDouble(),
      (point[1] as num).toDouble(),
      width * (key == 'mouth' ? .29 : .19),
      height * (key == 'mouth' ? .13 : .10),
    );
    mask *= ((d - 1) / .65).clamp(0.0, 1.0);
  }
  return mask;
}

/// Precompute one edge-preserving bilateral pass; slider changes only blend it.
/// PNG preserves exact unchanged pixels between this pass and final export.
Uint8List smoothPhoto(Map<String, dynamic> input) {
  final source = img.decodeImage(input['bytes'] as Uint8List)!;
  final face = input['face'] as Map<String, dynamic>?;
  if (face == null) return Uint8List.fromList(img.encodePng(source));
  final output = img.Image.from(source);
  final step = math.max(1, (source.width / 450).round());
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final mask = faceMask(x / source.width, y / source.height, face);
      if (mask == 0) continue;
      final center = source.getPixel(x, y);
      final cr = center.r.toDouble(),
          cg = center.g.toDouble(),
          cb = center.b.toDouble();
      var red = 0.0, green = 0.0, blue = 0.0, total = 0.0;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final pixel = source.getPixel(
            (x + dx * step).clamp(0, source.width - 1),
            (y + dy * step).clamp(0, source.height - 1),
          );
          final dr = pixel.r - cr, dg = pixel.g - cg, db = pixel.b - cb;
          final weight = math.exp(
            -(dx * dx + dy * dy) / 5.0 - (dr * dr + dg * dg + db * db) / 1800.0,
          );
          red += pixel.r * weight;
          green += pixel.g * weight;
          blue += pixel.b * weight;
          total += weight;
        }
      }
      output.setPixelRgb(
        x,
        y,
        cr + (red / total - cr) * mask,
        cg + (green / total - cg) * mask,
        cb + (blue / total - cb) * mask,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(output));
}

Uint8List renderPhoto(Map<String, dynamic> input) {
  final original = img.decodeImage(input['original'] as Uint8List)!;
  final smooth = img.decodeImage(input['smooth'] as Uint8List)!;
  final settings = input['settings'] as PhotoAdjustments;
  final strength = settings.smoothing.clamp(0.0, 1.0);
  final exposure = math.pow(2, settings.brightness.clamp(-1.0, 1.0) * .6);
  final warmth = settings.warmth.clamp(-1.0, 1.0) * 14;
  for (var y = 0; y < original.height; y++) {
    for (var x = 0; x < original.width; x++) {
      final p = original.getPixel(x, y), s = smooth.getPixel(x, y);
      original.setPixelRgb(
        x,
        y,
        ((p.r + (s.r - p.r) * strength) * exposure + warmth).clamp(0, 255),
        ((p.g + (s.g - p.g) * strength) * exposure).clamp(0, 255),
        ((p.b + (s.b - p.b) * strength) * exposure - warmth).clamp(0, 255),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(original, quality: 93));
}
