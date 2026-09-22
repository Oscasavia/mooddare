import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;

const fullPhotoCrop = Rect.fromLTWH(0, 0, 1, 1);

/// Crop coordinates always refer to the upright, full captured image.
Rect cropForRatio(Rect current, double imageRatio, double? ratio) {
  if (ratio == null) return current;
  final normalizedRatio = ratio / imageRatio;
  var width = current.width;
  var height = width / normalizedRatio;
  if (height > current.height) {
    height = current.height;
    width = height * normalizedRatio;
  }
  return Rect.fromCenter(center: current.center, width: width, height: height);
}

Rect movePhotoCrop(Rect crop, Offset delta) => Rect.fromLTWH(
  (crop.left + delta.dx).clamp(0.0, 1 - crop.width),
  (crop.top + delta.dy).clamp(0.0, 1 - crop.height),
  crop.width,
  crop.height,
);

/// The opposite corner stays anchored; locked ratios cannot leave the image.
Rect resizePhotoCrop(Rect crop, Offset delta, int corner, double? ratio) {
  final left = corner == 0 || corner == 3;
  final top = corner < 2;
  final anchor = Offset(
    left ? crop.right : crop.left,
    top ? crop.bottom : crop.top,
  );
  final maxWidth = left ? anchor.dx : 1 - anchor.dx;
  final maxHeight = top ? anchor.dy : 1 - anchor.dy;
  var width = crop.width + delta.dx * (left ? -1 : 1);
  var height = crop.height + delta.dy * (top ? -1 : 1);
  if (ratio != null) {
    final limit = math.min(maxWidth, maxHeight * ratio);
    if (delta.dy.abs() * ratio > delta.dx.abs()) width = height * ratio;
    width = width.clamp(math.min(.08, limit), limit);
    height = width / ratio;
  } else {
    width = width.clamp(math.min(.08, maxWidth), maxWidth);
    height = height.clamp(math.min(.08, maxHeight), maxHeight);
  }
  return Rect.fromLTWH(
    left ? anchor.dx - width : anchor.dx,
    top ? anchor.dy - height : anchor.dy,
    width,
    height,
  );
}

Uint8List cropPhoto(Map<String, dynamic> input) {
  final bytes = input['bytes'] as Uint8List;
  final crop = input['crop'] as Rect;
  if (![
        crop.left,
        crop.top,
        crop.right,
        crop.bottom,
      ].every((v) => v.isFinite) ||
      crop.width <= 0 ||
      crop.height <= 0 ||
      crop.left < -1e-9 ||
      crop.top < -1e-9 ||
      crop.right > 1 + 1e-9 ||
      crop.bottom > 1 + 1e-9) {
    throw const FormatException('Invalid photo crop.');
  }
  if (crop == fullPhotoCrop) return bytes;
  img.Image? source;
  try {
    source = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException('This photo could not be cropped.');
  }
  if (source == null) {
    throw const FormatException('This photo could not be cropped.');
  }
  final x = (crop.left * source.width).round().clamp(0, source.width - 1);
  final y = (crop.top * source.height).round().clamp(0, source.height - 1);
  final right = (crop.right * source.width).round().clamp(x + 1, source.width);
  final bottom = (crop.bottom * source.height).round().clamp(
    y + 1,
    source.height,
  );
  final output = img.copyCrop(
    source,
    x: x,
    y: y,
    width: right - x,
    height: bottom - y,
  );
  output.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(output, quality: 95));
}
