import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:mooddare/features/camera/domain/beauty_lens.dart';
import 'face_fixture.dart';
import 'live_beauty_test.dart' show channel, waitForState, capture, difference;

bool contains(List<double> polygon, double x, double y) {
  var inside = false;
  for (var i = 0, j = polygon.length - 2; i < polygon.length; j = i, i += 2) {
    final xi = polygon[i], yi = polygon[i + 1];
    final xj = polygon[j], yj = polygon[j + 1];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'mesh makeup follows lips, protects features, mirrors and survives still capture',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final cache = (await getTemporaryDirectory()).path;
      final fixture = File('$cache/mesh-portrait.jpg');
      await fixture.writeAsBytes(base64Decode(faceFixtureBase64));
      try {
        for (final front in [false, true]) {
          await channel.invokeMethod<void>('startFixture', {
            'path': fixture.path,
            'front': front,
          });
          final state = await waitForState(
            tester,
            (s) => (s['detections'] as num? ?? 0) > 0,
          );
          debugPrint(
            'Mesh fixture: face=${state['faceDetected']}, geometry=${state['geometryDetected']}, detector=${state['detectionMillis']}ms',
          );
          expect(state['geometryDetected'], isTrue);
          final geometry = (await channel.invokeMapMethod<String, dynamic>(
            'inspectFaceGeometry',
          ))!;
          final maskFile = File(geometry['path'] as String);
          final mask = img.decodePng(await maskFile.readAsBytes())!;
          await maskFile.delete();
          final bounds = (geometry['bounds'] as List)
              .map((e) => (e as num).toDouble())
              .toList();
          final polygons = (geometry['polygons'] as List)
              .map(
                (p) => (p as List).map((v) => (v as num).toDouble()).toList(),
              )
              .toList();
          var lipPixels = 0, skinPixels = 0, protectedPixels = 0;
          for (var y = 2; y < mask.height - 2; y++) {
            for (var x = 2; x < mask.width - 2; x++) {
              final p = mask.getPixel(x, y);
              if (p.r > 150) skinPixels++;
              final u = bounds[0] + (x + .5) / mask.width * bounds[2];
              final v = bounds[1] + (y + .5) / mask.height * bounds[3];
              if (p.g > 180) {
                lipPixels++;
                expect(
                  contains(polygons[5], u, v),
                  isTrue,
                  reason: 'Tint must stay in the outer lip contour',
                );
                expect(
                  contains(polygons[6], u, v),
                  isFalse,
                  reason: 'Tint must leave the mouth opening clear',
                );
              }
              if (contains(polygons[6], u, v)) {
                protectedPixels++;
                expect(
                  p.g,
                  lessThan(12),
                  reason: 'The inner mouth and teeth must be protected',
                );
              }
            }
          }
          expect(skinPixels, greaterThan(5000));
          expect(lipPixels, greaterThan(100));
          debugPrint(
            'Mask: $skinPixels skin pixels, $lipPixels lip pixels, $protectedPixels inner-mouth pixels',
          );
          await channel.invokeMethod<void>(
            'setLook',
            BeautyLens.all.first.settings(0),
          );
          final original = await capture();
          await channel.invokeMethod<void>(
            'setLook',
            const BeautyLens('Makeup only', makeup: 1).settings(1),
          );
          final tinted = await capture();
          expect(difference(original, tinted), greaterThan(.02));
          expect(
            difference(
              original,
              tinted,
              right: original.width ~/ 5,
              bottom: original.height ~/ 5,
            ),
            lessThan(.5),
          );
          var redShift = 0.0, samples = 0;
          for (var y = 0; y < original.height; y++) {
            for (var x = 0; x < original.width; x++) {
              final u = front
                  ? 1 - (x + .5) / original.width
                  : (x + .5) / original.width;
              final v = (y + .5) / original.height;
              final mx = ((u - bounds[0]) / bounds[2] * mask.width).floor();
              final my = ((v - bounds[1]) / bounds[3] * mask.height).floor();
              if (mx < 0 ||
                  my < 0 ||
                  mx >= mask.width ||
                  my >= mask.height ||
                  mask.getPixel(mx, my).g < 200) {
                continue;
              }
              final a = original.getPixel(x, y), b = tinted.getPixel(x, y);
              redShift += (b.r - b.g) - (a.r - a.g);
              samples++;
            }
          }
          expect(samples, greaterThan(10));
          expect(
            redShift / math.max(1, samples),
            greaterThan(3),
            reason: 'Lip color must change at the mirrored lip location',
          );
          final stillFile = File(
            (await channel.invokeMethod<String>('captureStillFixture'))!,
          );
          final still = img.decodeJpg(await stillFile.readAsBytes())!;
          await stillFile.delete();
          expect(difference(tinted, still), lessThan(.5));
          await channel.invokeMethod<void>(
            'setLook',
            const BeautyLens(
              'Makeup only',
              makeup: 1,
            ).settings(1, original: true),
          );
          expect(difference(original, await capture()), lessThan(.1));
          if (!front) {
            // Disposable emulator artifacts for inspecting the actual GPU output.
            await File(
              '$cache/mesh-original.jpg',
            ).writeAsBytes(img.encodeJpg(original, quality: 95));
            await channel.invokeMethod<void>(
              'setLook',
              BeautyLens.all.firstWhere((l) => l.name == 'Rosy').settings(.65),
            );
            await File(
              '$cache/mesh-rosy.jpg',
            ).writeAsBytes(img.encodeJpg(await capture(), quality: 95));
            // The integration runner removes the app afterward; allow host-side
            // visual inspection to copy the disposable images while it exists.
            await tester.pump(const Duration(seconds: 6));
          }
          await channel.invokeMethod<void>('stop');
        }
      } finally {
        await channel.invokeMethod<void>('stop');
        await fixture.delete();
      }
    },
  );

  testWidgets('open-mouth contour excludes teeth and protects eyes and brows', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final fixture = File(
      '${(await getTemporaryDirectory()).path}/open-mouth-mask.jpg',
    );
    await fixture.writeAsBytes(base64Decode(faceFixtureBase64));
    List<double> rect(double x, double y, double w, double h) => [
      x,
      y,
      x + w,
      y,
      x + w,
      y + h,
      x,
      y + h,
    ];
    final polygons = [
      rect(.25, .15, .4, .6),
      rect(.32, .35, .08, .04),
      rect(.5, .35, .08, .04),
      rect(.31, .3, .1, .025),
      rect(.49, .3, .1, .025),
      rect(.36, .55, .18, .14),
      rect(.4, .59, .1, .065),
    ];
    try {
      await channel.invokeMethod<void>('startFixture', {
        'path': fixture.path,
        'front': false,
      });
      final result = (await channel.invokeMapMethod<String, dynamic>(
        'inspectFaceGeometry',
        {'polygons': polygons},
      ))!;
      final maskFile = File(result['path'] as String);
      final mask = img.decodePng(await maskFile.readAsBytes())!;
      await maskFile.delete();
      final bounds = (result['bounds'] as List).cast<num>();
      var mouthPixels = 0, lipPixels = 0;
      for (var y = 0; y < mask.height; y++) {
        for (var x = 0; x < mask.width; x++) {
          final u = (bounds[0] + (x + .5) / mask.width * bounds[2]).toDouble();
          final v = (bounds[1] + (y + .5) / mask.height * bounds[3]).toDouble();
          final pixel = mask.getPixel(x, y);
          if (contains(polygons[6], u, v)) {
            mouthPixels++;
            expect(pixel.g, lessThan(12));
            expect(pixel.r, lessThan(12));
          }
          if (pixel.g > 180) lipPixels++;
        }
      }
      expect(mouthPixels, greaterThan(1000));
      expect(lipPixels, greaterThan(2000));
      for (final region in [1, 2, 3, 4]) {
        final p = polygons[region];
        final x = (((p[0] + p[4]) / 2 - bounds[0]) / bounds[2] * mask.width)
            .floor();
        final y = (((p[1] + p[5]) / 2 - bounds[1]) / bounds[3] * mask.height)
            .floor();
        expect(mask.getPixel(x, y).r, lessThan(12));
        expect(mask.getPixel(x, y).g, lessThan(12));
      }
    } finally {
      await channel.invokeMethod<void>('stop');
      await fixture.delete();
    }
  });
}
