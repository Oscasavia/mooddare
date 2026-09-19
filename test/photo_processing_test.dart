import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mooddare/features/camera/domain/photo_processing.dart';

void main() {
  final face = <String, dynamic>{
    'x': .1,
    'y': .1,
    'width': .8,
    'height': .8,
    'leftEye': [.35, .38],
    'rightEye': [.65, .38],
    'mouth': [.5, .73],
    'nose': [.5, .53],
  };
  test('mask excludes background, eyes and lips and includes cheeks', () {
    expect(faceMask(.01, .01, face), 0);
    expect(faceMask(.35, .38, face), 0);
    expect(faceMask(.5, .73, face), 0);
    expect(faceMask(.29, .56, face), greaterThan(0));
  });
  test('normalization rejects corrupt files and bounds image dimensions', () {
    expect(
      () => normalizePhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    final bytes = normalizePhoto(
      Uint8List.fromList(img.encodePng(img.Image(width: 2560, height: 1280))),
    );
    final image = img.decodeJpg(bytes)!;
    expect(image.width, 2048);
    expect(image.height, 1024);
  });
  test('normalization bakes EXIF rotation and removes camera metadata', () {
    final source = img.Image(width: 60, height: 40);
    source.exif.imageIfd.orientation = 6;
    source.exif.imageIfd.make = 'Test camera';
    final result = img.decodeJpg(
      normalizePhoto(Uint8List.fromList(img.encodeJpg(source))),
    )!;
    expect(result.width, 40);
    expect(result.height, 60);
    expect(result.exif.imageIfd.make, isNull);
    expect(result.exif.imageIfd.orientation, isNull);
  });
  test('no detected face leaves decoded pixels unchanged', () {
    final image = img.Image(width: 32, height: 32);
    img.fill(image, color: img.ColorRgb8(90, 120, 150));
    final bytes = Uint8List.fromList(img.encodePng(image));
    final result = img.decodePng(smoothPhoto({'bytes': bytes, 'face': null}))!;
    expect(result.getBytes(), image.getBytes());
  });
  test(
    'smoothing reduces small cheek variations without changing protected pixels',
    () {
      final source = img.Image(width: 100, height: 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          final noise = (x + y).isEven ? 8 : -8;
          source.setPixelRgb(x, y, 140 + noise, 100 + noise, 85 + noise);
        }
      }
      final result = img.decodePng(
        smoothPhoto({
          'bytes': Uint8List.fromList(img.encodePng(source)),
          'face': face,
        }),
      )!;
      expect(
        (result.getPixel(29, 56).r - result.getPixel(30, 56).r).abs(),
        lessThan(16),
      );
      expect(result.getPixel(1, 1).r, source.getPixel(1, 1).r);
      expect(result.getPixel(35, 38).r, source.getPixel(35, 38).r);
      expect(result.getPixel(50, 73).r, source.getPixel(50, 73).r);
    },
  );
  test(
    'zero strength preserves tone; warmth changes red and blue in opposite directions',
    () {
      final source = img.Image(width: 16, height: 16);
      img.fill(source, color: img.ColorRgb8(100, 100, 100));
      final bytes = Uint8List.fromList(img.encodePng(source));
      img.Image render(PhotoAdjustments settings) => img.decodeJpg(
        renderPhoto({'original': bytes, 'smooth': bytes, 'settings': settings}),
      )!;
      final neutral = render(const PhotoAdjustments()).getPixel(8, 8);
      expect(neutral.r, closeTo(100, 2));
      final warm = render(const PhotoAdjustments(warmth: 1)).getPixel(8, 8);
      expect(warm.r, greaterThan(warm.b));
      expect(
        render(const PhotoAdjustments(brightness: 1)).getPixel(8, 8).r,
        greaterThan(neutral.r),
      );
    },
  );
}
